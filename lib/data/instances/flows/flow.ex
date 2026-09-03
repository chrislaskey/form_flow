defmodule FormFlow.Data.Instances.Flow do
  @moduledoc """
  `FormFlow.Data.Instances.Flow` Ecto Schema for one traversal of a root
  flow — a journey — the instance-side counterpart of
  `FormFlow.Data.Templates.Flow`, exactly as `FormFlow.Data.Instances.Form`
  is the counterpart of `FormFlow.Data.Templates.Form`.

  `flow_id` names the root; the traversal covers the whole tree reachable
  through subflow references, with interior positions addressed by `path`
  on the attached form instances. The flow is referenced *live* — never
  versioned, never snapshotted: structure is routing, and edits propagate
  to journeys in flight (form instances already carry their own immutable
  pin at the form-version level, which is where attestation lives).

  Traversal state is deliberately not stored — no per-node rows, no
  progress columns. It is derived by `FormFlow.Data.Instances.FlowProgress`
  from the live tree and the journey's form instances, so a template edit
  can never desync it. `status` and `completed_at` are stamps, not caches:
  facts at a moment, written by `FormFlow.Data.Instances.Flows.complete/2` —
  they claim only their moment and are never recomputed.

  A journey carries two opaque host identities: `user_id`, the creating
  user — any principal string, system identities included — and
  `tenant_id`, the host tenant the journey belongs to, `nil` for a host
  with no tenants. Both are stamped at creation and immutable afterwards,
  and both are written to two locations: the dedicated column, so the
  database can index and narrow by them, and a `"user_id"` / `"tenant_id"`
  key inside `metadata`, the free-form host-app map, the same way nodes
  keep a copy of `flow_id` in their properties. The changeset keeps the
  copies in sync — the column is authoritative, and a stale copy arriving
  in `metadata` is overwritten. FormFlow enforces nothing with either: the
  host combines them (and the rest of `metadata`) with the progress helpers
  to decide what the current user sees. Concurrency of journeys per host
  entity is host-app policy — no uniqueness.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias FormFlow.Data.Templates

  @statuses ~w(in_progress completed)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "form_flow_instance_flows" do
    belongs_to(:flow, Templates.Flow)

    field(:status, :string, default: "in_progress")
    field(:user_id, :string)
    field(:tenant_id, :string)
    field(:metadata, :map, default: %{})
    field(:completed_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec)
  end

  def statuses, do: @statuses

  @doc """
  Builds a changeset for a journey.

  `status` and `completed_at` are not castable — completion machinery
  stamps them (see moduledoc). `flow_id`, `user_id`, and `tenant_id` are
  castable at creation and immutable afterwards: a journey can never
  re-point at a different tree (its form instances' paths reference that
  tree's nodes), and provenance never changes.
  """
  def changeset(instance, attrs \\ %{}) do
    instance
    |> cast(attrs, [:flow_id, :user_id, :tenant_id, :metadata])
    |> validate_required([:flow_id])
    |> validate_immutable(:flow_id)
    |> validate_immutable(:user_id)
    |> validate_immutable(:tenant_id)
    |> copy_into_metadata(:user_id, "user_id")
    |> copy_into_metadata(:tenant_id, "tenant_id")
    |> foreign_key_constraint(:flow_id)
  end

  # The same rule Templates.Flow applies to `label`: castable at creation,
  # a commitment afterwards.
  defp validate_immutable(changeset, field) do
    if changeset.data.__meta__.state == :loaded and get_change(changeset, field) do
      add_error(changeset, field, "cannot be changed after creation")
    else
      changeset
    end
  end

  # The dual-write: metadata carries a copy of the column
  defp copy_into_metadata(changeset, field, key) do
    case get_field(changeset, field) do
      nil ->
        changeset

      value ->
        metadata = get_field(changeset, :metadata) || %{}

        put_change(changeset, :metadata, Map.put(metadata, key, value))
    end
  end
end
