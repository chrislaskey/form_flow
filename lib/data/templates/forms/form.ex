defmodule FormFlow.Data.Templates.Form do
  @moduledoc """
  `FormFlow.Data.Templates.Form` Ecto Schema for a form template's identity —
  the lineage.

  A form's stable identity (name, description, app, ownership) lives here;
  every definition — draft or published — is a
  `FormFlow.Data.Templates.Form.Version` row. The split is what makes
  versioning work: nodes and URLs point at the lineage, instances pin a
  version, and "which version to show" is a read-time question (see
  `FormFlow.Data.Templates.Forms`).

  ## Ownership

  `owner_flow_id` mirrors `FormFlow.Data.Templates.Flow`'s ownership: an owned
  form is a flow tree's private property (the ownership root, flat), created
  by the editor and cleaned up with its flow. `nil` means a reusable catalog form,
  listed in `/forms` and shared by reference. Catalog names are unique per
  app; owned forms may repeat names freely (yearly copies of "W-2 Details").

  `copied_from_form_id` records provenance across copies — which lineage this
  one was rolled over from — for cross-cycle identity and future prefill.
  It is not castable: only `FormFlow.Data.Templates.Forms.copy/2` sets it.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias FormFlow.Data.Templates.Flow
  alias FormFlow.Data.Templates.Form.Version

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "form_flow_template_forms" do
    field(:app, :string, default: "default")
    field(:name, :string)
    field(:description, :string)

    belongs_to(:owner_flow, Flow, foreign_key: :owner_flow_id)
    belongs_to(:copied_from, __MODULE__, foreign_key: :copied_from_form_id)

    has_many(:versions, Version, foreign_key: :template_form_id)

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Builds a changeset for a form lineage — identity fields only.

  The definition lives on versions, never here. `copied_from_form_id` is not
  castable; provenance is stamped only by the copy operation.
  """
  def changeset(form, attrs \\ %{}) do
    form
    |> cast(attrs, [:app, :name, :description, :owner_flow_id])
    |> validate_required([:name])
    |> foreign_key_constraint(:owner_flow_id)
    |> unique_constraint([:app, :name], name: :form_flow_template_forms_app_name_index)
  end
end
