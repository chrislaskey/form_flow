defmodule FormFlow.Data.Migrations.Postgres.V02 do
  @moduledoc false

  # The graph schema: a property graph in the Neo4j style, stored relationally.
  # Nodes carry labels (a set) and properties; relationships carry a single
  # label and properties. `graph_id` is a real column so the database can
  # enforce membership and cascade deletes; the schemas also keep a copy of it
  # inside properties, the location that carries over to Neo4j.
  #
  # Deleting a node deletes its relationships (Neo4j's DETACH DELETE as the
  # only mode): `:restrict` would push deletion ordering onto every caller, and
  # for a diagram editor detach-delete is what the UI means.
  #
  # The SQLite version of this file is intentionally a near-copy — see V01.

  use Ecto.Migration

  def up(context) do
    create_if_not_exists table(:form_flow_graphs, primary_key: false, prefix: context.prefix) do
      add(:id, :uuid, primary_key: true)

      timestamps(type: :utc_datetime_usec)
    end

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

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists(index(:form_flow_graph_nodes, [:graph_id], prefix: context.prefix))

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
  end
end
