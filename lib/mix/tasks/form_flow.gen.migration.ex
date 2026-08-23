defmodule Mix.Tasks.FormFlow.Gen.Migration do
  @shortdoc "Generates a migration that installs FormFlow's tables"

  @moduledoc """
  Generates an Ecto migration that creates FormFlow's tables in your app's
  database.

      mix form_flow.gen.migration

  The generated migration calls `FormFlow.Data.Migration.up/1` with the version
  pinned, so it keeps doing what it did when it was written. Upgrading FormFlow
  means running this task again: it finds the version your existing migration
  pinned and generates a second migration that applies only the versions in
  between — and whose rollback returns to the old version rather than removing
  FormFlow entirely.

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
    pinned = highest_pinned_version(path)

    cond do
      pinned >= version ->
        Mix.shell().info("""
        A migration in #{path} already pins FormFlow version #{pinned} — nothing to generate.
        """)

      pinned == 0 ->
        # First install: rolling back removes FormFlow entirely
        generate(path, repo, "AddFormFlow", "add_form_flow", version, 1)

      true ->
        # Upgrade: rolling back returns to the previously pinned version
        generate(
          path,
          repo,
          "AddFormFlowV#{version}",
          "add_form_flow_v#{version}",
          version,
          pinned + 1
        )
    end
  end

  defp generate(path, repo, module, name, up_version, down_version) do
    file = Path.join(path, "#{timestamp()}_#{name}.exs")

    down_comment =
      if down_version == 1 do
        "# Rolling back removes FormFlow's tables, and the data in them"
      else
        "# Rolling back returns FormFlow to schema version #{down_version - 1}"
      end

    create_directory(path)

    create_file(file, """
    defmodule #{inspect(Module.concat([repo, "Migrations", module]))} do
      use Ecto.Migration

      def up, do: FormFlow.Data.Migration.up(version: #{up_version})

      #{down_comment}
      def down, do: FormFlow.Data.Migration.down(version: #{down_version})
    end
    """)

    Mix.shell().info("""

    Run it with:

        mix ecto.migrate
    """)
  end

  # The version an earlier run of this task pinned, or 0 when there is none.
  # Read from the migration files themselves — the database may not exist yet.
  defp highest_pinned_version(path) do
    path
    |> Path.join("*.exs")
    |> Path.wildcard()
    |> Enum.flat_map(fn file ->
      ~r/FormFlow\.Data\.Migration\.up\(version: (\d+)\)/
      |> Regex.scan(File.read!(file))
      |> Enum.map(fn [_, version] -> String.to_integer(version) end)
    end)
    |> Enum.max(fn -> 0 end)
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
