defmodule FormFlow.Data.Templates.Flow.RelationshipTest do
  use ExUnit.Case, async: true

  alias FormFlow.Data.Templates.Flow.Relationship

  @attrs %{
    flow_id: Ecto.UUID.generate(),
    source_id: Ecto.UUID.generate(),
    target_id: Ecto.UUID.generate(),
    label: "TRANSITIONS_TO"
  }

  test "casts endpoints, label, and properties" do
    changeset =
      Relationship.changeset(%Relationship{}, Map.put(@attrs, :properties, %{"if" => "approved"}))

    assert changeset.valid?
    assert changeset.changes.label == "TRANSITIONS_TO"

    assert properties(changeset) == %{
             "if" => "approved",
             "flow_id" => @attrs.flow_id
           }
  end

  test "requires flow_id, source_id, target_id, and label" do
    changeset = Relationship.changeset(%Relationship{}, %{})

    refute changeset.valid?

    assert %{
             flow_id: ["can't be blank"],
             source_id: ["can't be blank"],
             target_id: ["can't be blank"],
             label: ["can't be blank"]
           } = errors_on(changeset)
  end

  test "properties default rather than being required" do
    changeset = Relationship.changeset(%Relationship{}, @attrs)

    assert changeset.valid?

    assert Map.delete(Ecto.Changeset.apply_changes(changeset).properties, "id") == %{
             "flow_id" => @attrs.flow_id
           }
  end

  test "casts tenant_id and copies it into properties" do
    changeset = Relationship.changeset(%Relationship{}, Map.put(@attrs, :tenant_id, "acme"))

    assert changeset.valid?
    assert changeset.changes.tenant_id == "acme"

    assert properties(changeset) == %{
             "flow_id" => @attrs.flow_id,
             "tenant_id" => "acme"
           }
  end

  test "IN, EMBEDS, and OWNED_BY are reserved for the Neo4j structural vocabulary" do
    for label <- ~w(IN EMBEDS OWNED_BY) do
      changeset = Relationship.changeset(%Relationship{}, %{@attrs | label: label})

      refute changeset.valid?
      assert %{label: ["is reserved by FormFlow"]} = errors_on(changeset)
    end

    assert Relationship.changeset(%Relationship{}, @attrs).valid?
  end

  test "carries the unique constraint on source, target, and label" do
    changeset = Relationship.changeset(%Relationship{}, @attrs)

    unique =
      for constraint <- changeset.constraints,
          constraint.type == :unique,
          do: constraint.constraint

    # Postgres's name for the index, and the one SQLite's adapter rebuilds
    # from the columns because SQLite cannot report the index itself
    assert "form_flow_template_flow_relationships_source_target_label_index" in unique

    assert "form_flow_template_flow_relationships_source_id_target_id_label_index" in unique
  end

  test "the relationship's own id is copied into properties, generated if absent" do
    id = Ecto.UUID.generate()

    changeset =
      Relationship.changeset(
        %Relationship{},
        Map.merge(@attrs, %{id: id, properties: %{"id" => "stale"}})
      )

    assert changeset.changes.properties["id"] == id

    generated = Relationship.changeset(%Relationship{}, @attrs)

    assert {:ok, _} = Ecto.UUID.cast(generated.changes.id)
    assert generated.changes.properties["id"] == generated.changes.id
  end

  # The generated id is unpredictable, so exact-map assertions compare what is
  # left once its properties copy is set aside
  defp properties(changeset), do: Map.delete(changeset.changes.properties, "id")

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
