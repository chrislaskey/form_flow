defmodule DemoWeb.DocsLive.DataModelingLive.GraphSchema do
  @moduledoc """
  The Neo4j side of `DemoWeb.DocsLive.DataModelingLive`: the three entities a dual-write
  would create, drawn with the same node type as the SQL schema above them so
  the two read as one page.

  Nothing here is derived. There is no graph database to read it off — the
  extension does not exist yet — so this is a transcription of the mapping
  `guides/neo4j.md` records, and that guide is the thing to check when the two
  drift.

  Everything here is a node, a relationship, or a flow — the data model's own
  words. A node is what the product calls a *step*, and where that reading
  matters the page says "node (step)" rather than switching vocabulary.

  Three points the drawing is making, each of which surprises people:

    * **Only the graph half of the templates crosses over.** Nodes,
      relationships, and the flows they point at. Form templates, form
      versions, and every instance table stay in SQL and are joined back by id
      — a `form_id` in a Neo4j property map is a key into Postgres, not a
      pointer into the graph.
    * **Flows are Neo4j nodes, not a third kind of thing.** Anything a
      reference targets has to be a node or the reference cannot be traversed,
      and subflow and ownership references both point at flows.
    * **A node carries labels, a relationship carries one type.** That is
      Neo4j's model, and FormFlow's SQL mirrors it: `labels text[]` on the
      nodes table, a single `label varchar` on the relationships table.

  The edges here are not foreign keys. Three of them are *structural*: the
  relationship Neo4j would hold that no relationships row does, because a
  property already says it. They draw dashed.
  """

  # Left to right, targets on the right, the same direction the SQL schema
  # reads: the flow everything points at is the right-hand column.
  @entities [
    %{
      id: "relationship",
      title: "[:CONNECTS_TO]",
      source: "form_flow_template_flow_relationships",
      position: %{x: 0, y: 30},
      fields: [
        {"type", "string ← label", nil},
        {"startNode", "node", :source},
        {"endNode", "node", :source},
        {"properties.flow_id", "uuid", nil},
        {"properties.tenant_id", "string", nil},
        {"properties.*", "domain data", nil}
      ]
    },
    %{
      id: "node",
      title: "(:Node)",
      source: "form_flow_template_flow_nodes",
      position: %{x: 420, y: 0},
      fields: [
        {"labels", "list<string>", :target},
        {"properties.flow_id", "uuid", :source},
        {"properties.subflow_id", "uuid", :source},
        {"properties.form_id", "uuid → SQL", nil},
        {"properties.slug", "string", nil},
        {"properties.tenant_id", "string", nil},
        {"properties.*", "domain data", nil}
      ]
    },
    %{
      id: "flow",
      title: "(:Flow)",
      source: "form_flow_template_flows",
      position: %{x: 840, y: 40},
      fields: [
        {"labels", "[\":Flow\"]", nil},
        {"id", "uuid", :target},
        {"name", "string", nil},
        {"slug", "string", nil},
        {"status", "string", nil},
        {"owner_flow_id", "uuid", :source},
        {"properties.*", "domain data", nil}
      ]
    }
  ]

  # `structural?` is the dashed ones: derived from a property, not stored as a
  # relationship row. `CONNECTS_TO`'s two ends are the row itself, so they are
  # drawn solid.
  @edges [
    %{
      from: {"relationship", "startNode"},
      to: {"node", "labels"},
      label: nil,
      structural?: false
    },
    %{from: {"relationship", "endNode"}, to: {"node", "labels"}, label: nil, structural?: false},
    %{from: {"node", "properties.flow_id"}, to: {"flow", "id"}, label: "IN", structural?: true},
    %{
      from: {"node", "properties.subflow_id"},
      to: {"flow", "id"},
      label: "EMBEDS",
      structural?: true
    },
    %{
      from: {"flow", "owner_flow_id"},
      to: {"flow", "id"},
      label: "OWNED_BY",
      structural?: true
    }
  ]

  # The same grey the SQL diagram's edges use
  @edge_color "#a1a1aa"

  @doc """
  The graph schema in ReactFlow's own shape, ready for
  `FormFlow.Web.Helpers.ReactFlow.to_json/1`.

  Every node is `type: "table"` — the same component the SQL schema uses, so a
  reader compares two drawings rather than learning two.
  """
  def data do
    %{nodes: Enum.map(@entities, &to_node/1), edges: Enum.map(@edges, &to_edge/1)}
  end

  @doc """
  The reserved relationship types, the property each is derived from, and what
  it means — the table the page draws under the graph.
  """
  def structural_types do
    [
      %{
        type: "IN",
        derived_from: "(:Node).properties.flow_id",
        meaning: "the flow a node (step) belongs to"
      },
      %{
        type: "EMBEDS",
        derived_from: "(:Node).properties.subflow_id",
        meaning: "the flow a node (step) embeds"
      },
      %{
        type: "OWNED_BY",
        derived_from: "(:Flow).owner_flow_id",
        meaning: "the root a subflow belongs to"
      }
    ]
  end

  defp to_node(entity) do
    %{
      id: entity.id,
      type: "table",
      position: entity.position,
      data: %{
        schema: entity.title,
        table: entity.source,
        group: "templates",
        primary: false,
        columns:
          for {name, type, handle} <- entity.fields do
            %{name: name, type: type, key: nil, handle: handle && to_string(handle)}
          end
      }
    }
  end

  defp to_edge(edge) do
    {source, source_field} = edge.from
    {target, target_field} = edge.to

    %{
      id: "#{source}.#{source_field}->#{target}.#{target_field}",
      source: source,
      sourceHandle: source_field,
      target: target,
      targetHandle: target_field,
      type: "smoothstep",
      label: edge.label,
      labelBgPadding: [6, 2],
      labelBgBorderRadius: 3,
      labelBgStyle: %{fill: "#fff", stroke: @edge_color},
      labelStyle: %{fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace", fontSize: 10},
      style: edge_style(edge),
      markerEnd: %{type: "arrowclosed", color: @edge_color, width: 16, height: 16}
    }
  end

  defp edge_style(%{structural?: true}),
    do: %{stroke: @edge_color, strokeWidth: 1.5, strokeDasharray: "4 3"}

  defp edge_style(%{structural?: false}), do: %{stroke: @edge_color, strokeWidth: 1.5}
end
