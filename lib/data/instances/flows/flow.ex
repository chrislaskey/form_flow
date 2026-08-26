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
  progress columns. It is derived by `FormFlow.Data.Instances.Progress`
  from the live tree and the journey's form instances, so a template edit
  can never desync it. `status` and `completed_at` are stamps, not caches:
  facts at a moment, written by `FormFlow.Data.Instances.Flows.complete/2` —
  they claim only their moment and are never recomputed.

  A journey carries no scoping column. It does carry an owner: `user_id`,
  the creating user, an opaque host handle — any principal string, system
  identities included — stamped at creation and immutable afterwards.
  FormFlow enforces nothing with it: the host combines it (and `metadata`,
  the free-form host-app map) with the progress helpers to decide what the
  current user sees. Concurrency of journeys per host entity is host-app
  policy — no uniqueness.
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
    field(:metadata, :map, default: %{})
    field(:completed_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec)
  end

  def statuses, do: @statuses

  @doc """
  Builds a changeset for a journey.

  `status` and `completed_at` are not castable — completion machinery
  stamps them (see moduledoc). `flow_id` and `user_id` are castable at
  creation and immutable afterwards: a journey can never re-point at a
  different tree (its form instances' paths reference that tree's nodes),
  and provenance never changes.
  """
  def changeset(instance, attrs \\ %{}) do
    instance
    |> cast(attrs, [:flow_id, :user_id, :metadata])
    |> validate_required([:flow_id])
    |> validate_immutable(:flow_id)
    |> validate_immutable(:user_id)
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
end
