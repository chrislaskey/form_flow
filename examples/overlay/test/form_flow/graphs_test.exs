defmodule Demo.FormFlowGraphsTest do
  @moduledoc """
  Exercises `FormFlow.Data.Graphs` and the graph schemas against a real database —
  the library's own tests stop at changesets, so this is where the V01 graph DDL
  (foreign keys, cascades, the unique relationship index) is proven to hold.
  """

  use Demo.DataCase, async: false

  alias FormFlow.Data.Repo, as: FormFlowRepo
  alias FormFlow.Data.Graph
  alias FormFlow.Data.Graphs

  test "create, get, update, and delete a graph" do
    assert {:ok, %Graph{id: id}} = Graphs.create()

    assert %Graph{id: ^id, nodes: [], relationships: []} = Graphs.get(id)

    assert {:ok, %Graph{id: ^id}} = Graphs.update(Graphs.get(id), %{})

    assert {:ok, _} = Graphs.delete(Graphs.get(id))
    assert Graphs.get(id) == nil
  end

  test "list returns graphs with counts, without loading their contents" do
    {:ok, first} = Graphs.create()
    {:ok, second} = Graphs.create()

    start = insert_node(first)
    form = insert_node(first)
    insert_relationship(first, start, form)

    assert [%Graph{id: a}, %Graph{id: b}] = Graphs.list()
    assert {a, b} == {first.id, second.id}

    assert [
             %Graph{nodes_count: 2, relationships_count: 1},
             %Graph{nodes_count: 0, relationships_count: 0}
           ] = Graphs.list()

    assert [%Graph{nodes: %Ecto.Association.NotLoaded{}} | _] = Graphs.list()

    # Owned subflow children live inside their root — never listed beside it
    {:ok, _child} = Graphs.create(%{owner_graph_id: first.id})
    assert length(Graphs.list()) == 2
  end

  test "get loads nodes and relationships, round-tripping labels and properties" do
    {:ok, graph} = Graphs.create()

    start = insert_node(graph, ["Step", "Start"], %{"label" => "Start"})
    form = insert_node(graph, ["Step"], %{"label" => "Form", "fields" => 4})
    insert_relationship(graph, start, form, %{"if" => "always"})

    assert %Graph{nodes: nodes, relationships: [relationship]} = Graphs.get(graph.id)

    assert length(nodes) == 2
    assert Enum.find(nodes, &(&1.id == start.id)).labels == ["Step", "Start"]

    assert Enum.find(nodes, &(&1.id == form.id)).properties == %{
             "label" => "Form",
             "fields" => 4,
             "graph_id" => graph.id
           }

    assert relationship.label == "TRANSITIONS_TO"
    assert relationship.properties == %{"if" => "always", "graph_id" => graph.id}
    assert {relationship.source_id, relationship.target_id} == {start.id, form.id}
  end

  test "graph_id is written to both the column and properties" do
    {:ok, graph} = Graphs.create()
    node = insert_node(graph)
    other = insert_node(graph)
    relationship = insert_relationship(graph, node, other)

    assert node.graph_id == graph.id
    assert node.properties["graph_id"] == graph.id

    assert relationship.graph_id == graph.id
    assert relationship.properties["graph_id"] == graph.id
  end

  test "a source and target can only be linked once per label" do
    {:ok, graph} = Graphs.create()
    start = insert_node(graph)
    form = insert_node(graph)

    insert_relationship(graph, start, form)

    assert {:error, changeset} =
             FormFlowRepo.insert(relationship_changeset(graph, start, form))

    assert %{source_id: ["has already been taken"]} = errors_on(changeset)

    # The same pair under a different label is fine
    assert {:ok, _} =
             FormFlowRepo.insert(
               relationship_changeset(graph, start, form, label: "FALLS_BACK_TO")
             )
  end

  test "relationships require nodes that exist" do
    {:ok, graph} = Graphs.create()
    start = insert_node(graph)

    changeset =
      Graph.Relationship.changeset(%Graph.Relationship{}, %{
        graph_id: graph.id,
        source_id: start.id,
        target_id: Ecto.UUID.generate(),
        label: "TRANSITIONS_TO"
      })

    # SQLite reports foreign key violations without naming the constraint, so
    # Ecto cannot route them to the changeset's foreign_key_constraint and
    # raises instead. On Postgres this same insert returns {:error, changeset}
    # with "does not exist" on :target_id.
    assert_raise Ecto.ConstraintError, ~r/foreign_key_constraint/, fn ->
      FormFlowRepo.insert(changeset)
    end
  end

  test "deleting a node detaches it: its relationships go too" do
    {:ok, graph} = Graphs.create()
    start = insert_node(graph)
    form = insert_node(graph)
    insert_relationship(graph, start, form)

    assert {:ok, _} = FormFlowRepo.delete(form)

    assert %Graph{relationships: []} = Graphs.get(graph.id)
  end

  test "deleting a graph cascades to every node and relationship in it" do
    {:ok, graph} = Graphs.create()
    start = insert_node(graph)
    form = insert_node(graph)
    insert_relationship(graph, start, form)

    assert {:ok, _} = Graphs.delete(Graphs.get(graph.id))

    assert {:ok, %{rows: [[0]]}} = Repo.query("SELECT count(*) FROM form_flow_graph_nodes")

    assert {:ok, %{rows: [[0]]}} =
             Repo.query("SELECT count(*) FROM form_flow_graph_relationships")
  end

  describe "declared flavor and save-time children" do
    test "create persists name and label; label is immutable" do
      {:ok, graph} = Graphs.create(%{name: "Enrollment", label: "subflows"})

      assert graph.name == "Enrollment"
      assert graph.label == "subflows"

      assert {:error, changeset} = Graphs.update(graph, %{label: "forms"})
      assert %{label: ["cannot be changed after creation"]} = errors_on(changeset)

      assert {:ok, renamed} = Graphs.update(graph, %{name: "Renamed"})
      assert renamed.name == "Renamed"
    end

    test "a forms flow rejects subflow steps" do
      {:ok, graph} = Graphs.create(%{label: "forms"})

      assert {:error, changeset} =
               Graphs.update(graph, %{
                 nodes: [%{properties: %{"type" => "subflow", "data" => %{}}}],
                 relationships: []
               })

      assert %{nodes: ["a forms flow cannot contain subflow steps"]} = errors_on(changeset)
    end

    test "a subflows flow rejects form steps but accepts Start and End" do
      {:ok, graph} = Graphs.create(%{label: "subflows"})

      assert {:error, changeset} =
               Graphs.update(graph, %{
                 nodes: [%{properties: %{"type" => "step", "data" => %{"kind" => "form"}}}],
                 relationships: []
               })

      assert %{nodes: ["a subflows flow cannot contain form steps"]} = errors_on(changeset)

      assert {:ok, _} =
               Graphs.update(Graphs.get(graph.id), %{
                 nodes: Graphs.starter_nodes(),
                 relationships: []
               })
    end

    test "saving creates children for subflow nodes, from their declared label" do
      {:ok, root} =
        Graphs.create(%{label: "subflows", nodes: Graphs.starter_nodes(), relationships: []})

      {:ok, _} =
        Graphs.update(Graphs.get(root.id), %{
          nodes: [
            %{
              properties: %{
                "type" => "subflow",
                "data" => %{"label" => "Collect address", "subflow_label" => "forms"}
              }
            },
            %{
              properties: %{
                "type" => "subflow",
                "data" => %{"label" => "Interview", "subflow_label" => "subflows"}
              }
            }
          ],
          relationships: []
        })

      root = Graphs.get(root.id)
      children = root.nodes |> Enum.map(& &1.subflow_id) |> Enum.map(&Graphs.get/1)

      address = Enum.find(children, &(&1.name == "Collect address"))
      interview = Enum.find(children, &(&1.name == "Interview"))

      assert address.label == "forms"
      assert interview.label == "subflows"

      # Owned by the root, seeded with the universal Start/End starter
      for child <- children do
        assert child.owner_graph_id == root.id

        assert child.nodes |> Enum.map(&get_in(&1.properties, ["data", "label"])) |> Enum.sort() ==
                 ["End", "Start"]

        assert child.relationships == []
      end

      # Saving again does not create duplicates: the references round-trip
      {:ok, _} =
        Graphs.update(root, %{
          nodes: Enum.map(root.nodes, &%{id: &1.id, properties: &1.properties}),
          relationships: []
        })

      assert Graphs.get(root.id).nodes
             |> Enum.map(& &1.subflow_id)
             |> Enum.sort() == Enum.sort([address.id, interview.id])
    end
  end

  describe "subflows and ownership" do
    test "an owned subflow: created, referenced, drilled into" do
      {:ok, root} = Graphs.create()
      {:ok, child} = Graphs.create(%{owner_graph_id: root.id})

      node = insert_subflow_node(root, child)

      assert Graphs.owned?(child)
      refute Graphs.owned?(root)

      # The reference dual-writes into properties, like graph_id
      assert node.subflow_id == child.id
      assert node.properties["subflow_id"] == child.id

      assert %Graph{id: id} = Graphs.get(node.subflow_id)
      assert id == child.id
    end

    test "a subflow reference survives the editor round-trip via properties" do
      {:ok, root} = Graphs.create(%{label: "subflows"})
      {:ok, child} = Graphs.create(%{owner_graph_id: root.id})

      # The editor sends properties untouched, no :subflow_id attribute
      {:ok, _} =
        Graphs.update(root, %{
          nodes: [%{id: Ecto.UUID.generate(), properties: %{"subflow_id" => child.id}}],
          relationships: []
        })

      assert [node] = Graphs.get(root.id).nodes
      assert node.subflow_id == child.id
      assert Graphs.get(child.id) != nil
    end

    test "make_reusable detaches, stamps, and re-homes descendants" do
      {:ok, root} = Graphs.create()
      {:ok, middle} = Graphs.create(%{owner_graph_id: root.id})
      {:ok, leaf} = Graphs.create(%{owner_graph_id: root.id})

      insert_subflow_node(root, middle)
      insert_subflow_node(middle, leaf)

      assert {:ok, middle} = Graphs.make_reusable(Graphs.get(middle.id))

      assert middle.owner_graph_id == nil
      assert %DateTime{} = middle.made_reusable_at

      # The leaf under it stays private, re-homed to the new ownership root
      assert Graphs.get(leaf.id).owner_graph_id == middle.id
    end

    test "list_reusable lists only graphs made reusable, newest first" do
      {:ok, _root} = Graphs.create()
      {:ok, first} = Graphs.create()
      {:ok, second} = Graphs.create()

      {:ok, _} = Graphs.make_reusable(first)
      {:ok, _} = Graphs.make_reusable(second)

      assert Enum.map(Graphs.list_reusable(), & &1.id) == [second.id, first.id]
    end

    test "duplicate deep-copies owned children and keeps reusable references" do
      {:ok, root} = Graphs.create()
      {:ok, owned} = Graphs.create(%{owner_graph_id: root.id})
      {:ok, shared} = Graphs.create()
      {:ok, shared} = Graphs.make_reusable(shared)

      form = insert_node(owned, ["Step"], %{"label" => "Inside"})
      insert_subflow_node(root, owned)
      insert_subflow_node(root, shared)

      assert {:ok, copy} = Graphs.duplicate(Graphs.get(root.id))

      assert copy.id != root.id
      assert copy.made_reusable_at == nil

      copied_refs = copy.nodes |> Enum.map(& &1.subflow_id) |> Enum.reject(&is_nil/1)

      # The reusable reference is shared; the owned one points at a fresh copy
      assert shared.id in copied_refs
      assert [owned_copy_id] = copied_refs -- [shared.id]
      assert owned_copy_id != owned.id

      owned_copy = Graphs.get(owned_copy_id)
      assert owned_copy.owner_graph_id == copy.id
      assert [inside] = owned_copy.nodes
      assert inside.id != form.id
      assert inside.properties["label"] == "Inside"
    end

    test "deleting a graph referenced by another flow is refused" do
      {:ok, root} = Graphs.create()
      {:ok, shared} = Graphs.create()
      {:ok, shared} = Graphs.make_reusable(shared)

      insert_subflow_node(root, shared)

      assert {:error, changeset} = Graphs.delete(shared)
      assert %{id: ["is still used as a subflow by another flow"]} = errors_on(changeset)

      # Remove the reference and deletion goes through
      {:ok, _} = Graphs.update(Graphs.get(root.id), %{nodes: [], relationships: []})
      assert {:ok, _} = Graphs.delete(shared)
    end

    test "deleting a root deletes its owned tree, sparing reusable graphs" do
      {:ok, root} = Graphs.create()
      {:ok, owned} = Graphs.create(%{owner_graph_id: root.id})
      {:ok, shared} = Graphs.create()
      {:ok, shared} = Graphs.make_reusable(shared)

      insert_subflow_node(root, owned)
      insert_subflow_node(root, shared)

      assert {:ok, _} = Graphs.delete(Graphs.get(root.id))

      assert Graphs.get(root.id) == nil
      assert Graphs.get(owned.id) == nil
      assert Graphs.get(shared.id) != nil
    end

    test "delete_node removes the step and collects owned children, sparing reusable" do
      {:ok, root} = Graphs.create(%{label: "subflows"})
      {:ok, owned} = Graphs.create(%{owner_graph_id: root.id})
      {:ok, grandchild} = Graphs.create(%{owner_graph_id: root.id})
      {:ok, shared} = Graphs.create()
      {:ok, shared} = Graphs.make_reusable(shared)

      owned_node = insert_subflow_node(root, owned)
      shared_node = insert_subflow_node(root, shared)
      insert_subflow_node(owned, grandchild)

      {:ok, _} = Graphs.delete_node(owned_node)

      # The step is gone, and the owned subtree went with it
      assert Graphs.get_node(owned_node.id) == nil
      assert Graphs.get(owned.id) == nil
      assert Graphs.get(grandchild.id) == nil

      # Removing a reusable usage keeps the reusable graph
      {:ok, _} = Graphs.delete_node(shared_node)
      assert Graphs.get(shared.id) != nil
    end

    test "saving contents garbage-collects unreachable owned subflows" do
      {:ok, root} = Graphs.create(%{label: "subflows"})
      {:ok, kept} = Graphs.create(%{owner_graph_id: root.id})
      {:ok, dropped} = Graphs.create(%{owner_graph_id: root.id})
      {:ok, grandchild} = Graphs.create(%{owner_graph_id: root.id})

      keeper = insert_subflow_node(root, kept)
      insert_subflow_node(root, dropped)
      insert_subflow_node(dropped, grandchild)

      # Save the root keeping only the node that references `kept`
      {:ok, _} =
        Graphs.update(Graphs.get(root.id), %{
          nodes: [%{id: keeper.id, subflow_id: kept.id, properties: keeper.properties}],
          relationships: []
        })

      assert Graphs.get(kept.id) != nil
      assert Graphs.get(dropped.id) == nil
      assert Graphs.get(grandchild.id) == nil
    end
  end

  defp insert_node(graph, labels \\ ["Step"], properties \\ %{}) do
    {:ok, node} =
      %Graph.Node{}
      |> Graph.Node.changeset(%{graph_id: graph.id, labels: labels, properties: properties})
      |> FormFlowRepo.insert()

    node
  end

  defp insert_relationship(graph, source, target, properties \\ %{}) do
    {:ok, relationship} =
      FormFlowRepo.insert(relationship_changeset(graph, source, target, properties: properties))

    relationship
  end

  defp insert_subflow_node(graph, subflow) do
    {:ok, node} =
      %Graph.Node{}
      |> Graph.Node.changeset(%{
        graph_id: graph.id,
        subflow_id: subflow.id,
        properties: %{"type" => "subflow"}
      })
      |> FormFlowRepo.insert()

    node
  end

  defp relationship_changeset(graph, source, target, opts \\ []) do
    Graph.Relationship.changeset(%Graph.Relationship{}, %{
      graph_id: graph.id,
      source_id: source.id,
      target_id: target.id,
      label: Keyword.get(opts, :label, "TRANSITIONS_TO"),
      properties: Keyword.get(opts, :properties, %{})
    })
  end
end
