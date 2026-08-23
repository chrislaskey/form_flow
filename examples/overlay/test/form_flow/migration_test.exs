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
    assert Migration.migrated_version() == 2
  end

  test "the template and instance tables accept rows" do
    {:ok, _} = insert_template("Enrollment")
    {:ok, %{rows: [[template_id]]}} = Repo.query("SELECT id FROM form_flow_template_forms")

    assert {:ok, _} =
             Repo.query(
               """
               INSERT INTO form_flow_instance_forms
                 (app, template_form_id, state, data, inserted_at, updated_at)
               VALUES ('default', ?, 'in_progress', '{"name":"Ada"}', ?, ?)
               """,
               [template_id, @timestamp, @timestamp]
             )

    assert {:ok, %{rows: [[1]]}} = Repo.query("SELECT count(*) FROM form_flow_instance_forms")
  end

  test "template names are unique per app" do
    {:ok, _} = insert_template("Enrollment")

    assert {:error, _} = insert_template("Enrollment")
    assert {:ok, _} = insert_template("Enrollment", "other-app")
  end

  defp insert_template(name, app \\ "default") do
    Repo.query(
      """
      INSERT INTO form_flow_template_forms (app, name, definition, inserted_at, updated_at)
      VALUES (?, ?, '{}', ?, ?)
      """,
      [app, name, @timestamp, @timestamp]
    )
  end
end
