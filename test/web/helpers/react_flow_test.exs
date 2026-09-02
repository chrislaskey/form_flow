defmodule FormFlow.Web.Helpers.ReactFlowTest do
  use ExUnit.Case, async: true

  alias FormFlow.Web.Helpers.ReactFlow

  @node %{
    id: "1",
    type: "step",
    position: %{x: 240, y: 0},
    data: %{label: "Start", kind: "start", fields: 0}
  }

  @edge %{id: "e1-2", source: "1", target: "2", markerEnd: %{type: "arrowclosed"}}

  defp encode(data), do: data |> ReactFlow.to_json() |> Jason.decode!()

  describe "to_json/1" do
    test "keeps existing node UUIDs stable — form-instance paths depend on it" do
      id = Ecto.UUID.generate()

      %{nodes: [saved]} = ReactFlow.to_flow_attrs(%{"nodes" => [%{"id" => id}], "edges" => []})

      assert saved.id == id
    end

    test "passes a node through unchanged" do
      assert %{"nodes" => [node]} = encode(%{nodes: [@node], edges: []})

      assert node == %{
               "id" => "1",
               "type" => "step",
               "position" => %{"x" => 240, "y" => 0},
               "data" => %{"label" => "Start", "kind" => "start", "fields" => 0}
             }
    end

    test "passes an edge through unchanged, camel case included" do
      assert %{"edges" => [edge]} = encode(%{nodes: [], edges: [@edge]})

      assert edge == %{
               "id" => "e1-2",
               "source" => "1",
               "target" => "2",
               "markerEnd" => %{"type" => "arrowclosed"}
             }
    end

    test "adds nothing to a minimal node" do
      minimal = %{id: "1", position: %{x: 0, y: 0}, data: %{}}

      assert %{"nodes" => [node]} = encode(%{nodes: [minimal], edges: []})

      # No injected type, no defaulted data keys
      assert Map.keys(node) == ["data", "id", "position"]
    end

    test "does not invent edges between nodes" do
      two_nodes = [@node, %{@node | id: "2", position: %{x: 240, y: 140}}]

      assert encode(%{nodes: two_nodes, edges: []})["edges"] == []
    end

    test "passes through ReactFlow options this module knows nothing about" do
      decorated_node = Map.merge(@node, %{draggable: false, hidden: false, zIndex: 10})
      decorated_edge = Map.merge(@edge, %{animated: true, label: "yes", sourceHandle: "a"})

      assert %{"nodes" => [node], "edges" => [edge]} =
               encode(%{nodes: [decorated_node], edges: [decorated_edge]})

      assert node["draggable"] == false
      assert node["zIndex"] == 10
      assert edge["animated"] == true
      assert edge["sourceHandle"] == "a"
      assert edge["label"] == "yes"
    end

    test "keeps top-level keys other than nodes and edges" do
      assert encode(%{nodes: [], edges: [], viewport: %{x: 0, y: 0, zoom: 1.5}})["viewport"] ==
               %{"x" => 0, "y" => 0, "zoom" => 1.5}
    end

    test "preserves the order nodes and edges were given in" do
      nodes = for id <- ["c", "a", "b"], do: %{@node | id: id}

      assert encode(%{nodes: nodes, edges: []})["nodes"] |> Enum.map(& &1["id"]) == [
               "c",
               "a",
               "b"
             ]
    end

    test "an empty diagram is allowed" do
      assert encode(%{nodes: [], edges: []}) == %{"nodes" => [], "edges" => []}
    end

    test "rejects anything that is not a map" do
      assert_raise FunctionClauseError, fn -> ReactFlow.to_json([@node]) end
    end
  end

  describe "to_flow_attrs/1" do
    test "a node's map becomes its properties, minus the id" do
      %{nodes: [node]} =
        ReactFlow.to_flow_attrs(%{
          "nodes" => [
            %{
              "id" => "1",
              "type" => "step",
              "position" => %{"x" => 240, "y" => 0},
              "data" => %{"label" => "Start"}
            }
          ],
          "edges" => []
        })

      assert node.properties == %{
               "type" => "step",
               "position" => %{"x" => 240, "y" => 0},
               "data" => %{"label" => "Start"}
             }
    end

    test "editor ids become UUIDs; existing UUIDs are kept" do
      existing = Ecto.UUID.generate()

      %{nodes: [kept, fresh], id_map: id_map} =
        ReactFlow.to_flow_attrs(%{
          "nodes" => [%{"id" => existing}, %{"id" => "4"}],
          "edges" => []
        })

      assert kept.id == existing
      assert {:ok, _} = Ecto.UUID.cast(fresh.id)
      refute fresh.id == existing

      # id_map is how a caller learns what a temporary editor id was saved as
      assert id_map[existing] == existing
      assert id_map["4"] == fresh.id
    end

    test "edges follow their nodes through the id mapping" do
      %{nodes: [start, form], relationships: [relationship]} =
        ReactFlow.to_flow_attrs(%{
          "nodes" => [%{"id" => "1"}, %{"id" => "2"}],
          "edges" => [
            %{
              "id" => "e1-2",
              "source" => "1",
              "target" => "2",
              "markerEnd" => %{"type" => "arrowclosed"}
            }
          ]
        })

      assert relationship.source_id == start.id
      assert relationship.target_id == form.id
      assert relationship.label == "CONNECTS_TO"
      assert relationship.properties == %{"markerEnd" => %{"type" => "arrowclosed"}}
    end

    test "accepts atom keys, the shape flows are written in Elixir" do
      %{nodes: [node, _form], relationships: [relationship]} =
        ReactFlow.to_flow_attrs(%{
          nodes: [%{id: "1", position: %{x: 0, y: 0}}, %{id: "2", position: %{x: 0, y: 100}}],
          edges: [%{id: "e1-2", source: "1", target: "2"}]
        })

      assert node.properties["position"] == %{"x" => 0, "y" => 0}
      assert {:ok, _} = Ecto.UUID.cast(relationship.source_id)
    end

    test "missing nodes or edges default to empty" do
      assert ReactFlow.to_flow_attrs(%{}) == %{nodes: [], relationships: [], id_map: %{}}
    end
  end

  describe "to_data/1" do
    test "is the inverse of to_flow_attrs/1" do
      attrs =
        ReactFlow.to_flow_attrs(%{
          "nodes" => [
            %{"id" => "1", "type" => "step", "position" => %{"x" => 240, "y" => 0}},
            %{"id" => "2", "type" => "step", "position" => %{"x" => 240, "y" => 140}}
          ],
          "edges" => [%{"id" => "e1-2", "source" => "1", "target" => "2"}]
        })

      flow = %FormFlow.Data.Templates.Flow{
        id: Ecto.UUID.generate(),
        nodes:
          Enum.map(attrs.nodes, fn node ->
            %FormFlow.Data.Templates.Flow.Node{id: node.id, properties: node.properties}
          end),
        relationships:
          Enum.map(attrs.relationships, fn relationship ->
            %FormFlow.Data.Templates.Flow.Relationship{
              id: relationship.id,
              source_id: relationship.source_id,
              target_id: relationship.target_id,
              label: relationship.label,
              properties: relationship.properties
            }
          end)
      }

      data = ReactFlow.to_data(flow)

      assert [%{"id" => id, "type" => "step", "position" => %{"x" => 240}} | _] = data.nodes
      assert {:ok, _} = Ecto.UUID.cast(id)

      assert [%{"source" => source, "target" => target}] = data.edges
      assert source == hd(data.nodes)["id"]
      assert target == Enum.at(data.nodes, 1)["id"]

      # And saving what to_data produced changes nothing: ids are stable.
      # id_map itself isn't part of that invariant — this second call's ids
      # are already UUIDs, so it's the identity map, unlike the temporary-id
      # mapping the first call produced.
      round_tripped = ReactFlow.to_flow_attrs(data)
      assert round_tripped.nodes == attrs.nodes
      assert round_tripped.relationships == attrs.relationships
    end

    test "projects the embedded flow's form_flow_type into a subflow node's data" do
      node = %FormFlow.Data.Templates.Flow.Node{
        id: Ecto.UUID.generate(),
        properties: %{"type" => "subflow", "data" => %{"label" => "Collect address"}},
        subflow: %FormFlow.Data.Templates.Flow{
          properties: %{"form_flow_type" => "wizard_any_order"}
        }
      }

      flow = %FormFlow.Data.Templates.Flow{nodes: [node], relationships: []}

      assert [%{"data" => data}] = ReactFlow.to_data(flow).nodes
      assert data["form_flow_type"] == "wizard_any_order"
      assert data["label"] == "Collect address"
    end

    test "projects the collected form's form_type into a form node's data" do
      node = %FormFlow.Data.Templates.Flow.Node{
        id: Ecto.UUID.generate(),
        properties: %{"type" => "step", "data" => %{"label" => "Review", "kind" => "form"}},
        form: %FormFlow.Data.Templates.Form{properties: %{"form_type" => "review"}}
      }

      untyped = %FormFlow.Data.Templates.Flow.Node{
        id: Ecto.UUID.generate(),
        properties: %{"type" => "step", "data" => %{"label" => "Intake", "kind" => "form"}},
        form: %FormFlow.Data.Templates.Form{properties: %{}}
      }

      flow = %FormFlow.Data.Templates.Flow{nodes: [node, untyped], relationships: []}

      assert [%{"data" => typed}, %{"data" => plain}] = ReactFlow.to_data(flow).nodes
      assert typed["form_type"] == "review"
      refute Map.has_key?(plain, "form_type")
    end

    test "projects the backing entity's name into a node's data.label" do
      subflow_node = %FormFlow.Data.Templates.Flow.Node{
        id: Ecto.UUID.generate(),
        properties: %{"type" => "subflow", "data" => %{"label" => "Stale label"}},
        subflow: %FormFlow.Data.Templates.Flow{name: "Collect address"}
      }

      form_node = %FormFlow.Data.Templates.Flow.Node{
        id: Ecto.UUID.generate(),
        properties: %{"type" => "step", "data" => %{"label" => "Stale label", "kind" => "form"}},
        form: %FormFlow.Data.Templates.Form{name: "W-2 Details"}
      }

      flow = %FormFlow.Data.Templates.Flow{nodes: [subflow_node, form_node], relationships: []}

      assert [
               %{"data" => %{"label" => "Collect address"}},
               %{"data" => %{"label" => "W-2 Details"}}
             ] =
               ReactFlow.to_data(flow).nodes
    end

    test "an entity-less or unloaded node keeps its stored label" do
      # Start/End steps have no backing entity; associations as built are
      # %Ecto.Association.NotLoaded{} — to_data must not require the preload
      node = %FormFlow.Data.Templates.Flow.Node{
        id: Ecto.UUID.generate(),
        properties: %{"type" => "step", "data" => %{"label" => "Start", "kind" => "start"}}
      }

      flow = %FormFlow.Data.Templates.Flow{nodes: [node], relationships: []}

      assert [%{"data" => %{"label" => "Start"}}] = ReactFlow.to_data(flow).nodes
    end

    test "projects nothing from an untyped or unloaded subflow" do
      untyped = %FormFlow.Data.Templates.Flow.Node{
        id: Ecto.UUID.generate(),
        properties: %{"type" => "subflow", "data" => %{"label" => "Untyped"}},
        subflow: %FormFlow.Data.Templates.Flow{properties: %{}}
      }

      # %Ecto.Association.NotLoaded{}, as built — to_data must not require
      # the preload
      unloaded = %FormFlow.Data.Templates.Flow.Node{
        id: Ecto.UUID.generate(),
        properties: %{"type" => "subflow", "data" => %{"label" => "Unloaded"}}
      }

      flow = %FormFlow.Data.Templates.Flow{nodes: [untyped, unloaded], relationships: []}

      for %{"data" => data} <- ReactFlow.to_data(flow).nodes do
        refute Map.has_key?(data, "form_flow_type")
      end
    end
  end
end
