defmodule Demo.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use Demo.DataCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias Demo.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Demo.DataCase
    end
  end

  setup tags do
    Demo.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Demo.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end

  @doc """
  The host's type lists as the pages pass them (`DemoWeb.FormFlowLive.Types`)
  — what `FormFlow.Data.Templates.Flows.copy/2` requires, since the copy
  reads them to decide which property values to drop.

      {:ok, copy} = Flows.copy(flow, [name: "Dog License 2027"] ++ host_types())
  """
  def host_types do
    [
      flow_types: DemoWeb.FormFlowLive.Types.flow_types(),
      form_types: DemoWeb.FormFlowLive.Types.form_types()
    ]
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
