defmodule FormFlow.Data.Templates.Flow.Event do
  @moduledoc """
  `FormFlow.Data.Templates.Flow.Event` Ecto Schema for the append-only
  audit trail of a flow template, mirroring the two instance-side logs
  (`FormFlow.Data.Instances.Flow.Event`, `FormFlow.Data.Instances.Form.Event`)
  and their discipline: every row carries the responsible principal
  (`user_id`, an opaque host-app identity — the admin at the page, or
  nothing when a host passes none), rows are never updated, and events never
  cascade-delete with their flow — the two paths that remove a flow row,
  `FormFlow.Data.Templates.Flows.delete/1` and the sweep of unreachable
  subflows inside a save, delete the log deliberately first.

  Root flows only: an owned subflow's status and history are its root's,
  as its health is, so it never has rows here. Five events today. `created`
  is written by `Flows.create/2` and by `Flows.copy/2` for the root they
  make.
  `status_changed` is written by `Flows.update_status/3` with the old and
  new status in `snapshot` (`"from"`, `"to"`); it is the answer to "when did
  we open this, when did we stop new starts, and who did it".
  `health_ignored` and `health_unignored` are written by
  `FormFlow.Data.Templates.Flows.Health.ignore/3` and `stop_ignoring/3`
  beside the record they keep on the flow, with the entry's `"code"`,
  `"path"`, and `"subject"` in `snapshot` — the record says what is ignored
  now; the log says who decided it, and when a decision was reversed.
  `pre_release_instances_deleted` is written by
  `FormFlow.Data.Instances.Flows.delete_pre_release/2` with the `"count"`
  deleted, so the trial run an admin cleared away on opening the flow is
  not simply missing.

  Events are audit, not state. `FormFlow.Data.Templates.Flow.status` is the
  column every page reads; nothing derives it from the log, which is what
  keeps the two from disagreeing. `snapshot` is free-form: what a later
  event kind wants to remember (a structural save's counts, a copy's
  source) goes there, so a new kind is a string added to `events/0` and
  nothing more.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias FormFlow.Data.Templates.Flow

  @events ~w(created status_changed health_ignored health_unignored pre_release_instances_deleted)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "form_flow_template_flow_events" do
    belongs_to(:flow, Flow, foreign_key: :flow_id)

    field(:event, :string)
    field(:snapshot, :map, default: %{})
    field(:user_id, :string)

    timestamps(type: :utc_datetime_usec)
  end

  def events, do: @events

  @doc "Builds a changeset for an event row."
  def changeset(event, attrs \\ %{}) do
    event
    |> cast(attrs, [:flow_id, :event, :snapshot, :user_id])
    |> validate_required([:flow_id, :event])
    |> validate_inclusion(:event, @events)
    |> foreign_key_constraint(:flow_id)
  end
end
