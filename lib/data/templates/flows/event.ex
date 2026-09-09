defmodule FormFlow.Data.Templates.Flow.Event do
  @moduledoc """
  `FormFlow.Data.Templates.Flow.Event` Ecto Schema for the append-only
  audit trail of a flow template, mirroring the two instance-side logs
  (`FormFlow.Data.Instances.Flow.Event`, `FormFlow.Data.Instances.Form.Event`)
  and their discipline: every row carries the responsible principal
  (`user_id`, an opaque host-app identity — the admin at the page, or
  nothing when a host passes none), rows are never updated, and events never
  cascade-delete with their flow — removal goes through
  `FormFlow.Data.Templates.Flows.delete/1`, which deletes them deliberately
  before the flow.

  Two events today. `created` is written by `Flows.create/2` and by
  `Flows.copy/2` for every flow row they insert, owned subflows included.
  `status_changed` is written by `Flows.update_status/3` with the old and
  new status in `snapshot` (`"from"`, `"to"`); it is the answer to "when did
  we open this, when did we stop new starts, and who did it".

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

  @events ~w(created status_changed)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "form_flow_flow_events" do
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
