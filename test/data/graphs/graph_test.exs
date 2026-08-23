defmodule FormFlow.Data.GraphTest do
  use ExUnit.Case, async: true

  alias FormFlow.Data.Graph

  test "the changeset is valid with no attributes — a graph row is an identity" do
    changeset = Graph.changeset(%Graph{})

    assert changeset.valid?
    assert changeset.changes == %{}
  end

  test "casts owner_graph_id, so owned subflows can be created" do
    owner_id = Ecto.UUID.generate()
    changeset = Graph.changeset(%Graph{}, %{owner_graph_id: owner_id})

    assert changeset.valid?
    assert changeset.changes.owner_graph_id == owner_id
  end

  test "made_reusable_at is not castable — only make_reusable/1 stamps it" do
    changeset = Graph.changeset(%Graph{}, %{made_reusable_at: DateTime.utc_now()})

    assert changeset.valid?
    assert changeset.changes == %{}
  end

  test "an owned graph cannot be reusable" do
    reusable = %Graph{made_reusable_at: DateTime.utc_now()}
    changeset = Graph.changeset(reusable, %{owner_graph_id: Ecto.UUID.generate()})

    refute changeset.valid?
    assert {"an owned graph cannot be reusable", _opts} = changeset.errors[:owner_graph_id]
  end

  test "ignores unknown attributes rather than casting them" do
    changeset = Graph.changeset(%Graph{}, %{name: "Enrollment"})

    assert changeset.valid?
    assert changeset.changes == %{}
  end

  test "associations point at the graph_id foreign key" do
    assert %{related: FormFlow.Data.Graph.Node, related_key: :graph_id} =
             Graph.__schema__(:association, :nodes)

    assert %{related: FormFlow.Data.Graph.Relationship, related_key: :graph_id} =
             Graph.__schema__(:association, :relationships)
  end
end
