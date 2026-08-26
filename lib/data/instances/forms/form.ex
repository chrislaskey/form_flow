defmodule FormFlow.Data.Instances.Form do
  @moduledoc """
  `FormFlow.Data.Instances.Form` Ecto Schema for one user's fill of a form.

  The load-bearing column is the pin: `template_form_version_id` names the
  exact definition this instance renders against — never "latest", never the
  live template (hard rule 1 in `archive/form-versioning.md`). Publishing a
  new version moves pins only through explicit publish-time policies
  (`FormFlow.Data.Templates.Forms.update_status/3`), each move recorded as an
  append-only `FormFlow.Data.Instances.Form.Event`.

  There is deliberately no lineage (`template_form_id`) column beside the
  pin: the lineage is derived through the pinned version, so it can never
  desync, and the rare admin queries that want it join for free.

  `data` holds the answers, keyed by field name, and holds *only* answers —
  progress, section state, and system markers never live inside it (hard
  rule 5). `labels_snapshot` caches `%{field_name => label}` from the pinned
  definition at completion, so a rename can't rewrite what an attestation
  meant; it is not castable — completion machinery stamps it.

  `metadata` is an opaque host-app map: whatever the host wants to attach —
  including who a fill concerns, until about-ness earns a named column.
  FormFlow never interprets it.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias FormFlow.Data.Templates.Form.Version

  @statuses ~w(in_progress completed)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "form_flow_instance_forms" do
    field(:app, :string, default: "default")

    belongs_to(:template_form_version, Version, foreign_key: :template_form_version_id)

    field(:status, :string, default: "in_progress")
    field(:data, :map, default: %{})
    field(:labels_snapshot, :map, default: %{})
    field(:metadata, :map, default: %{})
    field(:completed_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec)
  end

  def statuses, do: @statuses

  @doc """
  Builds a changeset for an instance form.

  `labels_snapshot` is not castable — it is stamped by completion machinery
  from the pinned definition, never supplied by callers.
  """
  def changeset(instance, attrs \\ %{}) do
    instance
    |> cast(attrs, [
      :app,
      :template_form_version_id,
      :status,
      :data,
      :metadata,
      :completed_at
    ])
    |> validate_required([:template_form_version_id])
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:template_form_version_id)
  end
end
