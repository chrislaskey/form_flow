defmodule Demo.FormFlowGraphsTest do
  @moduledoc """
  Exercises `FormFlow.Graphs` and the graph schemas against a real database —
  the library's own tests stop at changesets, so this is where the V02 DDL
  (foreign keys, cascades, the unique relationship index) is proven to hold.
  """

  use Demo.DataCase, async: false

  alias FormFlow.Data.Repo, as: FormFlowRepo
  alias FormFlow.Graph
  alias FormFlow.Graphs

  test "create, get, update, and delete a graph" do
    assert {:ok, %Graph{id: id}} = Graphs.create()

    assert %Graph{id: ^id, nodes: [], relationships: []} = Graphs.get(id)

    assert {:ok, %Graph{id: ^id}} = Graphs.update(Graphs.get(id), %{})

    assert {:ok, _} = Graphs.delete(Graphs.get(id))
    assert Graphs.get(id) == nil
  end

  test "list returns graphs without loading their contents" do
    {:ok, first} = Graphs.create()
    {:ok, second} = Graphs.create()

    assert [%Graph{id: a}, %Graph{id: b}] = Graphs.list()
    assert {a, b} == {first.id, second.id}

    assert [%Graph{nodes: %Ecto.Association.NotLoaded{}} | _] = Graphs.list()
  end

  test "get loads nodes and relationships, round-tripping labels and properties" do
    {:ok, graph} = Graphs.create()

    start = insert_node(graph, ["Step", "Start"], %{"label" => "Start"})
    form = insert_node(graph, ["Step"], %{"label" => "Form", "fields" => 4})
    insert_relationship(graph, start, form, %{"if" => "always"})

    assert %Graph{nodes: nodes, relationships: [relationship]} = Graphs.get(graph.id)

    assert length(nodes) == 2
    assert Enum.find(nodes, &(&1.id == start.id)).labels == ["Step", "Start"]
    assert Enum.find(nodes, &(&1.id == form.id)).properties == %{"label" => "Form", "fields" => 4}

    assert relationship.label == "TRANSITIONS_TO"
    assert relationship.properties == %{"if" => "always"}
    assert {relationship.source_id, relationship.target_id} == {start.id, form.id}
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
