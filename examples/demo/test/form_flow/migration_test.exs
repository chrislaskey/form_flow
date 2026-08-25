defmodule Demo.FormFlowMigrationTest do
  @moduledoc """
  Exercises `FormFlow.Data.Migration` against a real database — the library's
  own tests use repo stubs and never issue DDL, so this is where the migration
  is proven to actually run.

  The migration itself is `priv/repo/migrations/*_add_form_flow.exs`, generated
  by `mix form_flow.gen.migration` and applied by `mix ecto.migrate`.
  """

  use Demo.DataCase, async: false

  alias FormFlow.Data.Migration

  @timestamp "2026-01-01 00:00:00.000000"

  test "the database is migrated to the version FormFlow ships" do
    assert Migration.migrated_version(repo: Repo) == Migration.current_version(repo: Repo)
  end

  test "the version is read through the configured repo, with no argument" do
    assert Application.get_env(:form_flow, :repo) == Repo
    assert Migration.migrated_version() == 1
  end

  test "the template, version, instance, and event tables accept rows" do
    {:ok, form_id} = insert_template("Enrollment")
    {:ok, version_id} = insert_version(form_id)

    instance_id = Ecto.UUID.generate()

    assert {:ok, _} =
             Repo.query(
               """
               INSERT INTO form_flow_instance_forms
                 (id, app, template_form_version_id, status, data, labels_snapshot,
                  metadata, inserted_at, updated_at)
               VALUES (?, 'default', ?, 'in_progress', '{"name":"Ada"}', '{}', '{}', ?, ?)
               """,
               [instance_id, version_id, @timestamp, @timestamp]
             )

    assert {:ok, _} =
             Repo.query(
               """
               INSERT INTO form_flow_instance_form_events
                 (id, instance_form_id, event, to_version_id, data_snapshot,
                  inserted_at, updated_at)
               VALUES (?, ?, 'created', ?, '{}', ?, ?)
               """,
               [Ecto.UUID.generate(), instance_id, version_id, @timestamp, @timestamp]
             )

    assert {:ok, %{rows: [[1]]}} = Repo.query("SELECT count(*) FROM form_flow_instance_forms")
  end

  test "instances cannot be orphaned — the version pin is RESTRICT" do
    {:ok, form_id} = insert_template("Enrollment")
    {:ok, version_id} = insert_version(form_id)

    {:ok, _} =
      Repo.query(
        """
        INSERT INTO form_flow_instance_forms
          (id, app, template_form_version_id, status, data, labels_snapshot,
           metadata, inserted_at, updated_at)
        VALUES (?, 'default', ?, 'in_progress', '{}', '{}', '{}', ?, ?)
        """,
        [Ecto.UUID.generate(), version_id, @timestamp, @timestamp]
      )

    assert {:error, _} =
             Repo.query("DELETE FROM form_flow_template_form_versions WHERE id = ?", [version_id])
  end

  test "catalog names are unique per app; owned forms may repeat them" do
    {:ok, _} = insert_template("Enrollment")

    # The partial unique index guards the catalog (owner_graph_id IS NULL)
    assert {:error, _} = insert_template("Enrollment")
    assert {:ok, _} = insert_template("Enrollment", app: "other-app")

    # Owned forms are outside the catalog — yearly copies repeat names freely
    {:ok, graph_id} = insert_graph()
    assert {:ok, _} = insert_template("Enrollment", owner_graph_id: graph_id)
    assert {:ok, _} = insert_template("Enrollment", owner_graph_id: graph_id)
  end

  defp insert_template(name, opts \\ []) do
    id = Ecto.UUID.generate()
    app = Keyword.get(opts, :app, "default")
    owner_graph_id = Keyword.get(opts, :owner_graph_id)

    result =
      Repo.query(
        """
        INSERT INTO form_flow_template_forms
          (id, app, name, owner_graph_id, inserted_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        [id, app, name, owner_graph_id, @timestamp, @timestamp]
      )

    with {:ok, _} <- result, do: {:ok, id}
  end

  defp insert_version(form_id) do
    id = Ecto.UUID.generate()

    result =
      Repo.query(
        """
        INSERT INTO form_flow_template_form_versions
          (id, template_form_id, status, lock_version, definition, inserted_at, updated_at)
        VALUES (?, ?, 'draft', 1, '{}', ?, ?)
        """,
        [id, form_id, @timestamp, @timestamp]
      )

    with {:ok, _} <- result, do: {:ok, id}
  end

  defp insert_graph do
    id = Ecto.UUID.generate()

    result =
      Repo.query(
        """
        INSERT INTO form_flow_graphs (id, label, inserted_at, updated_at)
        VALUES (?, 'forms', ?, ?)
        """,
        [id, @timestamp, @timestamp]
      )

    with {:ok, _} <- result, do: {:ok, id}
  end
end
