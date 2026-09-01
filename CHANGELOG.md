# Changelog

## Unreleased

### `FormFlow.Config` describes types as structs

The config behaviour now answers *which types exist* rather than answering
per-value questions. Its two callbacks each return a list of structs, and
every struct carries the module that implements the type — so offering a
type and implementing it is one declaration, not two callbacks on two pages.

- **Breaking: `FormFlow.Config`'s callbacks are `enabled_flow_types/2` and
  `enabled_form_types/2`**, returning `FormFlow.Config.Flows.Type` and
  `FormFlow.Config.Forms.Type` structs (`id`, `module`, `name`,
  `description`, `properties`). `form_flow_type_options/2` and
  `form_flow_type_module/3` are gone. The defaults live in
  `FormFlow.Web.Components.Config.Default`; a custom module reaches them
  through `FormFlow.Config.enabled_flow_types/3` (and `/3` for forms), which
  also fall back to the defaults when the host set no `config`.
- The template pages' "Form flow type" dropdowns are populated from
  `enabled_flow_types/2`, each type's `name` and `id` as the option. The
  config reads its `FormFlow.Context` to decide what to offer: the flow edit
  page asks with the flow itself as `:subflow`, and the default config
  answers the two wizards (`"wizard_any_order"`, `"wizard_in_order"`) for a
  "forms" flow and nothing for a "subflows" flow — so whether a flow gets a
  dropdown at all is the config's call, not the page's. A "subflows" canvas's
  form subflow nodes ask separately, with the "forms" flow such a node
  embeds as `:subflow`, so they still get the types on a flow that has none
  of its own.
- **Breaking: `FormFlow.Flows.Types` is `FormFlow.Config.Flows.Type`**, and
  the `WizardInOrder` / `WizardAnyOrder` modules live under
  `FormFlow.Web.Components.Flows.Types`. A flow type `use`s the behaviour
  and overrides only what it changes; the defaults
  (`FormFlow.Web.Components.Flows.Types.Default`) are the in-order wizard.
  Its three callbacks each take a `FormFlow.Context` and `config_data`:
  `editable?/2` (may the user edit the form at `:form_progress` — start it,
  or keep working on it), `on_complete/2` (the next form after finishing it,
  or `nil` to hand back to the flow instance), and `progress_component/1`
  (the progress drawn above the form — `nil` draws nothing, which is what the
  old `show_progress?/1` decided). `openable?/2` is `editable?/2` and
  `next_form/2` is `on_complete/2`.
- `FormFlow.Context` gained the user-facing side: `:flow_instance`, the
  `:form_progress` in question, and `:flow_progress` — its flow's forms in
  order. Template-side callbacks see them as `nil`.
- The instance pages resolve a flow's stored `form_flow_type` among what the
  config enables for the context
  (`FormFlow.Web.Instances.Forms.Shared.flow_type/2`), so a host's config
  answers on the user-facing side too. Unset or unrecognized resolves to the
  first enabled type — the default config now lists the in-order wizard
  first, so it stays the baseline — and a context with no enabled types to
  the library's defaults. `FormFlow.Config` itself is only the behaviour and
  `config_module/1`.
- The user-facing side says "start" where it said "open": the flow instance
  page's button is **Start**, and `FormFlow.Web.Instances.Forms.Shared`
  takes `start: true` and assigns `:start_error`. Starting a form creates its
  instance, which is what pins the form version; editing is everything after.
  Reopen, which returns a completed form to in progress, keeps its name.
- **New: `FormFlow.Data.Instances.FlowProgress.actionable?/1`** — whether
  the flow allows work on a form (predecessors done, or already started),
  the primitive the in-order defaults are built on.
- **Breaking: `FormFlow.Config.Context` is `FormFlow.Context`.**
- The demo app's `DemoWeb.FormFlowLive.Config` — one module for both the
  admin and users pages, since a type is chosen on one side and acted on in
  the other — adds its `"demo_checklist"` type as a struct pointing at
  `DemoWeb.FormFlowLive.Checklist`, which overrides all three callbacks.

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
  back to `FormFlow.Config`'s defaults) with a `FormFlow.Context`.
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

### Flow types: which forms a user may open, and where they land next

`form_flow_type` now decides what a user actually sees. A "forms" flow's
stored type resolves — through `FormFlow.Config`'s `form_flow_type_module/3`
— to a module implementing the new `FormFlow.Flows.Types` behaviour, and the
user-facing pages ask it rather than deciding for themselves:

- `FormFlow.Flows.Types.WizardInOrder` (`"wizard_in_order"`) — the flow's
  forms are completed front to back, as before. Their progress is now
  *shown*, which is the new part, but not navigable: no jumping ahead.
- `FormFlow.Flows.Types.WizardAnyOrder` (`"wizard_any_order"`) — every form
  that isn't done is navigable, so a user can jump ahead. Submitting one
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
  Order is the order a user works them. `forms_in_flow/2` narrows the list
  to one flow's own, which is what every `FormFlow.Flows.Types` callback
  takes; `find_form/2` and `qualified_label/1` round it out.
- **New: `FormFlow.Web.Instances.Components.Flows.Progress`** draws a flow's
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
  user out of a finished subflow and into the next one. Nothing actionable
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

### Breaking: the user-facing URLs mirror the template URLs

`/journeys` and `/instances` are gone. They were the only nouns in the URL
space that named nothing in the data model — the schemas are
`FormFlow.Data.Instances.Flow` and `FormFlow.Data.Instances.Form`, and
"journey" was prose from the design notes — and the form URL addressed its
*database row* rather than its place in the flow, because opening created the
row before navigating. Both sides now use the same nouns, since the mount root
already says which world you are in:

| Before | After |
|--------|-------|
| `/journeys` | `/flows` |
| `/journeys/:id` | `/flows/:id` |
| `/journeys/:id/instances/:instance_id` | `/flows/:id/forms/*path` (read-only) |
| — | `/flows/:id/forms/*path/edit` (fillable) |

`/admin/flows/:id` is a flow template and `/users/flows/:id` is a flow
instance, page for page.

A form is now addressed by its **position**: `*path` is the chain of node ids
from the root flow down to the form node — the same `path` the instance row
stamps — so a form two subflows deep has three segments. The template side
needs no such chain, because every path to a shared subflow reaches the same
template; two paths through an *instance* are two different sets of answers.

That the URL of a position exists before its row does is what the rest of this
follows from:

- **`/edit` is the only page that writes.** It opens the position it addresses
  — create-on-open, which is what pins the form version — gated by the same
  `FormFlow.Flows.Types` `openable?/2` the listing asks, and idempotent
  afterwards. So the address bar cannot walk around a flow's type, and a
  refresh, a Back, or a bookmark all land where they should.
- **Every navigation to a form is an ordinary link.** Open, Continue, and the
  drawn progress's jumps were `phx-click` handlers that created a row and then
  redirected; they are now `<.link navigate>`. The `"open_form"` event and
  `FormFlow.Web.Instances.Positions` are both gone, and submitting no longer
  opens the next position itself — it navigates to that position's `/edit`,
  which does.
- **Bare `/forms/*path` is the read-only view** and never writes: with nothing
  filled in yet it says so and offers the Start link when the flow's type
  allows work there; with answers it shows them, submit hidden. Reopen is
  still an explicit button, since it changes state, and now lands on `/edit`.
- **New: `FormFlow.Web.Instances.Paths`** builds all four URLs, so the shape
  lives in one place.
- **New: `FormFlow.Data.Instances.Forms.get_at/2`** — the live (not
  superseded) instance at a position, which is how a position-addressed page
  finds its row.
- `FormFlow.Web.Instances.Components.Flows.Progress` takes `base` and
  `flow_instance_id` instead of `target`, since it renders links now.
- The pages' `journey_id` assign is `flow_instance_id`, and the UI says
  "Flows" where it said "Journeys".

### "Journey" is grounded where it is used

The docs use "journey" freely for the thing a user works through, and nothing
in the schema carries that name, so `FormFlow.Data.Instances` now defines it
once: an instance of a *whole* root flow — the `FormFlow.Data.Instances.Flow`
row plus every `FormFlow.Data.Instances.Form` filled at a position inside it
— is what the docs call a **journey**. Along with why the shorthand exists at
all, since "flow instance" alone reads as one step's worth of work.

- Every moduledoc that reaches for the word now grounds it on first mention
  rather than assuming it (`FlowProgress`, `FormProgress`, both `Flows` and
  `Forms` contexts, the `Flow` and `Form` schemas, `Flow.Event`, and the
  template-side delete guard) — always concrete first, shorthand second: "a
  whole root flow instance — a journey", never the other way round, so the
  term is never load-bearing before it is defined. `FormFlow.Flows.Types` had
  one incidental use and now says "flow instance", the concrete term, rather
  than introducing a word it never defines.
- The one user-visible string that had nowhere to ground itself changed with
  it: deleting a flow that is in use now reports `"cannot be deleted: flow
  instances have been started against it"`.

### The user-facing form page is two pages

`FormFlow.Web.Instances.Forms.Show` carried a `mode` attr and branched on it
throughout — read-only or fillable, one file. The two URLs are two pages, so
they are now two components, the way the template side has always had
`Templates.Forms.Show` and `.Edit`:

- **`FormFlow.Web.Instances.Forms.Show`** (`/flows/:id/forms/*path`) renders
  the answers read-only and never opens anything. Reopen lives here, beside
  the answers it reopens, and lands on Edit.
- **`FormFlow.Web.Instances.Forms.Edit`** (`/flows/:id/forms/*path/edit`) is
  the page that opens a position, and the only one that renders a submittable
  form. An already-submitted position renders no form at all: it points back
  to Show, so exactly one page renders answers read-only and exactly one
  reopens them.

`mode` is gone — the module *is* the mode — and with it the `read_only?/1`
branch, the mode-keyed DynamicForm id, and the `:if={@mode == :show}` guards.

Two pieces are shared rather than duplicated, since two copies of a gate can
drift apart:

- **New: `FormFlow.Web.Instances.Forms.Shared`** resolves what is at the
  position both pages address — which form the path names, its flow's
  `FormFlow.Flows.Types` module, whether the type allows work there, the live
  instance, and the parsed definition. `resolve/2` reads the page's assigns
  and writes the answers back; `open: true` is Edit's mode and the one write
  in it.
- **New: `FormFlow.Web.Instances.Components.FormPage`** holds the frame both
  pages put around their content: the breadcrumb, and the panel that stands in
  for a form when there is none. The wording of that panel stays with the
  page, since Show and Edit have different things to say about an absent form.

While the opening moved: the progress bar is now derived *after* a position is
opened, so the form being filled reads as in progress rather than available —
it was drawn from statuses derived a moment before the open.

### Every listing is a `Slab.table`

The user-facing flow listing was the last hand-rolled `<table>` in the
library — plain `thead`/`tbody`, no sorting, no pagination, the whole list
fetched at once. It is now a `Slab.table` in query mode, like both template
indexes:

- **New: `FormFlow.Data.Instances.Flows.list_query/1`** — the same listing as
  a composable query, unordered and unpreloaded so `order_by`,
  `limit`/`offset`, `Repo.aggregate(:count)`, and preloads can be layered on
  top. `list/1` is now built from it and behaves exactly as before.
- The flow's name comes from the `:flow` association through Slab's `preload`
  attr, which it applies *after* filtering, sorting, and counting — so the
  query stays aggregate-safe. That column is deliberately not sortable: it is
  a joined value, not a column Slab could compile into `ORDER BY`.
- Sorting defaults to newest first, matching `list/1`, and the default is only
  injected when the URL carries no sort of its own — a bare `sort_direction`
  default would make every other column start descending.
- `FormFlow.Web.Router` now forwards `uri` and `params` to the flow listing,
  which URL-driven sorting and pagination need. Hosts calling the component
  directly should pass both from `handle_params/3`.
- "Start a new flow" stays a plain list rather than becoming a second table:
  Slab reads `sort` and `page` straight from the URL, so two Slab tables on
  one page would share — and fight over — the same params.

Two listings stay lists on purpose, and say so: the forms on a flow instance's
page are in *flow order*, which sorting would destroy, and are derived
`FormFlow.Data.Instances.FormProgress` structs rather than rows; the version
sidebar on a form's page is navigation, not data.

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
