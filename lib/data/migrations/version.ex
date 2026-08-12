defmodule FormFlow.Data.Migrations.Version do
  @moduledoc false

  # Tracks which version of FormFlow's schema a database is on.
  #
  # This deliberately does not use Ecto's `:migration_source` option: that is a
  # repo-wide setting (see Ecto.Migrator, which overwrites whatever is passed
  # with `repo.config()[:migration_source]`), so a library cannot claim its own
  # migrations table without relocating the host's migration history too.
  #
  # A one-row table is portable across adapters, which matters because Postgres
  # and SQLite are both supported. Oban solves the same problem with a Postgres
  # table comment, and consequently leaves SQLite unversioned.

  use Ecto.Migration

  @table "form_flow_migrations"

  @doc "The version table's unqualified name."
  def table_name, do: @table

  @doc """
  Creates the version table if it is missing, flushing so it can be read back
  in the same migration.
  """
  def create_table(context) do
    create_if_not_exists table(@table, primary_key: false, prefix: context.prefix) do
      add(:version, :integer, null: false)
    end

    flush()
  end

  def drop_table(context) do
    drop_if_exists(table(@table, prefix: context.prefix))
  end

  @doc """
  Reads the applied version, returning `0` when FormFlow has never migrated.
  """
  def read(context) do
    case context.repo.query("SELECT version FROM #{quoted(context)}", [], log: false) do
      {:ok, %{rows: [[version] | _]}} when is_integer(version) -> version
      _ -> 0
    end
  end

  def write(version, context) when is_integer(version) do
    execute("DELETE FROM #{quoted(context)}")
    execute("INSERT INTO #{quoted(context)} (version) VALUES (#{version})")
  end

  # The prefix is validated as an unquoted identifier before it reaches here
  defp quoted(%{prefix: nil}), do: ~s("#{@table}")
  defp quoted(%{prefix: prefix}), do: ~s("#{prefix}"."#{@table}")
end
