defmodule FormFlow.Test.FakeRepos.SQLiteRepo do
  @moduledoc false

  # An unmigrated repo on SQLite. See FormFlow.Test.FakeRepos.PostgresRepo.

  def __adapter__, do: Ecto.Adapters.SQLite3

  def query(_sql, _params, _opts), do: {:error, %{message: "no such table"}}
end
