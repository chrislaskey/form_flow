defmodule FormFlow.Data.Migration do
  @moduledoc """
  `FormFlow.Data.Migration` module creates and updates FormFlow's tables inside
  the parent application's database.

  FormFlow doesn't own a repo or a migration directory. Instead the parent app
  generates one ordinary Ecto migration that calls into this module, so
  FormFlow's DDL runs through the same `mix ecto.migrate`, `mix ecto.rollback`,
  and release tooling as every other migration in the app:

      defmodule MyApp.Repo.Migrations.AddFormFlow do
        use Ecto.Migration

        def up, do: FormFlow.Data.Migration.up(version: 1)
        def down, do: FormFlow.Data.Migration.down(version: 1)
      end

  `mix form_flow.gen.migration` writes exactly that file.

  ## Versions

  FormFlow's schema is versioned independently of the host's migration history.
  The applied version lives in a `form_flow_migrations` table, so `up/1` knows
  which steps still need to run and is safe to run more than once.

  Pin the version in the generated migration. A pinned migration keeps doing
  what it did when it was written, and upgrading FormFlow means generating a
  second migration for the newer version rather than silently changing the
  meaning of an old one.

  ## Options

    * `:version` - the version to migrate to. Defaults to the latest version
      for `up/1` and the initial version for `down/1`.

    * `:prefix` - the database schema to run in. Defaults to the prefix the
      migration itself is running under, so `mix ecto.migrate --prefix` works
      without passing anything here. Postgres only.

    * `:repo` - the repo to inspect the applied version with. Defaults to the
      repo running the migration, falling back to the configured
      `config :form_flow, repo: MyApp.Repo`. Only needed when calling outside
      of a migration.

  ## Adapters

  Postgres and SQLite are supported out of the box, dispatched on the repo's
  adapter. Apps on another adapter can supply their own module implementing
  this behaviour:

      config :form_flow, migrator: MyApp.FormFlowMigrator
  """

  use Ecto.Migration

  alias FormFlow.Data.Migrations.Version
  alias FormFlow.Data.Repo, as: DataRepo

  @doc "The first version this adapter can migrate to."
  @callback initial_version() :: pos_integer()

  @doc "The latest version this adapter knows how to migrate to."
  @callback current_version() :: pos_integer()

  @doc "The module implementing a single version's `up/1` and `down/1`."
  @callback version_module(pos_integer()) :: module()

  @doc """
  Migrates FormFlow's tables up to `:version`, or to the latest version.

  Running this when the database is already at or beyond the target version is
  a no-op, so it is safe to re-run.
  """
  def up(opts \\ []) when is_list(opts) do
    context = context(opts, :up)

    Version.create_table(context)

    applied = Version.read(context)

    cond do
      applied >= context.version ->
        :ok

      applied == 0 ->
        change(context.migrator.initial_version()..context.version//1, :up, context)

      true ->
        change((applied + 1)..context.version//1, :up, context)
    end
  end

  @doc """
  Migrates FormFlow's tables down to and including `:version`.

  Defaults to the initial version, which removes every table FormFlow created
  — including the data in them.
  """
  def down(opts \\ []) when is_list(opts) do
    context = context(opts, :down)

    applied = Version.read(context)

    if applied >= context.version do
      change(applied..context.version//-1, :down, context)
    else
      :ok
    end
  end

  @doc """
  The version the database is currently migrated to, or `0` if FormFlow has
  never been migrated.
  """
  def migrated_version(opts \\ []) when is_list(opts) do
    opts
    |> context(:current)
    |> Version.read()
  end

  @doc """
  The latest version the installed FormFlow knows how to migrate to.
  """
  def current_version(opts \\ []) when is_list(opts) do
    context(opts, :current).migrator.current_version()
  end

  defp change(range, direction, context) do
    Enum.each(range, fn version ->
      apply(context.migrator.version_module(version), direction, [context])
    end)

    lowest = Enum.min(range)
    initial = context.migrator.initial_version()

    cond do
      direction == :up -> Version.write(Enum.max(range), context)
      lowest == initial -> Version.drop_table(context)
      true -> Version.write(lowest - 1, context)
    end
  end

  defp context(opts, direction) do
    opts = Map.new(opts)
    migrator = migrator(opts)

    %{
      migrator: migrator,
      repo: repo(opts),
      prefix: prefix(opts),
      version: version(opts, migrator, direction)
    }
  end

  defp migrator(opts) do
    case Application.get_env(:form_flow, :migrator) do
      nil -> adapter_migrator(opts)
      migrator -> migrator
    end
  end

  defp adapter_migrator(opts) do
    case repo(opts).__adapter__() do
      Ecto.Adapters.Postgres ->
        FormFlow.Data.Migrations.Postgres

      Ecto.Adapters.SQLite3 ->
        FormFlow.Data.Migrations.SQLite

      adapter ->
        raise ArgumentError, """
        FormFlow has no migrations for the #{inspect(adapter)} adapter.

        Supported adapters are Ecto.Adapters.Postgres and Ecto.Adapters.SQLite3.
        To migrate another database, implement the FormFlow.Data.Migration
        behaviour and configure it:

            config :form_flow, migrator: MyApp.FormFlowMigrator
        """
    end
  end

  defp repo(opts) do
    cond do
      repo = Map.get(opts, :repo) -> repo
      in_migration?() -> repo()
      repo = DataRepo.repo() -> repo
      true -> raise ArgumentError, no_repo_message()
    end
  end

  defp prefix(opts) do
    case Map.get(opts, :prefix, migration_prefix()) do
      nil ->
        nil

      prefix when is_atom(prefix) ->
        prefix |> to_string() |> validate_prefix!()

      prefix when is_binary(prefix) ->
        validate_prefix!(prefix)
    end
  end

  defp migration_prefix do
    if in_migration?(), do: prefix()
  end

  defp validate_prefix!(prefix) do
    if Regex.match?(~r/^[a-zA-Z_][a-zA-Z0-9_]*$/, prefix) do
      prefix
    else
      raise ArgumentError,
            "expected :prefix to be a valid unquoted identifier, got: #{inspect(prefix)}"
    end
  end

  defp version(opts, migrator, direction) do
    default =
      case direction do
        :up -> migrator.current_version()
        :down -> migrator.initial_version()
        :current -> migrator.current_version()
      end

    version = Map.get(opts, :version, default)
    range = migrator.initial_version()..migrator.current_version()

    if version in range do
      version
    else
      raise ArgumentError,
            "expected :version to be between #{inspect(range)}, got: #{inspect(version)}"
    end
  end

  # Ecto stores the migration runner in the process dictionary, so this is how
  # we tell "called from inside a migration" from "called from application code"
  defp in_migration?, do: is_map(Process.get(:ecto_migration))

  defp no_repo_message do
    """
    FormFlow could not determine which repo to migrate.

    When calling outside of a migration, pass one explicitly:

        FormFlow.Data.Migration.migrated_version(repo: MyApp.Repo)

    or configure it once:

        config :form_flow, repo: MyApp.Repo
    """
  end
end
