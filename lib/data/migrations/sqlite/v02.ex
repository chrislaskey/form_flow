defmodule FormFlow.Data.Migrations.SQLite.V02 do
  @moduledoc false

  # The graph schema for SQLite. See FormFlow.Data.Migrations.Postgres.V02 —
  # the DDL is deliberately duplicated rather than shared so each adapter can
  # diverge as the schema grows.
  #
  # Differences from Postgres: no schemas so `context.prefix` is ignored, no
  # GIN indexes (labels and properties are stored as JSON text and scanned —
  # fine for the expected shape of loading one graph and working in memory),
  # and no column defaults for arrays/maps (the Ecto schemas default them).

  use Ecto.Migration

  def up(_context) do
    create_if_not_exists table(:form_flow_graphs, primary_key: false) do
      add(:id, :uuid, primary_key: true)

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists table(:form_flow_graph_nodes, primary_key: false) do
      add(:id, :uuid, primary_key: true)

      add(
        :graph_id,
        references(:form_flow_graphs, type: :uuid, on_delete: :delete_all),
        null: false
      )

      add(:labels, {:array, :string}, null: false)
      add(:properties, :map, null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists(index(:form_flow_graph_nodes, [:graph_id]))

    create_if_not_exists table(:form_flow_graph_relationships, primary_key: false) do
      add(:id, :uuid, primary_key: true)

      add(
        :graph_id,
        references(:form_flow_graphs, type: :uuid, on_delete: :delete_all),
        null: false
      )

      add(
        :source_id,
        references(:form_flow_graph_nodes, type: :uuid, on_delete: :delete_all),
        null: false
      )

      add(
        :target_id,
        references(:form_flow_graph_nodes, type: :uuid, on_delete: :delete_all),
        null: false
      )

      add(:label, :string, null: false)
      add(:properties, :map, null: false)

      timestamps(type: :utc_datetime_usec)
    end

    # Unique, so the same pair can't be linked twice with the same label; its
    # source_id prefix doubles as the outbound traversal index
    create_if_not_exists(
      unique_index(:form_flow_graph_relationships, [:source_id, :target_id, :label])
    )

    # Inbound traversal ("what points at N?")
    create_if_not_exists(index(:form_flow_graph_relationships, [:target_id, :label]))

    create_if_not_exists(index(:form_flow_graph_relationships, [:graph_id]))
  end

  def down(_context) do
    drop_if_exists(table(:form_flow_graph_relationships))
    drop_if_exists(table(:form_flow_graph_nodes))
    drop_if_exists(table(:form_flow_graphs))
  end
end
