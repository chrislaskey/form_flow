defmodule FormFlow.Data.Templates.Flow.EventTest do
  use ExUnit.Case, async: true

  alias FormFlow.Data.Templates.Flow.Event

  test "an event needs its flow and a kind the log knows" do
    flow_id = Ecto.UUID.generate()

    changeset =
      Event.changeset(%Event{}, %{
        flow_id: flow_id,
        event: "status_changed",
        snapshot: %{"from" => "draft", "to" => "open"},
        user_id: "admin"
      })

    assert changeset.valid?
    assert changeset.changes.snapshot == %{"from" => "draft", "to" => "open"}

    refute Event.changeset(%Event{}, %{event: "status_changed"}).valid?
    refute Event.changeset(%Event{}, %{flow_id: flow_id, event: "published"}).valid?

    # The two kinds today; a later kind is a string added here
    assert Event.events() == ~w(created status_changed)
  end

  test "the actor is optional — a host that passes no user_id logs the change unsigned" do
    changeset = Event.changeset(%Event{}, %{flow_id: Ecto.UUID.generate(), event: "created"})

    assert changeset.valid?
    refute Map.has_key?(changeset.changes, :user_id)
  end
end
