defmodule FormFlow.Data.Migrations.SQLite.V01 do
  @moduledoc false

  # The initial schema for SQLite. See FormFlow.Data.Migrations.Postgres.V01 —
  # the DDL is deliberately duplicated rather than shared so each adapter can
  # diverge as the schema grows.
  #
  # SQLite has no schemas, so `context.prefix` is ignored.

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
  end

  def down(_context) do
    drop_if_exists(table(:form_flow_instance_forms))
    drop_if_exists(table(:form_flow_template_forms))
  end
end
