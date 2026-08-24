defmodule FormFlow.Data.Migrations.SQLite.V04 do
  @moduledoc false

  # Names and declared flavor for SQLite. See
  # FormFlow.Data.Migrations.Postgres.V04 for what the columns mean — the DDL
  # is deliberately duplicated rather than shared so each adapter can diverge.
  #
  # Plain `add` because ecto_sqlite3 does not support `add_if_not_exists` —
  # safe, the form_flow_migrations version table guarantees each version runs
  # at most once. NOT NULL with a default is allowed in SQLite's ALTER TABLE.

  use Ecto.Migration

  def up(_context) do
    alter table(:form_flow_graphs) do
      add(:name, :string)
      add(:label, :string, null: false, default: "forms")
    end
  end

  def down(_context) do
    alter table(:form_flow_graphs) do
      remove(:label)
      remove(:name)
    end
  end
end
