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

    create_if_not_exists table(:form_flow_template_forms, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:app, :string, null: false, default: "default")
      add(:name, :string, null: false)
      add(:description, :text)
      add(:owner_graph_id, references(:form_flow_graphs, type: :uuid, on_delete: :nilify_all))

      add(
        :copied_from_form_id,
        references(:form_flow_template_forms, type: :uuid, on_delete: :nilify_all)
      )

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists(
      unique_index(:form_flow_template_forms, [:app, :name], where: "owner_graph_id IS NULL")
    )

    create_if_not_exists(index(:form_flow_template_forms, [:app]))
    create_if_not_exists(index(:form_flow_template_forms, [:owner_graph_id]))

    create_if_not_exists table(:form_flow_template_form_versions, primary_key: false) do
      add(:id, :uuid, primary_key: true)

      add(
        :template_form_id,
        references(:form_flow_template_forms, type: :uuid, on_delete: :restrict),
        null: false
      )

      add(:status, :string, null: false, default: "draft")
      add(:version, :integer)

      add(
        :based_on_version_id,
        references(:form_flow_template_form_versions, type: :uuid, on_delete: :nilify_all)
      )

      add(:lock_version, :integer, null: false, default: 1)
      add(:definition, :map, null: false)
      add(:published_at, :utc_datetime_usec)

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists(
      unique_index(:form_flow_template_form_versions, [:template_form_id, :version])
    )

    create_if_not_exists(index(:form_flow_template_form_versions, [:template_form_id, :status]))

    create_if_not_exists table(:form_flow_instance_forms, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:app, :string, null: false, default: "default")

      add(
        :template_form_version_id,
        references(:form_flow_template_form_versions, type: :uuid, on_delete: :restrict),
        null: false
      )

      add(:status, :string, null: false, default: "in_progress")
      add(:data, :map, null: false)
      add(:labels_snapshot, :map, null: false)
      add(:subject, :string)
      add(:metadata, :map, null: false)
      add(:completed_at, :utc_datetime_usec)

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists(index(:form_flow_instance_forms, [:template_form_version_id]))
    create_if_not_exists(index(:form_flow_instance_forms, [:app, :status]))
    create_if_not_exists(index(:form_flow_instance_forms, [:subject]))

    create_if_not_exists table(:form_flow_instance_form_events, primary_key: false) do
      add(:id, :uuid, primary_key: true)

      add(
        :instance_form_id,
        references(:form_flow_instance_forms, type: :uuid, on_delete: :restrict),
        null: false
      )

      add(:event, :string, null: false)

      add(
        :from_version_id,
        references(:form_flow_template_form_versions, type: :uuid, on_delete: :restrict)
      )

      add(
        :to_version_id,
        references(:form_flow_template_form_versions, type: :uuid, on_delete: :restrict)
      )

      add(:data_snapshot, :map, null: false)
      add(:actor, :string)

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists(index(:form_flow_instance_form_events, [:instance_form_id]))

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
      add(:form_id, references(:form_flow_template_forms, type: :uuid, on_delete: :nothing))

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists(index(:form_flow_graph_nodes, [:graph_id]))
    create_if_not_exists(index(:form_flow_graph_nodes, [:subflow_id]))
    create_if_not_exists(index(:form_flow_graph_nodes, [:form_id]))

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
    drop_if_exists(table(:form_flow_instance_form_events))
    drop_if_exists(table(:form_flow_instance_forms))
    drop_if_exists(table(:form_flow_template_form_versions))
    drop_if_exists(table(:form_flow_template_forms))
    drop_if_exists(table(:form_flow_graphs))
  end
end
