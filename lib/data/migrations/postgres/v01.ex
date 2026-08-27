defmodule FormFlow.Data.Migrations.Postgres.V01 do
  @moduledoc false

  # The initial schema, in two parts:
  #
  # Forms — a form template split into an identity (the lineage) and its
  # definitions (versions), plus an instance of a user filling one out.
  # Mirrors FormFlow.Data.Templates.Form, FormFlow.Data.Templates.Form.Version,
  # and FormFlow.Data.Instances.Form. Published versions are immutable; every
  # definition — draft or published — is a version row, and instances pin the
  # exact version they were filled against (see archive/form-versioning.md).
  #
  # Flows — a property graph in the Neo4j style, stored relationally. Nodes
  # carry labels (a set) and properties; relationships carry a single label
  # and properties. `flow_id` is a real column so the database can enforce
  # membership and cascade deletes; the schemas also keep a copy of it inside
  # properties, the location that carries over to Neo4j.
  #
  # Flows are created first: `template_forms.owner_flow_id` references them.
  #
  # Deleting a node deletes its relationships (Neo4j's DETACH DELETE as the
  # only mode): `:restrict` would push deletion ordering onto every caller, and
  # for a diagram editor detach-delete is what the UI means.
  #
  # Columns worth explaining:
  #
  #   * `template_forms.owner_flow_id` — the ownership, mirroring
  #     `flows.owner_flow_id`: which root flow's private property this form
  #     is. NULL = a reusable catalog form, listed in /forms. `:nilify_all`
  #     because cleanup of owned forms is explicit context code (deleting a
  #     flow deletes its owned forms deliberately — a nilified owner must never
  #     silently become a catalog entry).
  #   * `template_forms.copied_from_form_id` — provenance: which lineage this
  #     one was copied from (yearly rollover), for cross-cycle identity and
  #     future prefill.
  #   * The `(name)` unique index is scoped to the catalog
  #     (`owner_flow_id IS NULL`) — one namespace: owned forms may repeat
  #     names across yearly copies; catalog forms stay unambiguous in every
  #     picker.
  #   * `template_form_versions.version` — NULL until publish. The plain
  #     unique index works because multiple NULLs never collide, so published
  #     versions get uniqueness with no partial-index or CHECK logic. Status
  #     values (draft | published | archived) are enforced in the changeset,
  #     not the database.
  #   * `instance_forms.template_form_version_id` — the pin: the exact
  #     definition this instance renders against. There is deliberately no
  #     lineage column beside it — the lineage is derived through the pin, and
  #     a stored copy would need a desync guard. `:restrict` so answer sets
  #     can never be orphaned or cascade-deleted by template changes.
  #   * `instance_form_events` — append-only audit: pin migrations, reopens,
  #     status changes, with prior data snapshotted when a migration discards
  #     it. `:restrict` from events to instances: deleting an instance goes
  #     through an explicit delete API that removes events deliberately.
  #   * `instance_flows` — one traversal of a root flow (a journey). The root
  #     is referenced live — no flow versioning, edits propagate to journeys
  #     in flight — and `:restrict`ed: journeys can never be orphaned by
  #     template deletion. `user_id` is the creating user, stamped and
  #     immutable. Traversal state is never stored; it is derived
  #     (FormFlow.Data.Instances.Progress).
  #   * `instance_forms.instance_flow_id` + `path` — the visit identity of an
  #     in-journey form instance: the chain of node ids from the root flow
  #     through each embedding subflow node to the form node itself.
  #     NULL/empty = a standalone fill. Deliberately no node FK: editor saves
  #     replace all nodes (clear_contents), so any FK action would fire on
  #     every routine save — and a node column would be a derivable copy of
  #     last(path).
  #   * `instance_forms.superseded_at` — stamped by strand reconciliation on
  #     the old instance when its successor is created; derivation skips
  #     superseded rows. The unique index is scoped to active rows: one
  #     *active* form instance per visit, while superseded rows remain as
  #     attestation records that never block a revived path.
  #   * `instance_flow_events` — the journey's append-only audit, mirroring
  #     `instance_form_events` discipline (`:restrict`, explicit deletes).
  #   * `nodes.subflow_id` — the reference: this node embeds that flow. NULL
  #     on form nodes. `on_delete: :nothing` on purpose: deletion protection
  #     lives in FormFlow.Data.Templates.Flows, where it can refuse with a friendly
  #     error and where delete ordering is explicit — RESTRICT would race the
  #     ownership cascade inside a single statement.
  #   * `nodes.form_id` — the form-node counterpart of `subflow_id`: this node
  #     collects that form (the lineage, never a version — version resolution
  #     is a read-time and instance-pin concern). Same `:nothing` rationale.
  #
  # The SQLite version of this file is intentionally a near-copy rather than a
  # shared module, so each adapter's DDL stays readable in one place and is free
  # to diverge as the schema grows.

  use Ecto.Migration

  def up(context) do
    create_if_not_exists table(:form_flow_flows, primary_key: false, prefix: context.prefix) do
      add(:id, :uuid, primary_key: true)
      add(:name, :string)
      add(:label, :string, null: false, default: "forms")
      add(:properties, :map, null: false, default: %{})

      add(
        :owner_flow_id,
        references(:form_flow_flows, type: :uuid, on_delete: :delete_all, prefix: context.prefix)
      )

      add(:made_reusable_at, :utc_datetime_usec)

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists(index(:form_flow_flows, [:owner_flow_id], prefix: context.prefix))

    create_if_not_exists(
      index(:form_flow_flows, [:made_reusable_at],
        where: "made_reusable_at IS NOT NULL",
        prefix: context.prefix
      )
    )

    create_if_not_exists table(:form_flow_template_forms,
                           primary_key: false,
                           prefix: context.prefix
                         ) do
      add(:id, :uuid, primary_key: true)
      add(:name, :string, null: false)
      add(:description, :text)

      add(
        :owner_flow_id,
        references(:form_flow_flows, type: :uuid, on_delete: :nilify_all, prefix: context.prefix)
      )

      add(
        :copied_from_form_id,
        references(:form_flow_template_forms,
          type: :uuid,
          on_delete: :nilify_all,
          prefix: context.prefix
        )
      )

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists(
      unique_index(:form_flow_template_forms, [:name],
        where: "owner_flow_id IS NULL",
        prefix: context.prefix
      )
    )

    create_if_not_exists(
      index(:form_flow_template_forms, [:owner_flow_id], prefix: context.prefix)
    )

    create_if_not_exists table(:form_flow_template_form_versions,
                           primary_key: false,
                           prefix: context.prefix
                         ) do
      add(:id, :uuid, primary_key: true)

      add(
        :template_form_id,
        references(:form_flow_template_forms,
          type: :uuid,
          on_delete: :restrict,
          prefix: context.prefix
        ),
        null: false
      )

      add(:status, :string, null: false, default: "draft")
      add(:version, :integer)

      add(
        :based_on_version_id,
        references(:form_flow_template_form_versions,
          type: :uuid,
          on_delete: :nilify_all,
          prefix: context.prefix
        )
      )

      add(:lock_version, :integer, null: false, default: 1)
      add(:definition, :map, null: false, default: %{})
      add(:published_at, :utc_datetime_usec)

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists(
      unique_index(:form_flow_template_form_versions, [:template_form_id, :version],
        prefix: context.prefix
      )
    )

    create_if_not_exists(
      index(:form_flow_template_form_versions, [:template_form_id, :status],
        prefix: context.prefix
      )
    )

    create_if_not_exists table(:form_flow_instance_flows,
                           primary_key: false,
                           prefix: context.prefix
                         ) do
      add(:id, :uuid, primary_key: true)

      add(
        :flow_id,
        references(:form_flow_flows, type: :uuid, on_delete: :restrict, prefix: context.prefix),
        null: false
      )

      add(:status, :string, null: false, default: "in_progress")
      add(:user_id, :string)
      add(:metadata, :map, null: false, default: %{})
      add(:completed_at, :utc_datetime_usec)

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists(index(:form_flow_instance_flows, [:flow_id], prefix: context.prefix))
    create_if_not_exists(index(:form_flow_instance_flows, [:status], prefix: context.prefix))

    create_if_not_exists table(:form_flow_instance_forms,
                           primary_key: false,
                           prefix: context.prefix
                         ) do
      add(:id, :uuid, primary_key: true)

      add(
        :template_form_version_id,
        references(:form_flow_template_form_versions,
          type: :uuid,
          on_delete: :restrict,
          prefix: context.prefix
        ),
        null: false
      )

      add(:status, :string, null: false, default: "in_progress")
      add(:lock_version, :integer, null: false, default: 1)
      add(:data, :map, null: false, default: %{})
      add(:metadata, :map, null: false, default: %{})
      add(:completed_at, :utc_datetime_usec)

      add(
        :instance_flow_id,
        references(:form_flow_instance_flows,
          type: :uuid,
          on_delete: :restrict,
          prefix: context.prefix
        )
      )

      add(:path, {:array, :text}, null: false, default: [])
      add(:superseded_at, :utc_datetime_usec)

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists(
      index(:form_flow_instance_forms, [:template_form_version_id], prefix: context.prefix)
    )

    create_if_not_exists(
      index(:form_flow_instance_forms, [:instance_flow_id], prefix: context.prefix)
    )

    # One *active* form instance per visit — superseded rows stay as
    # attestation records without blocking a revived path from being filled
    create_if_not_exists(
      unique_index(:form_flow_instance_forms, [:instance_flow_id, :path],
        where: "instance_flow_id IS NOT NULL AND superseded_at IS NULL",
        prefix: context.prefix
      )
    )

    create_if_not_exists(index(:form_flow_instance_forms, [:status], prefix: context.prefix))

    create_if_not_exists table(:form_flow_instance_form_events,
                           primary_key: false,
                           prefix: context.prefix
                         ) do
      add(:id, :uuid, primary_key: true)

      add(
        :instance_form_id,
        references(:form_flow_instance_forms,
          type: :uuid,
          on_delete: :restrict,
          prefix: context.prefix
        ),
        null: false
      )

      add(:event, :string, null: false)

      add(
        :from_version_id,
        references(:form_flow_template_form_versions,
          type: :uuid,
          on_delete: :restrict,
          prefix: context.prefix
        )
      )

      add(
        :to_version_id,
        references(:form_flow_template_form_versions,
          type: :uuid,
          on_delete: :restrict,
          prefix: context.prefix
        )
      )

      add(:data_snapshot, :map, null: false, default: %{})
      add(:user_id, :string)

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists(
      index(:form_flow_instance_form_events, [:instance_form_id], prefix: context.prefix)
    )

    create_if_not_exists table(:form_flow_instance_flow_events,
                           primary_key: false,
                           prefix: context.prefix
                         ) do
      add(:id, :uuid, primary_key: true)

      add(
        :instance_flow_id,
        references(:form_flow_instance_flows,
          type: :uuid,
          on_delete: :restrict,
          prefix: context.prefix
        ),
        null: false
      )

      add(:event, :string, null: false)
      add(:snapshot, :map, null: false, default: %{})
      add(:user_id, :string)

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists(
      index(:form_flow_instance_flow_events, [:instance_flow_id], prefix: context.prefix)
    )

    create_if_not_exists table(:form_flow_nodes,
                           primary_key: false,
                           prefix: context.prefix
                         ) do
      add(:id, :uuid, primary_key: true)

      add(
        :flow_id,
        references(:form_flow_flows,
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
        references(:form_flow_flows, type: :uuid, on_delete: :nothing, prefix: context.prefix)
      )

      add(
        :form_id,
        references(:form_flow_template_forms,
          type: :uuid,
          on_delete: :nothing,
          prefix: context.prefix
        )
      )

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists(index(:form_flow_nodes, [:flow_id], prefix: context.prefix))

    create_if_not_exists(index(:form_flow_nodes, [:subflow_id], prefix: context.prefix))

    create_if_not_exists(index(:form_flow_nodes, [:form_id], prefix: context.prefix))

    # Label and property lookups use GIN: labels via array containment (@>),
    # properties via jsonb_path_ops, which serves @> containment queries only
    create_if_not_exists(index(:form_flow_nodes, [:labels], using: "GIN", prefix: context.prefix))

    create_if_not_exists(
      index(:form_flow_nodes, ["properties jsonb_path_ops"],
        using: "GIN",
        name: :form_flow_nodes_properties_index,
        prefix: context.prefix
      )
    )

    create_if_not_exists table(:form_flow_relationships,
                           primary_key: false,
                           prefix: context.prefix
                         ) do
      add(:id, :uuid, primary_key: true)

      add(
        :flow_id,
        references(:form_flow_flows,
          type: :uuid,
          on_delete: :delete_all,
          prefix: context.prefix
        ),
        null: false
      )

      add(
        :source_id,
        references(:form_flow_nodes,
          type: :uuid,
          on_delete: :delete_all,
          prefix: context.prefix
        ),
        null: false
      )

      add(
        :target_id,
        references(:form_flow_nodes,
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
      unique_index(:form_flow_relationships, [:source_id, :target_id, :label],
        prefix: context.prefix
      )
    )

    # Inbound traversal ("what points at N?") — the reverse direction the
    # unique index above can't serve
    create_if_not_exists(
      index(:form_flow_relationships, [:target_id, :label], prefix: context.prefix)
    )

    create_if_not_exists(index(:form_flow_relationships, [:flow_id], prefix: context.prefix))
  end

  def down(context) do
    drop_if_exists(table(:form_flow_relationships, prefix: context.prefix))
    drop_if_exists(table(:form_flow_nodes, prefix: context.prefix))
    drop_if_exists(table(:form_flow_instance_flow_events, prefix: context.prefix))
    drop_if_exists(table(:form_flow_instance_form_events, prefix: context.prefix))
    drop_if_exists(table(:form_flow_instance_forms, prefix: context.prefix))
    drop_if_exists(table(:form_flow_instance_flows, prefix: context.prefix))
    drop_if_exists(table(:form_flow_template_form_versions, prefix: context.prefix))
    drop_if_exists(table(:form_flow_template_forms, prefix: context.prefix))
    drop_if_exists(table(:form_flow_flows, prefix: context.prefix))
  end
end
