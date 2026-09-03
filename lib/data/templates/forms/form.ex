defmodule FormFlow.Data.Templates.Form do
  @moduledoc """
  `FormFlow.Data.Templates.Form` Ecto Schema for a form template's identity —
  the lineage.

  A form's stable identity (name, description, ownership) lives here;
  every definition — draft or published — is a
  `FormFlow.Data.Templates.Form.Version` row. The split is what makes
  versioning work: nodes and URLs point at the lineage, instances pin a
  version, and "which version to show" is a read-time question (see
  `FormFlow.Data.Templates.Forms`).

  ## Ownership

  `owner_flow_id` mirrors `FormFlow.Data.Templates.Flow`'s ownership: an owned
  form is a flow tree's private property (the ownership root, flat), created
  by the editor and cleaned up with its flow. `nil` means a reusable catalog form,
  listed in `/forms` and shared by reference. Catalog names are unique — the
  catalog is one namespace; owned forms may repeat names freely (yearly
  copies of "W-2 Details").

  `copied_from_form_id` records provenance across copies — which lineage this
  one was rolled over from — for cross-cycle identity and future prefill.
  It is not castable: only `FormFlow.Data.Templates.Forms.copy/2` sets it.

  ## Tenancy

  `tenant_id` is the host tenant the lineage belongs to — an opaque host
  identity, `nil` for a host with no tenants — stamped at creation and
  immutable afterwards; owned forms and copies take their flow tree's. Like a
  node's `flow_id` it is written to both locations: the dedicated column,
  so the database can index and narrow by it, and a `"tenant_id"` key inside
  `properties`, the copy that carries over to Neo4j. The changeset keeps
  the copy in sync — the column is authoritative, and a stale `"tenant_id"`
  arriving in `properties` is overwritten.

  ## Slug

  `slug` is the lineage's secondary identifier — see
  `FormFlow.Data.Templates.Slug`: optional, unique per tenant, editable,
  never following a rename, and dual-written into `properties["slug"]` the
  same way. `FormFlow.Data.Templates.Forms.create/1` fills one in from the
  name when none is given; owned forms take their flow's slug as a prefix.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias FormFlow.Data.Templates.Flow
  alias FormFlow.Data.Templates.Form.Version
  alias FormFlow.Data.Templates.Slug

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "form_flow_template_forms" do
    field(:name, :string)
    field(:description, :string)
    field(:tenant_id, :string)
    field(:slug, :string)

    # Open domain data in the Neo4j property-graph style, like a flow's.
    # Carries "form_type" — the id of the `FormFlow.Config.Forms.Type`
    # deciding how the form behaves for a user; absent means the default
    # applies.
    field(:properties, :map, default: %{})

    belongs_to(:owner_flow, Flow, foreign_key: :owner_flow_id)
    belongs_to(:copied_from, __MODULE__, foreign_key: :copied_from_form_id)

    has_many(:versions, Version, foreign_key: :template_form_id)

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Builds a changeset for a form lineage — identity fields and properties only.

  The definition lives on versions, never here. `copied_from_form_id` is not
  castable; provenance is stamped only by the copy operation. `tenant_id`
  is castable at creation and immutable afterwards.
  """
  def changeset(form, attrs \\ %{}) do
    form
    |> cast(attrs, [:name, :description, :tenant_id, :slug, :properties, :owner_flow_id])
    |> validate_required([:name])
    |> validate_immutable(:tenant_id)
    |> Slug.validate_slug(:form_flow_template_forms_slug_tenant_index)
    |> copy_into_properties(:tenant_id, "tenant_id")
    |> copy_into_properties(:slug, "slug")
    |> foreign_key_constraint(:owner_flow_id)
    |> unique_constraint(:name, name: :form_flow_template_forms_name_index)
  end

  defp validate_immutable(changeset, field) do
    if changeset.data.__meta__.state == :loaded and get_change(changeset, field) do
      add_error(changeset, field, "cannot be changed after creation")
    else
      changeset
    end
  end

  # The dual-write: properties carry a copy of the column, for Neo4j — and
  # none when the column is empty
  defp copy_into_properties(changeset, field, key) do
    properties = get_field(changeset, :properties) || %{}

    properties =
      case get_field(changeset, field) do
        nil -> Map.delete(properties, key)
        value -> Map.put(properties, key, value)
      end

    put_change(changeset, :properties, properties)
  end
end
