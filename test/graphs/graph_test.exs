defmodule FormFlow.GraphTest do
  use ExUnit.Case, async: true

  alias FormFlow.Graph

  test "the changeset is valid with no attributes — a graph row is an identity" do
    changeset = Graph.changeset(%Graph{})

    assert changeset.valid?
    assert changeset.changes == %{}
  end

  test "ignores unknown attributes rather than casting them" do
    changeset = Graph.changeset(%Graph{}, %{name: "Enrollment", nodes: [%{}]})

    assert changeset.valid?
    assert changeset.changes == %{}
  end

  test "associations point at the graph_id foreign key" do
    assert %{related: FormFlow.Graph.Node, related_key: :graph_id} =
             Graph.__schema__(:association, :nodes)

    assert %{related: FormFlow.Graph.Relationship, related_key: :graph_id} =
             Graph.__schema__(:association, :relationships)
  end
end
