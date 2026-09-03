defmodule FormFlow.Data.Instances.Form do
  @moduledoc """
  `FormFlow.Data.Instances.Form` Ecto Schema for one form instance — one user's completion of a form.

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
  rule 5). What each question's label *said* at completion time is always
  recoverable through the pin — the pinned definition is immutable.
  (Denormalizing labels onto the instance at completion — a labels
  snapshot — is a deliberately deferred optimization; see
  `archive/plans/instances-next.md`.)

  An instance carries two opaque host identities, the same pair as
  `FormFlow.Data.Instances.Flow`: `user_id`, the user who started it, and
  `tenant_id`, the host tenant it belongs to, `nil` for a host with no
  tenants. Both are stamped at creation and immutable afterwards.

  `metadata` is an opaque host-app map: whatever the host wants to attach —
  including who a form instance concerns, until about-ness earns a named column.
  FormFlow never interprets it.

  A form instance filled inside a whole root flow instance — a journey —
  rather than on its own carries its visit identity: `instance_flow_id` and
  `path`, the chain of node ids from the root flow
  through each embedding subflow node down to the form node itself. Both are
  present or both absent (a standalone fill), and `path` is a snapshot
  stamped at creation through `visit_changeset/4`, never castable, never
  updated; there is deliberately no node FK beside it (a derivable copy of
  `last(path)` that no FK action would survive — editor saves replace all
  nodes). Stranded is not a column state: `FormFlow.Data.Instances.FlowProgress` derives it when a
  path matches no position in the current tree. `superseded_at` is stamped
  by strand reconciliation on a replaced instance; derivation skips
  superseded rows, and the partial unique index enforces one *active*
  instance per visit.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias FormFlow.Data.Instances
  alias FormFlow.Data.Templates.Form.Version

  @statuses ~w(in_progress completed)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "form_flow_instance_forms" do
    belongs_to(:template_form_version, Version, foreign_key: :template_form_version_id)

    field(:status, :string, default: "in_progress")
    field(:lock_version, :integer, default: 1)
    field(:user_id, :string)
    field(:tenant_id, :string)
    field(:data, :map, default: %{})
    field(:metadata, :map, default: %{})
    field(:completed_at, :utc_datetime_usec)

    belongs_to(:instance_flow, Instances.Flow, foreign_key: :instance_flow_id)
    field(:path, {:array, :string}, default: [])
    field(:superseded_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec)
  end

  def statuses, do: @statuses

  @doc """
  Builds a changeset for an instance form.

  `status` and `completed_at` are not castable — they are stamped by
  completion machinery, never supplied by callers (the same discipline as
  `FormFlow.Data.Instances.Flow`). `user_id` and `tenant_id` are castable
  at creation and immutable afterwards. Updates go through the optimistic
  lock: two editors of one instance's `data` surface `Ecto.StaleEntryError`
  instead of a silent last-write-wins.
  """
  def changeset(instance, attrs \\ %{}) do
    instance
    |> cast(attrs, [
      :template_form_version_id,
      :instance_flow_id,
      :user_id,
      :tenant_id,
      :data,
      :metadata
    ])
    |> finalize()
  end

  @doc """
  Builds a changeset for an in-journey form instance: `changeset/2` plus
  the stamped visit identity. `path` is never castable from external
  input — the runner supplies it here, at creation, and it is immutable
  afterwards.
  """
  def visit_changeset(instance, attrs, instance_flow_id, path) when is_list(path) do
    instance
    |> cast(attrs, [
      :template_form_version_id,
      :user_id,
      :tenant_id,
      :data,
      :metadata
    ])
    |> put_change(:instance_flow_id, instance_flow_id)
    |> put_change(:path, path)
    |> finalize()
  end

  defp finalize(changeset) do
    changeset
    |> validate_required([:template_form_version_id])
    |> validate_immutable(:user_id)
    |> validate_immutable(:tenant_id)
    |> validate_visit_identity()
    |> optimistic_lock(:lock_version)
    |> foreign_key_constraint(:template_form_version_id)
    |> foreign_key_constraint(:instance_flow_id)
    |> unique_constraint([:instance_flow_id, :path])
  end

  # The visit identity is both-or-neither: standalone instances carry no
  # journey and no path, in-journey instances carry both. The partial
  # unique index (scoped to active in-journey rows) cannot catch the
  # orphaned-path half by itself.
  defp validate_visit_identity(changeset) do
    instance_flow_id = get_field(changeset, :instance_flow_id)
    path = get_field(changeset, :path) || []

    cond do
      is_nil(instance_flow_id) and path == [] ->
        changeset

      not is_nil(instance_flow_id) and path != [] ->
        changeset

      is_nil(instance_flow_id) ->
        add_error(changeset, :instance_flow_id, "is required when a visit path is set")

      true ->
        add_error(changeset, :path, "is required for an in-journey form instance")
    end
  end

  # The same rule Instances.Flow applies to its identities: castable at
  # creation, a commitment afterwards.
  defp validate_immutable(changeset, field) do
    if changeset.data.__meta__.state == :loaded and get_change(changeset, field) do
      add_error(changeset, field, "cannot be changed after creation")
    else
      changeset
    end
  end
end
