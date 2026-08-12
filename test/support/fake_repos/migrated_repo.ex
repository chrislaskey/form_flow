defmodule FormFlow.Test.FakeRepos.MigratedRepo do
  @moduledoc false

  # A repo already migrated to version 1.

  def __adapter__, do: Ecto.Adapters.Postgres

  def query(_sql, _params, _opts), do: {:ok, %{rows: [[1]]}}
end
