defmodule FormFlow.Data.Templates.Form.VersionTest do
  use ExUnit.Case, async: true

  alias FormFlow.Data.Templates.Form.Version

  @form_id Ecto.UUID.generate()

  describe "create_changeset/2" do
    test "a version is born a draft with no number" do
      changeset =
        Version.create_changeset(%Version{}, %{
          template_form_id: @form_id,
          definition: %{"fields" => []}
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :status) == "draft"
      assert Ecto.Changeset.get_field(changeset, :version) == nil
    end

    test "requires the lineage" do
      refute Version.create_changeset(%Version{}, %{definition: %{}}).valid?
    end

    test "version, published_at, status, and lock_version are not castable" do
      changeset =
        Version.create_changeset(%Version{}, %{
          template_form_id: @form_id,
          version: 7,
          published_at: DateTime.utc_now(),
          status: "published",
          lock_version: 99
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :version) == nil
      assert Ecto.Changeset.get_field(changeset, :published_at) == nil
      assert Ecto.Changeset.get_field(changeset, :status) == "draft"
      assert Ecto.Changeset.get_field(changeset, :lock_version) == 1
    end
  end

  describe "update_changeset/2 — immutability enforcement" do
    test "a draft's definition is editable, under the optimistic lock" do
      draft = loaded(%Version{status: "draft", lock_version: 1, template_form_id: @form_id})

      changeset = Version.update_changeset(draft, %{definition: %{"fields" => []}})

      assert changeset.valid?
      assert changeset.changes.definition == %{"fields" => []}
      # optimistic_lock filters on the current lock and increments at write
      # time — the same-draft "changed under you" guard
      assert changeset.filters == %{lock_version: 1}
    end

    test "a published definition rejects every change" do
      published = loaded(%Version{status: "published", version: 3, template_form_id: @form_id})

      changeset = Version.update_changeset(published, %{definition: %{"changed" => true}})

      refute changeset.valid?
      assert {"cannot be changed after publishing", _} = changeset.errors[:definition]
    end

    test "an archived definition rejects every change" do
      archived = loaded(%Version{status: "archived", version: 3, template_form_id: @form_id})

      refute Version.update_changeset(archived, %{definition: %{"changed" => true}}).valid?
    end
  end

  describe "status_changeset — whitelisted transitions" do
    test "draft → published stamps the assigned number and timestamp" do
      draft = loaded(%Version{status: "draft", template_form_id: @form_id})
      now = DateTime.utc_now()

      changeset = Version.status_changeset(draft, "published", 4, now)

      assert changeset.valid?
      assert changeset.changes.status == "published"
      assert changeset.changes.version == 4
      assert changeset.changes.published_at == now
    end

    test "published → archived" do
      published = loaded(%Version{status: "published", version: 2, template_form_id: @form_id})

      assert Version.status_changeset(published, "archived").valid?
    end

    test "draft → archived is rejected — only published work can be retired" do
      draft = loaded(%Version{status: "draft", template_form_id: @form_id})

      changeset = Version.status_changeset(draft, "archived")

      refute changeset.valid?
      assert {"cannot transition from draft to archived", _} = changeset.errors[:status]
    end

    test "archived → published is rejected — un-archiving is not a thing yet" do
      archived = loaded(%Version{status: "archived", version: 2, template_form_id: @form_id})

      refute Version.status_changeset(archived, "published", 5, DateTime.utc_now()).valid?
    end

    test "published → published is rejected — publishing is not repeatable" do
      published = loaded(%Version{status: "published", version: 2, template_form_id: @form_id})

      refute Version.status_changeset(published, "published", 3, DateTime.utc_now()).valid?
    end
  end

  defp loaded(version), do: Ecto.put_meta(version, state: :loaded)
end
