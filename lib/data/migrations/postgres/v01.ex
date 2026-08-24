defmodule FormFlow.Data.Migrations.Postgres.V01 do
  @moduledoc false

  # The initial schema, in two parts:
  #
  # Forms — a form template, and an instance of a user filling one out.
  # Mirrors FormFlow.Data.Templates.Form and FormFlow.Data.Instances.Form.
  #
  # Graphs — a property graph in the Neo4j style, stored relationally. Nodes
  # carry labels (a set) and properties; relationships carry a single label
  # and properties. `graph_id` is a real column so the database can enforce
  # membership and cascade deletes; the schemas also keep a copy of it inside
  # properties, the location that carries over to Neo4j.
  #
  # Deleting a node deletes its relationships (Neo4j's DETACH DELETE as the
  # only mode): `:restrict` would push deletion ordering onto every caller, and
  # for a diagram editor detach-delete is what the UI means.
  #
  # Columns worth explaining:
  #
  #   * `graphs.name` — the human name shown in listings, breadcrumbs, and the
  #     reusable catalog. Nullable; the UI falls back to "Untitled".
  #   * `graphs.label` — the graph's declared flavor: "forms" (contains form
  #     steps) or "subflows" (contains subflow steps), never mixed. Declared at
  #     creation and immutable after. Named `label` to mirror Neo4j, where it
  #     becomes the second label on the `:Graph` node (:Graph:Forms /
  #     :Graph:Subflows).
  #   * `graphs.owner_graph_id` — the ownership: which root's private property
  #     this graph is. NULL = nobody owns it (a root flow or a reusable
  #     subflow). Points at the ownership root, not the immediate parent, so
  #     one domain is one indexed cascade.
  #   * `graphs.made_reusable_at` — catalog membership, stamped by
  #     FormFlow.Data.Graphs.make_reusable/1. Partial index so listing the
  #     library stays a real-time query.
  #   * `nodes.subflow_id` — the reference: this node embeds that graph. NULL
  #     on form nodes. `on_delete: :nothing` on purpose: deletion protection
  #     lives in FormFlow.Data.Graphs, where it can refuse with a friendly
  #     error and where delete ordering is explicit — RESTRICT would race the
  #     ownership cascade inside a single statement.
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

    create_if_not_exists table(:form_flow_graphs, primary_key: false, prefix: context.prefix) do
      add(:id, :uuid, primary_key: true)
      add(:name, :string)
      add(:label, :string, null: false, default: "forms")

      add(
        :owner_graph_id,
        references(:form_flow_graphs, type: :uuid, on_delete: :delete_all, prefix: context.prefix)
      )

      add(:made_reusable_at, :utc_datetime_usec)

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists(index(:form_flow_graphs, [:owner_graph_id], prefix: context.prefix))

    create_if_not_exists(
      index(:form_flow_graphs, [:made_reusable_at],
        where: "made_reusable_at IS NOT NULL",
        prefix: context.prefix
      )
    )

    create_if_not_exists table(:form_flow_graph_nodes,
                           primary_key: false,
                           prefix: context.prefix
                         ) do
      add(:id, :uuid, primary_key: true)

      add(
        :graph_id,
        references(:form_flow_graphs,
          type: :uuid,
          on_delete: :delete_all,
          prefix: context.prefix
        ),
        null: false
      )

      add(:labels, {:array, :text}, null: false, default: [])
      add(:properties, :map, null: false, default: %{})

      add(
        :subflow_id,
        references(:form_flow_graphs, type: :uuid, on_delete: :nothing, prefix: context.prefix)
      )

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists(index(:form_flow_graph_nodes, [:graph_id], prefix: context.prefix))

    create_if_not_exists(index(:form_flow_graph_nodes, [:subflow_id], prefix: context.prefix))

    # Label and property lookups use GIN: labels via array containment (@>),
    # properties via jsonb_path_ops, which serves @> containment queries only
    create_if_not_exists(
      index(:form_flow_graph_nodes, [:labels], using: "GIN", prefix: context.prefix)
    )

    create_if_not_exists(
      index(:form_flow_graph_nodes, ["properties jsonb_path_ops"],
        using: "GIN",
        name: :form_flow_graph_nodes_properties_index,
        prefix: context.prefix
      )
    )

    create_if_not_exists table(:form_flow_graph_relationships,
                           primary_key: false,
                           prefix: context.prefix
                         ) do
      add(:id, :uuid, primary_key: true)

      add(
        :graph_id,
        references(:form_flow_graphs,
          type: :uuid,
          on_delete: :delete_all,
          prefix: context.prefix
        ),
        null: false
      )

      add(
        :source_id,
        references(:form_flow_graph_nodes,
          type: :uuid,
          on_delete: :delete_all,
          prefix: context.prefix
        ),
        null: false
      )

      add(
        :target_id,
        references(:form_flow_graph_nodes,
          type: :uuid,
          on_delete: :delete_all,
          prefix: context.prefix
        ),
        null: false
      )

      add(:label, :string, null: false)
      add(:properties, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    # Unique, so the same pair can't be linked twice with the same label — a
    # deliberate divergence from Neo4j, where parallel relationships are legal.
    # Its source_id prefix doubles as the outbound traversal index.
    create_if_not_exists(
      unique_index(:form_flow_graph_relationships, [:source_id, :target_id, :label],
        prefix: context.prefix
      )
    )

    # Inbound traversal ("what points at N?") — the reverse direction the
    # unique index above can't serve
    create_if_not_exists(
      index(:form_flow_graph_relationships, [:target_id, :label], prefix: context.prefix)
    )

    create_if_not_exists(
      index(:form_flow_graph_relationships, [:graph_id], prefix: context.prefix)
    )
  end

  def down(context) do
    drop_if_exists(table(:form_flow_graph_relationships, prefix: context.prefix))
    drop_if_exists(table(:form_flow_graph_nodes, prefix: context.prefix))
    drop_if_exists(table(:form_flow_graphs, prefix: context.prefix))
    drop_if_exists(table(:form_flow_instance_forms, prefix: context.prefix))
    drop_if_exists(table(:form_flow_template_forms, prefix: context.prefix))
  end
end
