# Changelog

## Unreleased

### Node menus on the canvas

Every node in the flow editor now carries a ⋮ menu — the home for managing a
node through the UI. ReactFlow has no native menu component, so this is
form_flow's own: a general-purpose dropdown each node type composes from
shared entries plus (in the future) its own. The first entry is **Delete**,
which routes through ReactFlow's `deleteElements` — the same path as the
Backspace key, so connected edges cascade, pinned Start/End nodes
(`deletable: false`) don't offer it, and the removal stays pending until
Save like every other canvas edit. Read-only canvases show no menu, since
its only entry is an editing action. The editor bundle was rebuilt.

### Form flow types (`form_flow_type`)

How a "forms" flow presents its steps to the user filling it out is now a
stored, configurable property: `"wizard_in_order"` (steps completed one after
another) or `"wizard_any_order"` (every step visible, completable in any
order), with the choices supplied by the `FormFlow.Config` behaviour's
`form_flow_type_options/2` callback. Rendering instances against the chosen
type (`form_flow_type_module/3`) comes in a future release — this release
stores the choice and hooks up the config pattern.

- **Breaking: `form_flow_flows` gained a `properties` column** (a map,
  Neo4j-style, like nodes and relationships already had). The initial schema
  is rewritten in place, pre-release style: drop and recreate any existing
  database (`mix ecto.reset`). The chosen type is stored under
  `properties["form_flow_type"]`; absent means the configured default
  decides.
- The flow edit page's name input is now a `DynamicForm` form and, on
  "forms" flows, carries a "Form flow type" dropdown populated from
  `form_flow_type_options/2`. The header's Save writes the canvas and these
  fields together; pending values ride the same unsaved-changes guard as
  canvas edits.
- `FormFlow.Web.Router` now forwards its `config` and `config_data` attrs to
  the flow Show and Edit pages, which call the configured module (falling
  back to `FormFlow.Config`'s defaults) with a `FormFlow.Config.Context`.
- In a "subflows" flow's canvas, form subflow nodes render the same choices
  on the node itself: a dropdown in edit mode, plain text in show mode. The
  embedded flow's `properties` stay the single source of truth — the node's
  `data.form_flow_type` is transport only. Saves pop it out of the node's
  properties and write it through to the embedded flow (clearing when
  "Type: default" is picked; write-through to a reusable child changes it
  for every consumer), and loads project the stored value back into the
  node's data. The editor bundle was rebuilt
  (`FormFlow.Web.Components.Editor` passes the options in via
  `formFlowTypeOptions`).

## v0.6.0

### Breaking: Renamed Graph to Flow

The stored diagram concept is now named what every other surface already
called it — routes, UI, and documentation all said "flow" while the data
layer said "graph". The rename is a hard cutover with no migration path: the
initial schema is rewritten in place (pre-release, no production installs).
Drop and recreate any existing database (`mix ecto.reset`).

Modules moved under the `Templates` namespace, beside
`FormFlow.Data.Templates.Form` — a flow definition is a design-time template
on the same axis as a form template:

| Before | After |
|--------|-------|
| `FormFlow.Data.Graphs` | `FormFlow.Data.Templates.Flows` |
| `FormFlow.Data.Graph` | `FormFlow.Data.Templates.Flow` |
| `FormFlow.Data.Graph.Node` | `FormFlow.Data.Templates.Flow.Node` |
| `FormFlow.Data.Graph.Relationship` | `FormFlow.Data.Templates.Flow.Relationship` |

Tables were renamed, and the `graph_` segment dropped from the child tables —
nothing else in the schema has nodes or relationships:

| Before | After |
|--------|-------|
| `form_flow_graphs` | `form_flow_flows` |
| `form_flow_graph_nodes` | `form_flow_nodes` |
| `form_flow_graph_relationships` | `form_flow_relationships` |

Columns: `graph_id` is now `flow_id` (nodes, relationships), and
`owner_graph_id` is now `owner_flow_id` (flows, template forms). The
`"graph_id"` key the schemas copy into `properties` for the future Neo4j
dual-write is now `"flow_id"` — stored data written before this change will
not be adopted.

The web/editor contract renamed with it: the LiveView events are
`form_flow:flow_changed` and `form_flow:set_flow`, the editor bundle's mount
options take `flow` and return a `setFlow/1` handle, and
`FormFlow.Web.Helpers.ReactFlow.to_graph_attrs/1` is now `to_flow_attrs/1`.
The committed editor bundle was rebuilt.

`Node` and `Relationship` keep their Neo4j property-graph names, and the
Neo4j mapping (`guides/neo4j.md`) now targets `:Flow` nodes instead of
`:Graph`. Routes are unchanged — the web layer already spoke `/flows`.
