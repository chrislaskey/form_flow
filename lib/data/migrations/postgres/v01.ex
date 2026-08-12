defmodule FormFlow.Data.Migrations.Postgres.V01 do
  @moduledoc false

  # The initial schema: a form template, and an instance of a user filling one
  # out. Mirrors FormFlow.Data.Templates.Form and FormFlow.Data.Instances.Form.
  #
  # The SQLite version of this file is intentionally a near-copy rather than a
  # shared module, so each adapter's DDL stays readable in one place and is free
  # to diverge as the schema grows.

  use Ecto.Migration

  def up(context) do
    create_if_not_exists table(:form_flow_template_forms, prefix: context.prefix) do
      add(:app, :string, null: false, default: "default")
      add(:name, :string, null: false)
      add(:description, :text)
      add(:definition, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists(
      unique_index(:form_flow_template_forms, [:app, :name], prefix: context.prefix)
    )

    create_if_not_exists table(:form_flow_instance_forms, prefix: context.prefix) do
      add(:app, :string, null: false, default: "default")

      add(
        :template_form_id,
        references(:form_flow_template_forms, on_delete: :restrict, prefix: context.prefix),
        null: false
      )

      add(:state, :string, null: false, default: "in_progress")
      add(:data, :map, null: false, default: %{})
      add(:completed_at, :utc_datetime_usec)

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists(
      index(:form_flow_instance_forms, [:template_form_id], prefix: context.prefix)
    )

    create_if_not_exists(index(:form_flow_instance_forms, [:app, :state], prefix: context.prefix))
  end

  def down(context) do
    drop_if_exists(table(:form_flow_instance_forms, prefix: context.prefix))
    drop_if_exists(table(:form_flow_template_forms, prefix: context.prefix))
  end
end
