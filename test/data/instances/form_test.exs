defmodule FormFlow.Data.Instances.FormTest do
  use ExUnit.Case, async: true

  alias FormFlow.Data.Instances

  @version_id Ecto.UUID.generate()

  describe "Instances.Form.changeset/2" do
    test "requires the version pin — an instance always knows what it renders against" do
      refute Instances.Form.changeset(%Instances.Form{}, %{data: %{}}).valid?

      changeset =
        Instances.Form.changeset(%Instances.Form{}, %{
          template_form_version_id: @version_id,
          data: %{"first_name" => "Ada"},
          subject: "user-123",
          metadata: %{"source" => "import"}
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :status) == "in_progress"
    end

    test "status is whitelisted" do
      changeset =
        Instances.Form.changeset(%Instances.Form{}, %{
          template_form_version_id: @version_id,
          status: "approved"
        })

      refute changeset.valid?
      assert {"is invalid", _} = changeset.errors[:status]
    end

    test "labels_snapshot is not castable — completion machinery stamps it" do
      changeset =
        Instances.Form.changeset(%Instances.Form{}, %{
          template_form_version_id: @version_id,
          labels_snapshot: %{"first_name" => "First name"}
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :labels_snapshot) == %{}
    end
  end

  describe "Instances.Form.Event.changeset/2" do
    test "requires the instance and a whitelisted event" do
      instance_id = Ecto.UUID.generate()

      refute Instances.Form.Event.changeset(%Instances.Form.Event{}, %{event: "migrated"}).valid?

      refute Instances.Form.Event.changeset(%Instances.Form.Event{}, %{
               instance_form_id: instance_id,
               event: "deleted"
             }).valid?

      changeset =
        Instances.Form.Event.changeset(%Instances.Form.Event{}, %{
          instance_form_id: instance_id,
          event: "migrated",
          from_version_id: @version_id,
          to_version_id: Ecto.UUID.generate(),
          data_snapshot: %{"old" => "answer"},
          actor: "admin-7"
        })

      assert changeset.valid?
    end
  end
end
