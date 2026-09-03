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
          metadata: %{"source" => "import"}
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :status) == "in_progress"
    end

    test "status is not castable — completion machinery stamps it" do
      changeset =
        Instances.Form.changeset(%Instances.Form{}, %{
          template_form_version_id: @version_id,
          status: "approved",
          completed_at: DateTime.utc_now()
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :status) == "in_progress"
      assert Ecto.Changeset.get_field(changeset, :completed_at) == nil
    end

    test "the visit identity is both-or-neither: a journey requires a path" do
      # standalone: neither — fine (the existing mode)
      assert Instances.Form.changeset(%Instances.Form{}, %{
               template_form_version_id: @version_id
             }).valid?

      # a journey without a stamped path is invalid — the partial unique
      # index can't catch this half, the changeset must
      changeset =
        Instances.Form.changeset(%Instances.Form{}, %{
          template_form_version_id: @version_id,
          instance_flow_id: Ecto.UUID.generate()
        })

      refute changeset.valid?
      assert {"is required for an in-journey form instance", _} = changeset.errors[:path]

      # path is not castable — only visit_changeset/4 stamps it
      changeset =
        Instances.Form.changeset(%Instances.Form{}, %{
          template_form_version_id: @version_id,
          path: [Ecto.UUID.generate()]
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :path) == []
    end

    test "visit_changeset/4 stamps the full visit identity" do
      instance_flow_id = Ecto.UUID.generate()
      path = [Ecto.UUID.generate(), Ecto.UUID.generate()]

      changeset =
        Instances.Form.visit_changeset(
          %Instances.Form{},
          %{template_form_version_id: @version_id, data: %{"name" => "Ada"}},
          instance_flow_id,
          path
        )

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :instance_flow_id) == instance_flow_id
      assert Ecto.Changeset.get_field(changeset, :path) == path
    end

    test "superseded_at is not castable — reconciliation stamps it" do
      changeset =
        Instances.Form.changeset(%Instances.Form{}, %{
          template_form_version_id: @version_id,
          superseded_at: DateTime.utc_now()
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :superseded_at) == nil
    end

    test "user_id and tenant_id are written to the column and copied into metadata" do
      changeset =
        Instances.Form.changeset(%Instances.Form{}, %{
          template_form_version_id: @version_id,
          user_id: "user-42",
          tenant_id: "tenant-1",
          metadata: %{"source" => "import"}
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :user_id) == "user-42"
      assert Ecto.Changeset.get_field(changeset, :tenant_id) == "tenant-1"

      assert Ecto.Changeset.get_field(changeset, :metadata) == %{
               "source" => "import",
               "user_id" => "user-42",
               "tenant_id" => "tenant-1"
             }
    end

    test "visit_changeset/4 stamps the same identities" do
      changeset =
        Instances.Form.visit_changeset(
          %Instances.Form{},
          %{template_form_version_id: @version_id, user_id: "user-42", tenant_id: "tenant-1"},
          Ecto.UUID.generate(),
          [Ecto.UUID.generate()]
        )

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :user_id) == "user-42"
      assert Ecto.Changeset.get_field(changeset, :tenant_id) == "tenant-1"

      assert Ecto.Changeset.get_field(changeset, :metadata) == %{
               "user_id" => "user-42",
               "tenant_id" => "tenant-1"
             }
    end

    test "a host with no tenants leaves tenant_id nil and out of metadata" do
      changeset =
        Instances.Form.changeset(%Instances.Form{}, %{
          template_form_version_id: @version_id,
          user_id: "user-42"
        })

      assert Ecto.Changeset.get_field(changeset, :tenant_id) == nil
      assert Ecto.Changeset.get_field(changeset, :metadata) == %{"user_id" => "user-42"}
    end

    test "user_id and tenant_id are immutable after creation" do
      persisted =
        %Instances.Form{
          template_form_version_id: @version_id,
          user_id: "user-42",
          tenant_id: "tenant-1"
        }
        |> Ecto.put_meta(state: :loaded)

      changeset = Instances.Form.changeset(persisted, %{user_id: "user-43"})
      refute changeset.valid?
      assert {"cannot be changed after creation", _} = changeset.errors[:user_id]

      changeset = Instances.Form.changeset(persisted, %{tenant_id: "tenant-2"})
      refute changeset.valid?
      assert {"cannot be changed after creation", _} = changeset.errors[:tenant_id]

      assert Instances.Form.changeset(persisted, %{data: %{"name" => "Ada"}}).valid?
    end

    test "the column is authoritative — a stale copy in metadata is overwritten" do
      persisted =
        %Instances.Form{
          template_form_version_id: @version_id,
          user_id: "user-42",
          tenant_id: "tenant-1",
          metadata: %{"user_id" => "user-42", "tenant_id" => "tenant-1"}
        }
        |> Ecto.put_meta(state: :loaded)

      changeset =
        Instances.Form.changeset(persisted, %{
          metadata: %{"user_id" => "impostor", "tenant_id" => "elsewhere", "source" => "import"}
        })

      assert changeset.valid?

      assert Ecto.Changeset.get_field(changeset, :metadata) == %{
               "user_id" => "user-42",
               "tenant_id" => "tenant-1",
               "source" => "import"
             }
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
          snapshot_data: %{"old" => "answer"},
          user_id: "admin-7"
        })

      assert changeset.valid?
    end
  end
end
