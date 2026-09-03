defmodule FormFlow.Data.Templates.FormTest do
  use ExUnit.Case, async: true

  alias FormFlow.Data.Templates.Form

  test "requires a name — a lineage is an identity, and the name is it" do
    refute Form.changeset(%Form{}).valid?

    changeset = Form.changeset(%Form{}, %{name: "W-2 Details"})

    assert changeset.valid?
    assert changeset.changes.name == "W-2 Details"
  end

  test "casts identity fields and ownership" do
    owner_id = Ecto.UUID.generate()

    changeset =
      Form.changeset(%Form{}, %{
        name: "W-2 Details",
        description: "Wages and withholding",
        owner_flow_id: owner_id
      })

    assert changeset.valid?
    assert changeset.changes.description == "Wages and withholding"
    assert changeset.changes.owner_flow_id == owner_id
  end

  test "casts properties — the form-level domain data, like form_type" do
    changeset =
      Form.changeset(%Form{}, %{name: "W-2 Details", properties: %{"form_type" => "prefill"}})

    assert changeset.valid?
    assert changeset.changes.properties == %{"form_type" => "prefill"}
  end

  test "tenant_id is written to the column and copied into properties" do
    changeset =
      Form.changeset(%Form{}, %{
        name: "W-2 Details",
        tenant_id: "acme",
        properties: %{"form_type" => "prefill"}
      })

    assert changeset.valid?
    assert changeset.changes.tenant_id == "acme"
    assert changeset.changes.properties == %{"form_type" => "prefill", "tenant_id" => "acme"}

    # A host with no tenants: nil column, no key
    refute Map.has_key?(Form.changeset(%Form{}, %{name: "Solo"}).changes, :properties)
  end

  test "tenant_id is immutable, and the column overwrites a stale properties copy" do
    persisted =
      %Form{name: "W-2 Details", tenant_id: "acme", properties: %{"tenant_id" => "acme"}}
      |> Ecto.put_meta(state: :loaded)

    changeset = Form.changeset(persisted, %{tenant_id: "other"})
    refute changeset.valid?
    assert {"cannot be changed after creation", _opts} = changeset.errors[:tenant_id]

    changeset =
      Form.changeset(persisted, %{
        properties: %{"form_type" => "review", "tenant_id" => "impostor"}
      })

    assert changeset.valid?
    assert changeset.changes.properties == %{"form_type" => "review", "tenant_id" => "acme"}
  end

  test "slug is written to the column and copied into properties; clearing it removes the copy" do
    changeset = Form.changeset(%Form{}, %{name: "W-2 Details", slug: "w2details"})

    assert changeset.valid?
    assert changeset.changes.slug == "w2details"
    assert changeset.changes.properties == %{"slug" => "w2details"}

    persisted =
      %Form{name: "W-2 Details", slug: "w2details", properties: %{"slug" => "w2details"}}
      |> Ecto.put_meta(state: :loaded)

    changeset = Form.changeset(persisted, %{slug: nil})
    assert changeset.valid?
    assert changeset.changes.properties == %{}
  end

  test "copied_from_form_id is not castable — only copy/2 stamps provenance" do
    changeset =
      Form.changeset(%Form{}, %{name: "W-2 Details", copied_from_form_id: Ecto.UUID.generate()})

    assert changeset.valid?
    refute Map.has_key?(changeset.changes, :copied_from_form_id)
  end
end
