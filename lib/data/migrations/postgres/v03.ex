defmodule FormFlow.Data.Migrations.Postgres.V03 do
  @moduledoc false

  # Subflows: a node can embed another graph, and graphs can be owned.
  #
  #   * `nodes.subflow_id` — the reference: this node embeds that graph.
  #     NULL on form nodes. `on_delete: :nothing` on purpose: deletion
  #     protection lives in FormFlow.Data.Graphs, where it can refuse with a
  #     friendly error and where delete ordering is explicit — RESTRICT would
  #     race the ownership cascade inside a single statement.
  #   * `graphs.owner_graph_id` — the ownership: which root's private property
  #     this graph is. NULL = nobody owns it (a root flow or a reusable
  #     subflow). Points at the ownership root, not the immediate parent, so
  #     one domain is one indexed cascade.
  #   * `graphs.made_reusable_at` — catalog membership, stamped by
  #     FormFlow.Data.Graphs.make_reusable/1. Partial index so listing the
  #     library stays a real-time query.
  #
  # The SQLite version of this file is intentionally a near-copy — see V01.

  use Ecto.Migration

  def up(context) do
    alter table(:form_flow_graphs, prefix: context.prefix) do
      add_if_not_exists(
        :owner_graph_id,
        references(:form_flow_graphs, type: :uuid, on_delete: :delete_all, prefix: context.prefix)
      )

      add_if_not_exists(:made_reusable_at, :utc_datetime_usec)
    end

    create_if_not_exists(index(:form_flow_graphs, [:owner_graph_id], prefix: context.prefix))

    create_if_not_exists(
      index(:form_flow_graphs, [:made_reusable_at],
        where: "made_reusable_at IS NOT NULL",
        prefix: context.prefix
      )
    )

    alter table(:form_flow_graph_nodes, prefix: context.prefix) do
      add_if_not_exists(
        :subflow_id,
        references(:form_flow_graphs, type: :uuid, on_delete: :nothing, prefix: context.prefix)
      )
    end

    create_if_not_exists(index(:form_flow_graph_nodes, [:subflow_id], prefix: context.prefix))
  end

  def down(context) do
    drop_if_exists(index(:form_flow_graph_nodes, [:subflow_id], prefix: context.prefix))

    alter table(:form_flow_graph_nodes, prefix: context.prefix) do
      remove(:subflow_id)
    end

    drop_if_exists(index(:form_flow_graphs, [:made_reusable_at], prefix: context.prefix))
    drop_if_exists(index(:form_flow_graphs, [:owner_graph_id], prefix: context.prefix))

    alter table(:form_flow_graphs, prefix: context.prefix) do
      remove(:made_reusable_at)
      remove(:owner_graph_id)
    end
  end
end
