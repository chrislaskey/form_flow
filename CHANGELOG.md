# Changelog

## Unreleased

### Node menus on the canvas

Every node in the flow editor now carries a ⋮ menu — the home for managing a
node through the UI. ReactFlow has no native menu component, so this is
form_flow's own: a general-purpose dropdown each node type composes from
shared entries plus (in the future) its own. The first entry is **Delete**,
which asks for confirmation and then routes through ReactFlow's
`deleteElements` — the same path as the Backspace key, so connected edges
cascade, pinned Start/End nodes (`deletable: false`) don't offer it, and the
removal stays pending until Save like every other canvas edit. Menu items
declare `confirm` individually, so future destructive entries get the same
misclick protection. Read-only canvases show no menu, since
its only entry is an editing action. The editor bundle was rebuilt.

### Inline node renames on the canvas

In edit mode every node's title is a text input, so renaming no longer
requires drilling into each node's dedicated page (which still works — both
paths edit the same value). For nodes backed by a real entity the rename
writes through at save: a subflow node renames its embedded flow, a form
step renames its collected form — including shared/reusable ones, consistent
with their edit-everywhere semantics — and loading projects the entity's
current name back into the node's title, so the canvas and the entity's own
pages can't drift. Blank labels never blank a name. Entity-less nodes
(Start/End) keep the label as node-local data. A freshly added node
autofocuses its name input with the placeholder name selected, so it can be
renamed by just typing. Show mode renders plain text titles as before.

### Form flow types (`form_flow_type`)

How a "forms" flow presents its forms to the user filling them out is now a
stored, configurable property: `"wizard_in_order"` (forms completed one after
another) or `"wizard_any_order"` (every form visible, completable in any
order), with the choices supplied by the `FormFlow.Config` behaviour's
`form_flow_type_options/2` callback. What each type *does* is the section
below; this one is where the choice is stored and the config pattern hooked
up.

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

### Flow types: which forms a filler may open, and where they land next

`form_flow_type` now decides what a filler actually sees. A "forms" flow's
stored type resolves — through `FormFlow.Config`'s `form_flow_type_module/3`
— to a module implementing the new `FormFlow.Flows.Types` behaviour, and the
user-facing pages ask it rather than deciding for themselves:

- `FormFlow.Flows.Types.WizardInOrder` (`"wizard_in_order"`) — the flow's
  forms are completed front to back, as before. Their progress is now
  *shown*, which is the new part, but not navigable: no jumping ahead.
- `FormFlow.Flows.Types.WizardAnyOrder` (`"wizard_any_order"`) — every form
  that isn't done is navigable, so a filler can jump ahead. Submitting one
  moves them to the next form still open, wrapping back to the beginning (a
  skipped form is still waiting there); when nothing in the flow is open any
  more, the journey takes over.

An unset or unrecognized type resolves to the in-order wizard, which is also
`FormFlow.Flows.Types`' set of defaults — so a custom type `use`s the
behaviour and overrides only what it changes, exactly as a custom config
module extends `FormFlow.Config`. Three callbacks: `show_progress?/1`,
`openable?/2`, and `next_form/2`.

A type governs one "forms" flow, because that is where `form_flow_type` is
stored: a journey holds as many of them as it has "forms" flows, each with
its own type, and every question is asked of the flow the form belongs to.

- **Breaking: `FormFlow.Data.Instances.Progress` is now
  `FormFlow.Data.Instances.FlowProgress`** — it derives one flow instance's
  progress, and the name now says so. `derive/2`, `complete?/2`, and
  `next_path_position/2` are unchanged; nothing about how progress is
  *derived* changed.
- `FlowProgress.forms/2` is the new second view of that derivation: the
  journey's form positions as an ordered list of
  `FormFlow.Data.Instances.FormProgress` structs — one per form, carrying its
  label, the subflow nodes drilled through to reach it, its live form
  instance, and the "forms" flow it belongs to, alongside the derived status.
  Order is the order a filler works them. `forms_in_flow/2` narrows the list
  to one flow's own, which is what every `FormFlow.Flows.Types` callback
  takes; `find_form/2` and `qualified_label/1` round it out.
- **New: `FormFlow.Web.Instances.Components.FlowProgress`** draws a flow's
  forms above the one being filled, each with its state, the current one
  marked `aria-current="step"`. A single-form flow draws nothing —
  `show_progress?/1` — and a form that can't be navigated to renders as the
  same button, disabled, so the row doesn't shift as forms become reachable.
  Its `badge/1` is now the one home for the wording and colors of a form's
  state, shared with the journey page's listing.
- The journey page's Open button now appears wherever the form's own flow
  type says `openable?/2` — an any-order wizard offers forms an in-order one
  keeps closed. Continue, View, and Reopen are unchanged.
- Submitting a form asks the type where to go next (`next_form/2`, against
  freshly derived statuses) and falls back to the journey's next actionable
  position when that flow has nothing left — which is what still carries a
  filler out of a finished subflow and into the next one. Nothing actionable
  anywhere: the journey page, as before.
- `FormFlow.Web.Router` now forwards `config` and `config_data` to the
  journey and form-instance pages too, so a host's config module answers on
  the user-facing side.
- **New: `FormFlow.Web.Instances.Positions.open/3`** — opening a position
  (create-on-open, which pins the version) with the failure wording both
  pages share.
- **New: `FormFlow.Flows`** namespace, for how a flow *behaves* as opposed to
  how it is stored (`FormFlow.Data`) or presented (`FormFlow.Web`).
- The demo grows a custom type end to end: the admin page's config offers
  "Demo checklist" (as before) and the users page's config now resolves it to
  `DemoWeb.FormFlowLive.Users.Checklist`, which overrides all three callbacks
  — every form open, finishing one returns to the top of the list, and the
  list is drawn even for a single-form flow.

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
