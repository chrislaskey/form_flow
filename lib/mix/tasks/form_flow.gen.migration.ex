defmodule Mix.Tasks.FormFlow.Gen.Migration do
  @shortdoc "Generates a migration that installs FormFlow's tables"

  @moduledoc """
  Generates an Ecto migration that creates FormFlow's tables in your app's
  database.

      mix form_flow.gen.migration

  The generated migration calls `FormFlow.Data.Migration.up/1` with the version
  pinned, so it keeps doing what it did when it was written. Upgrading FormFlow
  means running this task again to generate a migration for the newer version.

  ## Options

    * `-r`, `--repo` - the repo to generate the migration for. Defaults to the
      app's first configured repo.

    * `--migrations-path` - where to write the migration. Defaults to the repo's
      `priv/*/migrations` directory.

    * `--version` - the FormFlow schema version to pin. Defaults to the latest
      version the installed FormFlow supports.
  """

  use Mix.Task

  import Mix.Generator

  alias FormFlow.Data.Migration
  alias Mix.EctoSQL

  @switches [repo: [:string, :keep], migrations_path: :string, version: :integer]
  @aliases [r: :repo]

  @impl Mix.Task
  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)

    repo = repo(args)
    version = opts[:version] || Migration.current_version(repo: repo)
    path = opts[:migrations_path] || Path.join(EctoSQL.source_repo_priv(repo), "migrations")
    file = Path.join(path, "#{timestamp()}_add_form_flow.exs")

    create_directory(path)

    create_file(file, """
    defmodule #{inspect(Module.concat(repo, Migrations.AddFormFlow))} do
      use Ecto.Migration

      def up, do: FormFlow.Data.Migration.up(version: #{version})

      # Rolling back removes FormFlow's tables, and the data in them
      def down, do: FormFlow.Data.Migration.down(version: #{version})
    end
    """)

    Mix.shell().info("""

    Run it with:

        mix ecto.migrate
    """)
  end

  defp repo(args) do
    case Mix.Ecto.parse_repo(args) do
      [repo | _] ->
        Mix.Ecto.ensure_repo(repo, args)

      [] ->
        Mix.raise("""
        No repo found. Configure one for your app:

            config :my_app, ecto_repos: [MyApp.Repo]

        or pass it explicitly:

            mix form_flow.gen.migration -r MyApp.Repo
        """)
    end
  end

  # Matches mix ecto.gen.migration's naming so migrations sort chronologically
  defp timestamp do
    %{year: y, month: m, day: d, hour: hh, minute: mm, second: ss} = DateTime.utc_now()

    "#{y}#{pad(m)}#{pad(d)}#{pad(hh)}#{pad(mm)}#{pad(ss)}"
  end

  defp pad(int), do: int |> to_string() |> String.pad_leading(2, "0")
end
