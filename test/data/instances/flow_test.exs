defmodule FormFlow.Data.Instances.FlowTest do
  use ExUnit.Case, async: true

  alias FormFlow.Data.Instances

  @flow_id Ecto.UUID.generate()

  describe "Instances.Flow.changeset/2" do
    test "requires the root flow — a journey always knows what it traverses" do
      refute Instances.Flow.changeset(%Instances.Flow{}, %{}).valid?

      changeset =
        Instances.Flow.changeset(%Instances.Flow{}, %{
          flow_id: @flow_id,
          user_id: "user-42",
          metadata: %{"cycle" => "2026"}
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :status) == "in_progress"
    end

    test "status and completed_at are not castable — completion machinery stamps them" do
      changeset =
        Instances.Flow.changeset(%Instances.Flow{}, %{
          flow_id: @flow_id,
          status: "completed",
          completed_at: DateTime.utc_now()
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :status) == "in_progress"
      assert Ecto.Changeset.get_field(changeset, :completed_at) == nil
    end

    test "flow_id and user_id are immutable after creation" do
      persisted =
        %Instances.Flow{flow_id: @flow_id, user_id: "user-42"}
        |> Ecto.put_meta(state: :loaded)

      changeset = Instances.Flow.changeset(persisted, %{flow_id: Ecto.UUID.generate()})
      refute changeset.valid?
      assert {"cannot be changed after creation", _} = changeset.errors[:flow_id]

      changeset = Instances.Flow.changeset(persisted, %{user_id: "user-43"})
      refute changeset.valid?
      assert {"cannot be changed after creation", _} = changeset.errors[:user_id]

      assert Instances.Flow.changeset(persisted, %{metadata: %{"note" => "ok"}}).valid?
    end
  end

  describe "Instances.Flow.Event.changeset/2" do
    test "requires the journey and a whitelisted event" do
      instance_id = Ecto.UUID.generate()

      refute Instances.Flow.Event.changeset(%Instances.Flow.Event{}, %{event: "created"}).valid?

      refute Instances.Flow.Event.changeset(%Instances.Flow.Event{}, %{
               instance_flow_id: instance_id,
               event: "deleted"
             }).valid?

      changeset =
        Instances.Flow.Event.changeset(%Instances.Flow.Event{}, %{
          instance_flow_id: instance_id,
          event: "reconciled",
          snapshot: %{"stranded_path" => ["a", "b"]},
          user_id: "admin-7"
        })

      assert changeset.valid?
    end
  end
end
