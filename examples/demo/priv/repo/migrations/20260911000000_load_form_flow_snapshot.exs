defmodule Demo.Repo.Migrations.LoadFormFlowSnapshot do
  @moduledoc """
  Replays `priv/repo/form_flow_snapshot.sql` into FormFlow's tables, so a
  freshly generated demo starts with the pet licensing flows and forms that
  were built by hand in the admin UI.

  The SQL is written by `examples/snapshot.sh`: one `INSERT` per line, in
  parent-first table order. Rebuild it after editing the flows, then commit.

  Two cases load nothing:

    * the test database — the demo's tests count on empty tables
    * a database that already has flows — this migration is pending on the
      very database the snapshot was taken from, and replaying it there would
      collide on primary keys. `mix ecto.reset` is the way to reload.

  Rolling back leaves the rows in place: the snapshot is the demo's data, not
  a schema change, and deleting it is `mix ecto.reset`'s job.
  """

  use Ecto.Migration

  require Logger

  @snapshot Path.expand("../form_flow_snapshot.sql", __DIR__)

  def up do
    cond do
      test_env?() ->
        Logger.info("Skipping the FormFlow snapshot in the test environment")

      flows_exist?() ->
        Logger.info("Skipping the FormFlow snapshot: the database already has flows")

      true ->
        statements = read_statements()
        Logger.info("Loading #{length(statements)} FormFlow rows from the snapshot")

        # Parent-first order makes this a formality, but a flow can be copied
        # from one built after it, so let SQLite check references at commit.
        # Queried directly with logging off rather than through execute/1, which
        # would echo every INSERT — some of them kilobytes of JSON — into the
        # migrate log.
        repo().query!("PRAGMA defer_foreign_keys = ON", [], log: false)
        Enum.each(statements, &repo().query!(&1, [], log: false))
    end
  end

  def down, do: :ok

  defp test_env?, do: function_exported?(Mix, :env, 0) and Mix.env() == :test

  defp flows_exist? do
    %{rows: [[count]]} = repo().query!("SELECT count(*) FROM form_flow_template_flows")
    count > 0
  end

  defp read_statements do
    @snapshot
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.filter(&String.starts_with?(&1, "INSERT INTO "))
  end
end
