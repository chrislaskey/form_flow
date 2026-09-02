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

  test "copied_from_form_id is not castable — only copy/2 stamps provenance" do
    changeset =
      Form.changeset(%Form{}, %{name: "W-2 Details", copied_from_form_id: Ecto.UUID.generate()})

    assert changeset.valid?
    refute Map.has_key?(changeset.changes, :copied_from_form_id)
  end
end
