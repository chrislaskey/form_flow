defmodule Demo.Snapshot do
  @moduledoc """
  The demo's seeded data, as SQL: `priv/repo/form_flow_snapshot.sql`, written
  by `examples/snapshot.sh` from the pet licensing flows built by hand in the
  admin UI.

  Two callers replay it, and they read it through here rather than each
  reaching for the file: the migration that loads it into a fresh database
  (`Demo.Repo.Migrations.LoadFormFlowSnapshot`) and `Demo.Reset`, which puts a
  running demo back to it.

  The file is one `INSERT` per line in parent-first table order — `sqlite3`
  escapes embedded newlines with `replace()`, which is what makes splitting on
  lines safe.
  """

  @doc "Every `INSERT` in the snapshot, in the order it was dumped."
  def statements do
    path()
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.filter(&String.starts_with?(&1, "INSERT INTO "))
  end

  @doc """
  Where the snapshot lives. Resolved through the application rather than
  `__DIR__`, so it is found in a release too.
  """
  def path, do: Application.app_dir(:demo, "priv/repo/form_flow_snapshot.sql")
end
