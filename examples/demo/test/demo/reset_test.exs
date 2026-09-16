defmodule Demo.ResetTest do
  use Demo.DataCase

  alias Demo.Reset
  alias Demo.Snapshot

  # The test database starts empty — the snapshot migration skips :test — so
  # these build their own "before" out of the snapshot itself.
  defp load_snapshot do
    Repo.query!("PRAGMA defer_foreign_keys = ON")
    Enum.each(Snapshot.statements(), &Repo.query!(&1, [], log: false))
  end

  defp counts do
    Map.new(Reset.tables(), fn table ->
      %{rows: [[count]]} = Repo.query!("SELECT count(*) FROM #{table}", [], log: false)
      {table, count}
    end)
  end

  defp flow_ids do
    %{rows: rows} = Repo.query!("SELECT id FROM form_flow_template_flows ORDER BY id")
    List.flatten(rows)
  end

  test "loads the snapshot into an empty database" do
    assert flow_ids() == []

    {:ok, counts} = Reset.run()

    assert counts.deleted == 0
    assert counts.loaded == length(Snapshot.statements())
    refute flow_ids() == []
  end

  test "clears what was built since, and puts the shipped data back" do
    load_snapshot()
    shipped = counts()
    shipped_flows = flow_ids()

    %{rows: [[template_id]]} = Repo.query!("SELECT id FROM form_flow_template_flows LIMIT 1")

    Repo.query!(
      """
      INSERT INTO form_flow_template_flows
        (id, name, label, tenant_id, slug, status, properties, owner_flow_id, inserted_at, updated_at)
      SELECT 'built-by-a-visitor', 'Built by a visitor', label, tenant_id, 'built-by-a-visitor',
             status, properties, owner_flow_id, inserted_at, updated_at
      FROM form_flow_template_flows WHERE id = ?
      """,
      [template_id]
    )

    assert "built-by-a-visitor" in flow_ids()

    {:ok, _counts} = Reset.run()

    refute "built-by-a-visitor" in flow_ids()
    assert flow_ids() == shipped_flows
    assert counts() == shipped
  end

  test "runs twice without drifting" do
    {:ok, _} = Reset.run()
    once = counts()

    {:ok, counts} = Reset.run()

    assert counts.deleted > 0
    assert counts() == once
  end

  test "leaves the FormFlow schema version alone" do
    %{rows: [[version]]} = Repo.query!("SELECT version FROM form_flow_database_migrations")

    {:ok, _} = Reset.run()

    assert %{rows: [[^version]]} =
             Repo.query!("SELECT version FROM form_flow_database_migrations")
  end

  test "empties every FormFlow table, not a list written down here" do
    tables = Reset.tables()

    assert "form_flow_template_flows" in tables
    assert "form_flow_instance_flows" in tables
    assert Enum.all?(tables, &String.starts_with?(&1, "form_flow_"))

    from_database =
      Repo.query!("SELECT name FROM sqlite_master WHERE type = 'table'")
      |> Map.get(:rows)
      |> List.flatten()
      |> Enum.filter(&String.starts_with?(&1, "form_flow_"))
      |> Enum.sort()

    assert tables == from_database
  end
end
