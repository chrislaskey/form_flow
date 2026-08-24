defmodule FormFlow.Data.Migrations.SQLite.V01 do
  @moduledoc false

  # The initial schema for SQLite. See FormFlow.Data.Migrations.Postgres.V01
  # for what the tables and columns mean — the DDL is deliberately duplicated
  # rather than shared so each adapter can diverge as the schema grows.
  #
  # Differences from Postgres: no schemas so `context.prefix` is ignored, no
  # GIN indexes (labels and properties are stored as JSON text and scanned —
  # fine for the expected shape of loading one graph and working in memory),
  # and no column defaults for arrays/maps (the Ecto schemas default them).

  use Ecto.Migration

  def up(_context) do
    create_if_not_exists table(:form_flow_template_forms) do
      add(:app, :string, null: false, default: "default")
      add(:name, :string, null: false)
      add(:description, :text)
      add(:definition, :map, null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists(unique_index(:form_flow_template_forms, [:app, :name]))

    create_if_not_exists table(:form_flow_instance_forms) do
      add(:app, :string, null: false, default: "default")

      add(
        :template_form_id,
        references(:form_flow_template_forms, on_delete: :restrict),
        null: false
      )

      add(:state, :string, null: false, default: "in_progress")
      add(:data, :map, null: false)
      add(:completed_at, :utc_datetime_usec)

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists(index(:form_flow_instance_forms, [:template_form_id]))
    create_if_not_exists(index(:form_flow_instance_forms, [:app, :state]))

    create_if_not_exists table(:form_flow_graphs, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:name, :string)
      add(:label, :string, null: false, default: "forms")
      add(:owner_graph_id, references(:form_flow_graphs, type: :uuid, on_delete: :delete_all))
      add(:made_reusable_at, :utc_datetime_usec)

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists(index(:form_flow_graphs, [:owner_graph_id]))

    create_if_not_exists(
      index(:form_flow_graphs, [:made_reusable_at], where: "made_reusable_at IS NOT NULL")
    )

    create_if_not_exists table(:form_flow_graph_nodes, primary_key: false) do
      add(:id, :uuid, primary_key: true)

      add(
        :graph_id,
        references(:form_flow_graphs, type: :uuid, on_delete: :delete_all),
        null: false
      )

      add(:labels, {:array, :string}, null: false)
      add(:properties, :map, null: false)
      add(:subflow_id, references(:form_flow_graphs, type: :uuid, on_delete: :nothing))

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists(index(:form_flow_graph_nodes, [:graph_id]))
    create_if_not_exists(index(:form_flow_graph_nodes, [:subflow_id]))

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
    drop_if_exists(table(:form_flow_instance_forms))
    drop_if_exists(table(:form_flow_template_forms))
  end
end
