defmodule FormFlow.Data.Instances.Form.Event do
  @moduledoc """
  `FormFlow.Data.Instances.Form.Event` Ecto Schema for the append-only audit
  trail of an instance form.

  Every pin migration, reopen, and status change writes one event carrying
  the responsible user (`user_id`, an opaque host-app identity — any
  principal, including "system:pin-migration"-style identities — threaded
  from day one, because retrofitting identity into a state machine was the
  reference system's unfinished TODO). When a migration discards or replaces data
  (reset, prune), the prior answers survive here in `data_snapshot` — which
  is why events never cascade-delete with their instance: removing an
  instance goes through `FormFlow.Data.Instances.Forms.delete_instance/2`,
  which deletes events deliberately.

  Rows are never updated.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias FormFlow.Data.Instances
  alias FormFlow.Data.Templates.Form.Version

  @events ~w(created migrated reopened status_changed)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "form_flow_instance_form_events" do
    belongs_to(:instance_form, Instances.Form, foreign_key: :instance_form_id)

    field(:event, :string)

    belongs_to(:from_version, Version, foreign_key: :from_version_id)
    belongs_to(:to_version, Version, foreign_key: :to_version_id)

    field(:data_snapshot, :map, default: %{})
    field(:user_id, :string)

    timestamps(type: :utc_datetime_usec)
  end

  def events, do: @events

  @doc "Builds a changeset for an event row."
  def changeset(event, attrs \\ %{}) do
    event
    |> cast(attrs, [
      :instance_form_id,
      :event,
      :from_version_id,
      :to_version_id,
      :data_snapshot,
      :user_id
    ])
    |> validate_required([:instance_form_id, :event])
    |> validate_inclusion(:event, @events)
    |> foreign_key_constraint(:instance_form_id)
  end
end
