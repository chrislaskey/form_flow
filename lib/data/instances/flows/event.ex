defmodule FormFlow.Data.Instances.Flow.Event do
  @moduledoc """
  `FormFlow.Data.Instances.Flow.Event` Ecto Schema for the append-only
  audit trail of a journey, mirroring `FormFlow.Data.Instances.Form.Event`
  discipline: every row carries the responsible user (`user_id`, an opaque
  host-app identity — any principal, including system ones), rows are never
  updated, and events never cascade-delete with their journey — removal
  goes through `FormFlow.Data.Instances.Flows.delete_instance/2`,
  deliberately.

  Events record *mutations* — they are not a pure data audit of every
  answer change. `snapshot` holds free-form notes: what was stranded by a
  template edit, what an admin decided about it. Progress derivation never
  reads events — they are audit, not state, which is what keeps them unable
  to split from the live flow.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias FormFlow.Data.Instances

  @events ~w(created status_changed reconciled)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "form_flow_instance_flow_events" do
    belongs_to(:instance_flow, Instances.Flow, foreign_key: :instance_flow_id)

    field(:event, :string)
    field(:snapshot, :map, default: %{})
    field(:user_id, :string)

    timestamps(type: :utc_datetime_usec)
  end

  def events, do: @events

  @doc "Builds a changeset for an event row."
  def changeset(event, attrs \\ %{}) do
    event
    |> cast(attrs, [:instance_flow_id, :event, :snapshot, :user_id])
    |> validate_required([:instance_flow_id, :event])
    |> validate_inclusion(:event, @events)
    |> foreign_key_constraint(:instance_flow_id)
  end
end
