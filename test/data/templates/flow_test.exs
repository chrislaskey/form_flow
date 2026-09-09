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

  test "tenant_id is written to the column and copied into properties" do
    changeset =
      Flow.changeset(%Flow{}, %{
        tenant_id: "acme",
        properties: %{"form_flow_type" => "wizard_any_order"}
      })

    assert changeset.valid?
    assert changeset.changes.tenant_id == "acme"

    assert changeset.changes.properties == %{
             "form_flow_type" => "wizard_any_order",
             "tenant_id" => "acme"
           }

    # A host with no tenants: nil column, no key
    assert Flow.changeset(%Flow{}, %{name: "Solo"}).changes == %{name: "Solo"}
  end

  test "tenant_id is immutable, and the column overwrites a stale properties copy" do
    persisted =
      %Flow{tenant_id: "acme", properties: %{"tenant_id" => "acme"}}
      |> Ecto.put_meta(state: :loaded)

    changeset = Flow.changeset(persisted, %{tenant_id: "other"})
    refute changeset.valid?
    assert {"cannot be changed after creation", _opts} = changeset.errors[:tenant_id]

    # The editor round-trips properties; a copy it drops or corrupts is restored
    changeset =
      Flow.changeset(persisted, %{
        properties: %{"form_flow_type" => "wizard_in_order", "tenant_id" => "impostor"}
      })

    assert changeset.valid?

    assert changeset.changes.properties == %{
             "form_flow_type" => "wizard_in_order",
             "tenant_id" => "acme"
           }
  end

  test "slug is written to the column and copied into properties; clearing it removes the copy" do
    changeset = Flow.changeset(%Flow{}, %{slug: "dla2026", properties: %{"k" => "v"}})

    assert changeset.valid?
    assert changeset.changes.slug == "dla2026"
    assert changeset.changes.properties == %{"k" => "v", "slug" => "dla2026"}

    persisted =
      %Flow{slug: "dla2026", properties: %{"slug" => "dla2026", "k" => "v"}}
      |> Ecto.put_meta(state: :loaded)

    changeset = Flow.changeset(persisted, %{slug: ""})
    assert changeset.valid?
    assert changeset.changes.slug == nil
    assert changeset.changes.properties == %{"k" => "v"}
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

  describe "status" do
    test "a flow is born a draft, and a status can be given at creation for seeds and tests" do
      assert %Flow{}.status == "draft"

      changeset = Flow.changeset(%Flow{}, %{status: "open"})
      assert changeset.valid?
      assert changeset.changes.status == "open"
    end

    test "only the statuses the table names are accepted" do
      changeset = Flow.changeset(%Flow{}, %{status: "closed"})

      refute changeset.valid?
      assert {"is invalid", _opts} = changeset.errors[:status]

      assert Flow.statuses() == ~w(draft open winding_down)
    end

    test "status is immutable through the plain changeset — update_status/3 moves it" do
      persisted = %Flow{status: "draft"} |> Ecto.put_meta(state: :loaded)

      refute Flow.changeset(persisted, %{status: "open"}).valid?
      assert Flow.status_changeset(persisted, "open").valid?
      refute Flow.status_changeset(persisted, "closed").valid?
    end

    test "what each status lets a user do: start, continue, see" do
      assert Flow.allows?("open", :start)
      assert Flow.allows?("open", :continue)
      assert Flow.allows?("open", :see)

      refute Flow.allows?("winding_down", :start)
      assert Flow.allows?("winding_down", :continue)
      assert Flow.allows?("winding_down", :see)

      refute Flow.allows?("draft", :start)
      refute Flow.allows?("draft", :continue)
      refute Flow.allows?("draft", :see)

      # The struct works too, and an unknown status allows nothing
      assert Flow.allows?(%Flow{status: "open"}, :start)
      refute Flow.allows?("closed", :see)

      assert Flow.statuses_allowing(:start) == ["open"]
      assert Flow.statuses_allowing(:see) == ["open", "winding_down"]
    end
  end
end
