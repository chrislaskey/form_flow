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
end
