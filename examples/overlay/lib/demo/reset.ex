defmodule Demo.Reset do
  @moduledoc """
  Puts the demo back to the data it ships with: empties every FormFlow table
  and replays `Demo.Snapshot`.

  The demo's database now lives on a Fly volume, so a deploy no longer discards
  what visitors leave behind, and the snapshot migration skips a database that
  already has flows. This is what reverts it instead.

  ## Why the tables are emptied rather than the database recreated

  SQLite would allow the stronger thing — the file is the database, and the
  connection pool is the only thing holding it — but recreating it means
  stopping the repo, deleting the file, starting the repo, and migrating, which
  drops every in-flight query and takes down anyone mid-form. Emptying the
  tables in one transaction leaves the pool alone and is the faster of the two
  by an order of magnitude.

  What it cannot do is repair the schema: it restores rows, not tables. A
  database whose structure is wrong still wants the migrations re-run.

  Deleting the database file out from under a live pool, incidentally, is the
  one thing never to do here. POSIX keeps the unlinked file alive for whoever
  holds it open, so the running pool keeps writing to a database that no longer
  has a name while every new connection opens an empty one, with no error on
  either side.
  """

  require Logger

  alias Demo.Repo
  alias Demo.Snapshot

  # Which FormFlow schema version is installed. That describes the tables
  # rather than the demo's data, and the snapshot does not carry it, so a
  # reset leaves the row where it is.
  @schema_version_table "form_flow_database_migrations"

  @doc """
  Empties FormFlow's tables and reloads the snapshot, in one transaction.

  Returns `{:ok, %{deleted: integer, loaded: integer}}` — rows cleared, and
  rows put back.
  """
  def run do
    {:ok, counts} =
      Repo.transaction(fn ->
        # Checked at commit instead of per statement, so the tables can be
        # emptied and refilled in any order. The snapshot is dumped
        # parent-first, which makes this a formality — but a flow can be
        # copied from one built after it, and then it is not.
        Repo.query!("PRAGMA defer_foreign_keys = ON", [], log: false)

        # Forms go before flows: a form's owner_flow_id nilifies when its
        # flow is deleted, which turns an owned form into a catalog form
        # for the rest of the statement - and catalog forms are unique by
        # name, so two owned "Details" forms collide. Deferring foreign
        # keys does not defer that unique check.
        deleted =
          tables()
          |> Enum.reject(&(&1 == @schema_version_table))
          |> Enum.sort_by(&(&1 != "form_flow_template_forms"))
          |> Enum.map(&Repo.query!("DELETE FROM #{&1}", [], log: false).num_rows)
          |> Enum.sum()

        statements = Snapshot.statements()
        Enum.each(statements, &Repo.query!(&1, [], log: false))

        %{deleted: deleted, loaded: length(statements)}
      end)

    Logger.info("Demo reset: cleared #{counts.deleted} rows, loaded #{counts.loaded}")

    {:ok, counts}
  end

  @doc """
  Every FormFlow table in the database, asked of the database rather than
  listed here — a table added by a later version of the library is emptied
  without this module hearing about it.
  """
  def tables do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT name FROM sqlite_master
        WHERE type = 'table' AND name LIKE 'form\\_flow\\_%' ESCAPE '\\'
        ORDER BY name
        """,
        [],
        log: false
      )

    List.flatten(rows)
  end
end
