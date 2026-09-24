defmodule FormFlow.Data.Instances.Flow do
  @moduledoc """
  `FormFlow.Data.Instances.Flow` Ecto Schema for one traversal of a root
  flow - a journey - the instance-side counterpart of
  `FormFlow.Data.Templates.Flow`, exactly as `FormFlow.Data.Instances.Form`
  is the counterpart of `FormFlow.Data.Templates.Form`.

  `template_flow_id` names the root; the traversal covers the whole tree
  reachable through subflow references, with interior positions addressed by
  `path` on the attached form instances. The flow is referenced *live* - never
  versioned, never snapshotted: structure is routing, and edits propagate
  to journeys in flight (each form instance already records its own form
  version, which never changes on its own, and that is where attestation lives).

  Traversal state is deliberately not stored as the truth - no per-node
  rows, no *authoritative* progress columns. It is derived by
  `FormFlow.Data.Instances.FlowProgress` from the live tree and the
  journey's form instances, so a template edit can never desync it.
  `status` and `completed_at` are recorded facts, not caches: true at a moment,
  written by `FormFlow.Data.Instances.Flows.complete/2` - they claim only
  their moment and are never recomputed. `completed_template_snapshot` is
  the third of that family: the flow tree and the journey's form positions
  as they stood at that same moment
  (`FormFlow.Data.Instances.Flows.Snapshot`), written by the same call,
  null before it, and the one recorded answer to "what did this flow look
  like when I finished it?" once a later template edit has moved the
  derivation on.

  Five columns are a **cache of that derivation**, written by
  `FormFlow.Data.Instances.Flows.update_next_positions/2` alone and never
  cast: `next_path` and `next_node_id`, the first position the flow is open
  at in flow order (`FlowProgress.next_path_position/2` - the path, and its
  last segment for a listing's `in ^ids` filter), `completed_forms` and
  `forms_total`, how many form positions of the whole tree have a completed
  instance and how many there are, and `next_computed_at`, when they were
  last written. `next_path` is null when nothing is actionable - the
  journey completed or blocked - and all five are null on a journey no
  refresh has reached. They are what the last refresh derived; the
  derivation stays the truth, and the flow instance page derives live and
  rewrites them when it finds them stale.

  Every position the flow is open at - not only the first - has a row in
  `FormFlow.Data.Instances.Flow.NextPosition`, the child table a listing
  filters through. The same refresh writes both in one transaction, so
  the row's `next_path` and the table's first row in flow order never
  disagree.

  A journey carries two opaque host identities: `user_id`, the creating
  user - any principal string, system identities included - and
  `tenant_id`, the host tenant the journey belongs to, `nil` for a host
  with no tenants. Both are set at creation and immutable afterwards.
  FormFlow enforces nothing with either: the host combines them (and
  `metadata`, the free-form host-app map) with the progress helpers to
  decide what the current user sees. Concurrency of journeys per host
  entity is host-app policy - no uniqueness.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias FormFlow.Data.Templates

  @statuses ~w(in_progress completed)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "form_flow_instance_flows" do
    belongs_to(:template_flow, Templates.Flow)

    field(:status, :string, default: "in_progress")
    field(:user_id, :string)
    field(:tenant_id, :string)
    field(:metadata, :map, default: %{})
    field(:completed_at, :utc_datetime_usec)
    field(:completed_template_snapshot, :map)

    # The cache of where the flow is open - see the moduledoc
    field(:next_path, {:array, :string})
    field(:next_node_id, :string)
    field(:completed_forms, :integer)
    field(:forms_total, :integer)
    field(:next_computed_at, :utc_datetime_usec)

    has_many(:next_positions, __MODULE__.NextPosition, foreign_key: :instance_flow_id)

    timestamps(type: :utc_datetime_usec)
  end

  def statuses, do: @statuses

  @doc """
  Whether the journey was started while its flow was `pre_release` - the
  marker `FormFlow.Data.Instances.Flows.create/2` leaves in `metadata`
  (`"form_flow" => %{"pre_release" => true}`), so a trial run can be told
  from the real one once the flow opens.
  """
  def pre_release?(%__MODULE__{metadata: metadata}),
    do: match?(%{"form_flow" => %{"pre_release" => true}}, metadata)

  @doc """
  Builds a changeset for a journey.

  `status`, `completed_at`, and `completed_template_snapshot` are not
  castable - completion machinery sets them (see moduledoc) - and neither
  are the five cache columns,
  which `FormFlow.Data.Instances.Flows.update_next_positions/2` writes
  through a plain change of its own, as `complete/2` writes `status` and `completed_at`.
  `template_flow_id`, `user_id`, and `tenant_id` are
  castable at creation and immutable afterwards: a journey can never
  re-point at a different tree (its form instances' paths reference that
  tree's nodes), and provenance never changes.
  """
  def changeset(instance, attrs \\ %{}) do
    instance
    |> cast(attrs, [:template_flow_id, :user_id, :tenant_id, :metadata])
    |> validate_required([:template_flow_id])
    |> validate_immutable(:template_flow_id)
    |> validate_immutable(:user_id)
    |> validate_immutable(:tenant_id)
    |> foreign_key_constraint(:template_flow_id)
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
