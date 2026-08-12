defmodule FormFlow.Test.FakeRepos.PostgresRepo do
  @moduledoc false

  # Minimal stand-in for a repo on Postgres. FormFlow.Data.Migration only needs
  # `__adapter__/0` to pick a migrator and `query/3` to read the applied
  # version, so tests that don't touch DDL need nothing more. The demo app
  # covers the DDL itself against a real SQLite database.
  #
  # This repo reports an unmigrated database: no version table yet.

  def __adapter__, do: Ecto.Adapters.Postgres

  def query(_sql, _params, _opts), do: {:error, %{message: "no such table"}}
end
