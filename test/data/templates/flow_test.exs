defmodule FormFlow.Data.Templates.FlowTest do
  use ExUnit.Case, async: true

  alias FormFlow.Data.Templates.Flow

  test "the changeset is valid with no attributes — a flow row is an identity" do
    changeset = Flow.changeset(%Flow{})

    assert changeset.valid?
    assert changeset.changes == %{}
  end

  test "casts name and label at creation" do
    changeset = Flow.changeset(%Flow{}, %{name: "Enrollment", label: "subflows"})

    assert changeset.valid?
    assert changeset.changes.name == "Enrollment"
    assert changeset.changes.label == "subflows"
  end

  test "label must be forms or subflows" do
    changeset = Flow.changeset(%Flow{}, %{label: "mixed"})

    refute changeset.valid?
    assert {"is invalid", _opts} = changeset.errors[:label]
  end

  test "label is immutable once the flow is persisted" do
    persisted = %Flow{label: "forms"} |> Ecto.put_meta(state: :loaded)
    changeset = Flow.changeset(persisted, %{label: "subflows"})

    refute changeset.valid?
    assert {"cannot be changed after creation", _opts} = changeset.errors[:label]

    # Renaming a persisted flow stays fine
    assert Flow.changeset(persisted, %{name: "Renamed"}).valid?
  end

  test "casts properties — the flow-level domain data, like form_flow_type" do
    changeset =
      Flow.changeset(%Flow{}, %{properties: %{"form_flow_type" => "wizard_any_order"}})

    assert changeset.valid?
    assert changeset.changes.properties == %{"form_flow_type" => "wizard_any_order"}
  end

  test "casts owner_flow_id, so owned subflows can be created" do
    owner_id = Ecto.UUID.generate()
    changeset = Flow.changeset(%Flow{}, %{owner_flow_id: owner_id})

    assert changeset.valid?
    assert changeset.changes.owner_flow_id == owner_id
  end

  test "made_reusable_at is not castable — only make_reusable/1 stamps it" do
    changeset = Flow.changeset(%Flow{}, %{made_reusable_at: DateTime.utc_now()})

    assert changeset.valid?
    assert changeset.changes == %{}
  end

  test "an owned flow cannot be reusable" do
    reusable = %Flow{made_reusable_at: DateTime.utc_now()}
    changeset = Flow.changeset(reusable, %{owner_flow_id: Ecto.UUID.generate()})

    refute changeset.valid?
    assert {"an owned flow cannot be reusable", _opts} = changeset.errors[:owner_flow_id]
  end

  test "ignores unknown attributes rather than casting them" do
    changeset = Flow.changeset(%Flow{}, %{color: "teal"})

    assert changeset.valid?
    assert changeset.changes == %{}
  end

  test "associations point at the flow_id foreign key" do
    assert %{related: FormFlow.Data.Templates.Flow.Node, related_key: :flow_id} =
             Flow.__schema__(:association, :nodes)

    assert %{related: FormFlow.Data.Templates.Flow.Relationship, related_key: :flow_id} =
             Flow.__schema__(:association, :relationships)
  end
end
