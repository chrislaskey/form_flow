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

    assert changeset.changes.properties == %{
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

    assert Ecto.Changeset.apply_changes(changeset).properties == %{
             "flow_id" => @attrs.flow_id
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

    assert Enum.any?(changeset.constraints, fn constraint ->
             constraint.type == :unique and
               constraint.constraint ==
                 "form_flow_relationships_source_id_target_id_label_index"
           end)
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
