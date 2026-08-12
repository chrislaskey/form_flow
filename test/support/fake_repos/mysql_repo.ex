defmodule FormFlow.Test.FakeRepos.MysqlRepo do
  @moduledoc false

  # An adapter FormFlow ships no migrations for.

  def __adapter__, do: Ecto.Adapters.MyXQL

  def query(_sql, _params, _opts), do: {:error, %{message: "no such table"}}
end
