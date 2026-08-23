defmodule FormFlow.Data.Migrations.SQLite.V03 do
  @moduledoc false

  # Subflows for SQLite. See FormFlow.Data.Migrations.Postgres.V03 for what the
  # columns mean — the DDL is deliberately duplicated rather than shared so
  # each adapter can diverge as the schema grows.
  #
  # SQLite has no schemas, so `context.prefix` is ignored. Partial indexes and
  # adding a nullable column with a foreign key via ALTER TABLE are supported.
  # `add_if_not_exists` is NOT (ecto_sqlite3 raises), hence plain `add` — safe
  # because the form_flow_migrations version table already guarantees each
  # version runs at most once.

  use Ecto.Migration

  def up(_context) do
    alter table(:form_flow_graphs) do
      add(:owner_graph_id, references(:form_flow_graphs, type: :uuid, on_delete: :delete_all))
      add(:made_reusable_at, :utc_datetime_usec)
    end

    create_if_not_exists(index(:form_flow_graphs, [:owner_graph_id]))

    create_if_not_exists(
      index(:form_flow_graphs, [:made_reusable_at], where: "made_reusable_at IS NOT NULL")
    )

    alter table(:form_flow_graph_nodes) do
      add(:subflow_id, references(:form_flow_graphs, type: :uuid, on_delete: :nothing))
    end

    create_if_not_exists(index(:form_flow_graph_nodes, [:subflow_id]))
  end

  def down(_context) do
    drop_if_exists(index(:form_flow_graph_nodes, [:subflow_id]))

    alter table(:form_flow_graph_nodes) do
      remove(:subflow_id)
    end

    drop_if_exists(index(:form_flow_graphs, [:made_reusable_at]))
    drop_if_exists(index(:form_flow_graphs, [:owner_graph_id]))

    alter table(:form_flow_graphs) do
      remove(:made_reusable_at)
      remove(:owner_graph_id)
    end
  end
end
