defmodule DemoWeb.DocsLive.DataModelingLive.Diagram do
  @moduledoc """
  The schema diagram `DemoWeb.DocsLive.DataModelingLive` draws: one ReactFlow node per
  table FormFlow's migration creates, one edge per foreign key between them.

  Everything but the layout is read off FormFlow's Ecto schemas at runtime —
  `__schema__(:source)` for the table name, `__schema__(:fields)` for the
  columns in declaration order, and each `belongs_to` for the foreign keys —
  so the diagram cannot drift from the library the demo is compiled against.
  Adding a column to a schema adds a row here; adding a `belongs_to` adds an
  edge.

  Three things the Ecto schemas cannot say, and where they come from instead:

    * **Postgres column types.** An Ecto field type is not a column type, so
      `@postgres_types` names what `Ecto.Adapters.Postgres` turns each one
      into, and `@migration_types` overrides the three columns where
      `FormFlow.Data.Migrations.Postgres.V01` declares a wider type than the
      schema's field implies. The demo itself runs SQLite; the types drawn
      here are the ones a Postgres host gets.
    * **`ON DELETE` behaviour.** It lives on the migration's `references`, not
      on `belongs_to`, so `@on_delete_rules` records it per column. It is the
      most load-bearing thing about this schema — see the long comment at the
      top of `FormFlow.Data.Migrations.Postgres.V01` — which is why the page
      names it against every foreign key it lists.
    * **Position.** ReactFlow has no layout of its own, so `@tables` places
      each one by hand, right to left in dependency order.
    * **Which tables matter most.** `@primary` names the five the page stars;
      nothing in the schema says one table is more central than another.
  """

  alias FormFlow.Data.Instances
  alias FormFlow.Data.Templates

  # Three columns, right to left in dependency order: `form_flow_template_flows`,
  # which nearly everything references, heads the right-hand column, the graph
  # of a flow's nodes is the middle one, and forms are on the left. Templates
  # fill the top band and the instances of them the bottom one, so an edge
  # normally leaves a foreign key on a node's right and arrives at the
  # referenced `id` on another node's left. Declaration order is the order the
  # foreign-key table under the diagram reads in, which is not this one.
  @tables [
    %{schema: Templates.Flow, position: %{x: 840, y: 0}},
    %{schema: Templates.Form, position: %{x: 0, y: 0}},
    %{schema: Templates.Flow.Node, position: %{x: 420, y: 0}},
    %{schema: Templates.Flow.Relationship, position: %{x: 420, y: 320}},
    %{schema: Templates.Flow.Event, position: %{x: 840, y: 320}},
    %{schema: Templates.Form.Version, position: %{x: 0, y: 320}},
    %{schema: Instances.Flow, position: %{x: 840, y: 700}},
    %{schema: Instances.Form, position: %{x: 0, y: 700}},
    %{schema: Instances.Form.Event, position: %{x: 0, y: 1120}},
    %{schema: Instances.Flow.Event, position: %{x: 840, y: 1010}}
  ]

  # The five a reader should find first: a flow template, the nodes in it, a
  # form template, and the two tables those turn into once a user fills one
  # out. The other five support them — a form's versions, a flow's audit log
  # and each instance's, and the relationships between nodes. The page marks
  # these with a star.
  @primary [
    Templates.Flow,
    Templates.Flow.Node,
    Templates.Form,
    Instances.Flow,
    Instances.Form
  ]

  # What Ecto.Adapters.Postgres.Connection's `ecto_to_db` writes for each field
  # type these schemas use. `:string` carries Ecto's default size of 255,
  # `:map` is jsonb, and `:utc_datetime_usec` is a bare timestamp because the
  # migration's `timestamps/1` passes no precision.
  @postgres_types %{
    :binary_id => "uuid",
    :integer => "integer",
    :map => "jsonb",
    :string => "varchar(255)",
    :utc_datetime_usec => "timestamp"
  }

  # The columns where the migration declares a wider type than the Ecto field
  # type maps to: `:text` and `{:array, :text}` against the schemas' `:string`
  # and `{:array, :string}`. The migration is the DDL that runs, so it wins.
  @migration_types %{
    {"form_flow_template_forms", "description"} => "text",
    {"form_flow_template_flow_nodes", "labels"} => "text[]",
    {"form_flow_instance_forms", "path"} => "text[]"
  }

  # Every foreign key's ON DELETE, transcribed from
  # FormFlow.Data.Migrations.Postgres.V01. Named in Postgres's words rather
  # than Ecto's, since that is the DDL the page is describing: :delete_all is
  # CASCADE, :nilify_all is SET NULL, :nothing is NO ACTION.
  @on_delete_rules %{
    {"form_flow_template_flows", "owner_flow_id"} => :cascade,
    {"form_flow_template_flow_events", "flow_id"} => :restrict,
    {"form_flow_template_forms", "owner_flow_id"} => :set_null,
    {"form_flow_template_forms", "copied_from_form_id"} => :set_null,
    {"form_flow_template_form_versions", "form_id"} => :restrict,
    {"form_flow_template_form_versions", "based_on_version_id"} => :set_null,
    {"form_flow_template_flow_nodes", "flow_id"} => :cascade,
    {"form_flow_template_flow_nodes", "subflow_id"} => :no_action,
    {"form_flow_template_flow_nodes", "form_id"} => :no_action,
    {"form_flow_template_flow_relationships", "flow_id"} => :cascade,
    {"form_flow_template_flow_relationships", "source_id"} => :cascade,
    {"form_flow_template_flow_relationships", "target_id"} => :cascade,
    {"form_flow_instance_flows", "template_flow_id"} => :restrict,
    {"form_flow_instance_flow_events", "instance_flow_id"} => :restrict,
    {"form_flow_instance_forms", "template_form_version_id"} => :restrict,
    {"form_flow_instance_forms", "instance_flow_id"} => :restrict,
    {"form_flow_instance_form_events", "instance_form_id"} => :restrict,
    {"form_flow_instance_form_events", "from_version_id"} => :restrict,
    {"form_flow_instance_form_events", "to_version_id"} => :restrict
  }

  # One grey for every edge: a line's job here is to say which column points
  # at which, and the ON DELETE rule it carries is named in the table below
  # rather than encoded in a colour the reader has to decode.
  @edge_color "#a1a1aa"

  # In the order the legend lists them: from the rule that destroys the most
  # data to the one the database declines to enforce at all.
  @on_delete [
    %{
      rule: :cascade,
      label: "CASCADE",
      meaning: "deleting the referenced row deletes this one with it"
    },
    %{
      rule: :restrict,
      label: "RESTRICT",
      meaning: "the database refuses to delete the referenced row while this one points at it"
    },
    %{
      rule: :set_null,
      label: "SET NULL",
      meaning: "deleting the referenced row leaves this column NULL"
    },
    %{
      rule: :no_action,
      label: "NO ACTION",
      meaning:
        "the database allows it; FormFlow refuses in application code instead, " <>
          "where it can say why and control the ordering"
    }
  ]

  @doc """
  The diagram in ReactFlow's own shape, ready for
  `FormFlow.Web.Helpers.ReactFlow.to_json/1`.

  Every node is `type: "table"`, the node type the page's hook registers.
  """
  def data do
    %{
      nodes: Enum.map(@tables, &to_node/1),
      edges: Enum.flat_map(@tables, &to_edges/1)
    }
  end

  @doc """
  Every foreign key in the schema, in the order the tables are declared —
  the reference table the page draws under the diagram.
  """
  def foreign_keys do
    for %{schema: schema} <- @tables, association <- references(schema) do
      rule = on_delete_rule(table_name(schema), association.owner_key)

      %{
        table: table_name(schema),
        column: to_string(association.owner_key),
        references: "#{table_name(association.related)}.#{association.related_key}",
        on_delete: rule.label
      }
    end
  end

  @doc """
  The four `ON DELETE` rules the schema uses, for the diagram's legend.
  """
  def on_delete_legend, do: @on_delete

  @doc """
  How many tables the diagram draws.
  """
  def table_count, do: length(@tables)

  defp to_node(%{schema: schema, position: position}) do
    %{
      id: table_name(schema),
      type: "table",
      position: position,
      data: %{
        table: table_name(schema),
        schema: schema_name(schema),
        group: to_string(group(schema)),
        primary: schema in @primary,
        columns: columns(schema)
      }
    }
  end

  defp to_edges(%{schema: schema}) do
    table = table_name(schema)

    for association <- references(schema) do
      %{
        id: "#{table}.#{association.owner_key}",
        source: table,
        sourceHandle: to_string(association.owner_key),
        target: table_name(association.related),
        targetHandle: to_string(association.related_key),
        type: "smoothstep",
        style: %{stroke: @edge_color, strokeWidth: 1.5},
        markerEnd: %{type: "arrowclosed", color: @edge_color, width: 16, height: 16}
      }
    end
  end

  # `belongs_to` is the only association that owns a column, so it is the only
  # one the database sees. `has_many` is the same foreign key read backwards
  # and would draw each edge twice.
  defp references(schema) do
    schema.__schema__(:associations)
    |> Enum.map(&schema.__schema__(:association, &1))
    |> Enum.filter(&match?(%Ecto.Association.BelongsTo{}, &1))
  end

  defp columns(schema) do
    keys = Map.new(references(schema), &{&1.owner_key, "FK"})

    for field <- schema.__schema__(:fields) do
      key = if field == :id, do: "PK", else: keys[field]

      %{
        name: to_string(field),
        type: postgres_type(schema, field),
        key: key,
        handle: handle(key)
      }
    end
  end

  # Only the columns an edge attaches to get a handle: a primary key is where
  # edges arrive, a foreign key is where they leave, and the rest are text.
  defp handle("PK"), do: "target"
  defp handle("FK"), do: "source"
  defp handle(nil), do: nil

  defp postgres_type(schema, field) do
    table = table_name(schema)
    column = to_string(field)

    case @migration_types[{table, column}] do
      nil -> ecto_to_postgres(schema.__schema__(:type, field), table, column)
      declared -> declared
    end
  end

  defp ecto_to_postgres({:array, type}, table, column),
    do: ecto_to_postgres(type, table, column) <> "[]"

  defp ecto_to_postgres(type, table, column) do
    @postgres_types[type] ||
      raise """
      No Postgres type is mapped for #{inspect(type)}, the Ecto type of \
      #{table}.#{column}. Add it to @postgres_types in \
      #{inspect(__MODULE__)}, or to @migration_types if the migration \
      declares something wider.
      """
  end

  defp on_delete_rule(table, column) do
    rule = Map.fetch!(@on_delete_rules, {table, to_string(column)})

    Enum.find(@on_delete, &(&1.rule == rule))
  end

  defp table_name(schema), do: schema.__schema__(:source)

  # "Templates.Flow.Node" rather than the full module: every schema shares the
  # FormFlow.Data prefix, and the page says so once in prose instead of ten
  # times on the canvas.
  defp schema_name(schema) do
    ["FormFlow", "Data" | rest] = Module.split(schema)

    Enum.join(rest, ".")
  end

  defp group(schema) do
    case Module.split(schema) do
      ["FormFlow", "Data", "Templates" | _] -> :templates
      ["FormFlow", "Data", "Instances" | _] -> :instances
    end
  end
end
