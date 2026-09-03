# Changelog

## v0.13.0

### Templates and instances know their tenant; form instances know their user

**New: `tenant_id`, everywhere a host's data lands.** `FormFlow.Data.Templates.Flow`,
`FormFlow.Data.Templates.Form`, `FormFlow.Data.Instances.Flow`, and
`FormFlow.Data.Instances.Form` each gain a `tenant_id` column — the host
tenant the row belongs to, an opaque host identity, `nil` for a host with
no tenants — stamped at creation and immutable afterwards. On the two
templates it is dual-written the way a node's `flow_id` is: the indexed
column, plus a `"tenant_id"` key inside `properties`, the copy that carries
over to Neo4j; the column is authoritative and a stale copy arriving in
`properties` is overwritten. On the two instances it is the column alone.
FormFlow enforces nothing with it; it is for the host's own queries and
authorization.

**`FormFlow.Data.Instances.Form` gains `user_id`** — the user who started
the form, stamped when `FormFlow.Data.Instances.Forms.update_status/4`
creates the instance from its `:user_id` option, which until now reached
only the event. Immutable, like the flow instance's.

- **`tenant_id` is an optional attr on `FormFlow.Web.router/1`**, defaulting
  to `nil`, and on the index and new LiveComponents of both template
  sections and the four instance LiveComponents. Only multitenant hosts set
  it. Flows and forms created from the template pages are stamped with it;
  so are flow instances started from the listing and form instances started
  inside them, exactly as `user_id` is. It also reaches every
  `FormFlow.Config` callback as `FormFlow.Context.tenant_id`.
- **Tenancy flows down the tree.** Owned subflows and owned forms a save
  creates take their root's tenant; `FormFlow.Data.Templates.Flows.duplicate/2`
  and `FormFlow.Data.Templates.Forms.copy/2` carry the source's into the copy.
- **The listings narrow by tenant.** `FormFlow.Data.Templates.Flows.list/1`,
  `roots_query/1`, and `list_reusable/1`, `FormFlow.Data.Templates.Forms.list/1`
  and `catalog_query/1`, and `FormFlow.Data.Instances.Flows.list/1` and
  `list_query/1` take `tenant_id:`. The three index pages and the
  start-a-flow picker pass the router's. Listing conveniences, not access
  control.
- `FormFlow.Data.Instances.Forms.update_status/4` takes `:tenant_id`,
  stamped on the instance when the call creates it.
- `FormFlow.Data.Templates.Forms.update/2` goes through the schema
  changeset, so a renamed catalog form colliding on `name` is a refused
  save rather than a raised constraint error.
- **Breaking: the v01 migration changed.** `form_flow_flows` and
  `form_flow_template_forms` gain `tenant_id`; `form_flow_instance_flows`
  gains `tenant_id`; `form_flow_instance_forms` gains `user_id` and
  `tenant_id`; every one of them is indexed. Drop and recreate any database
  migrated before this version.

### The listing asks the config too

**New: `flow_instances_query/2` on `FormFlow.Config`.** The listing page
shows whatever query the host's config returns — by default the current
user's own flow instances, exactly as before. A reviewer's desk returns
`FormFlow.Data.Instances.Flows.list_query/1` bare to list everyone's; a
host with finer rules layers its own `where` on top. The router's
`tenant_id` is applied after the callback answers, so a multitenant host
never lists across tenants by accident, and the host never has to think
about tenants in its query (`FormFlow.Data.Instances.Flows.narrow_tenant/2`
is the public helper that does it).

- **`handle_mount/2` now gates the listing as well.** Every user-facing page
  asks before it draws. On the listing the context carries only `:user_id`
  and `:tenant_id` — there is no flow in scope — and a refusal renders the
  message alone, a redirect navigates.
- The router passes `config` and `config_data` to the listing component.

### Templates have slugs

**New: `slug` on `FormFlow.Data.Templates.Flow` and
`FormFlow.Data.Templates.Form`** — a stable secondary identifier a host
looks a template up by without knowing its `id`, which differs between
environments (`FormFlow.Data.Templates.Slug`). Optional and nullable, unique
per tenant within its table, dual-written into `properties["slug"]` like
`tenant_id`, and never a foreign key — `id` still does that job. A slug
never follows a rename; it changes only when an admin changes it.

- **Every template gets one by default.** `Flows.create/1` and
  `Forms.create/1` generate a slug from the name when none is given, ten
  letters at most: one word truncates, two words join with a hyphen ("Dog
  Licensing" is `dog-license`, "User Information" is `user-inform`), three
  or more take their initials with numbers kept whole ("Dog License
  Application 2026" is `dla2026`). The subflows and forms
  a canvas save creates prefix their segment with the containing flow's
  slug, so nested children carry the whole chain: `dla2026_documents_user-inform`.
  A taken slug gets `-2`, `-3`, … — chosen by querying, not by retrying the
  insert, which would abort the enclosing transaction on Postgres.
- **`Flows.get_by_slug/2` and `Forms.get_by_slug/2`** look a template up by
  slug. `tenant_id:` is an optional keyword: a host with no tenants passes
  only the slug; a multitenant host passes the tenant, since the same slug
  can exist once per tenant.
- **Copies get fresh slugs.** `Flows.duplicate/2` takes `slug:`, defaulting
  to the source's with a free suffix, and rewrites its copied children's
  prefix from the old root slug to the new one — `dla2026_user-inform` under
  a copy slugged `dla2027` becomes `dla2027_user-inform`. `Forms.copy/2` takes
  `slug:` the same way.
- **Fixed: `Flows.duplicate/2` copies the identity.** The copy carries the
  source's name, label, and properties; until now it came back nameless,
  labelled "forms" whatever the source was, and without its type.
- **A Slug field on every template page.** The new-flow and new-form pages
  take one and generate it when left blank; the flow edit header and the
  form edit page let an admin change or clear it, and a slug that is taken
  or malformed is a refused save that names the field.
- **Breaking: the v01 migration changed again.** `form_flow_flows` and
  `form_flow_template_forms` gain `slug`, with a partial unique index over
  `slug` and `COALESCE(tenant_id, '')` — coalesced because both databases
  treat NULLs as distinct, which would let a host with no tenants reuse a
  slug. Drop and recreate any database migrated before this version.

## v0.12.0

### The config gates its pages: `handle_mount/2`

**New: `handle_mount/2` on `FormFlow.Config`.** Every user-facing page — the
flow instance's page and the two form pages, edit and Show — asks the host's
config whether it may render, once it has resolved what it addresses and
before anything is drawn. The context is the page's: on the flow instance's
page the root flow and every form of the instance, no form in scope; on a
form page the form's, with `:form_instance` the live instance or nil for a
form not yet started. The answer is one of `{:ok, assigns}` (render, with the
assigns merged into the page's), `{:error, message}` (render the message
alone, with a way back), or `{:redirect, to}` (navigate, rendering nothing
meanwhile). It is where a host authorizes by flow instance or by position, and
it lives on the config rather than the types because a config is per use of
the router while a type is global: the same review type can sit in flows with
different auth rules.

- **On the edit page it runs before the form is started**, so a refused or
  redirected visitor creates no instance and pins no version.
  `FormFlow.Web.Instances.Forms.Shared.assigns/1` now resolves a position
  without writing, and `start/1` is the separate second step Edit takes only
  when the config allowed the page. The `start:` option is gone.
- The callback is host code and is deliberately not rescued: an exception
  fails closed. A malformed answer raises naming the module.
- It runs whenever the page's assigns come in — on mount and on every later
  render of the parent LiveView — and the types' callbacks have already run
  with the original `config_data` by then, so assigns it merges are the
  page's, not theirs.

## v0.11.0

### Reviews notice when the reviewed form changes

A review now records what it reviewed, and says so when that form has moved
on since. Submitting a review of Intake writes the form it reviewed into the
`snapshot_data` of the review's own `status_changed` event, under
`"reviewed"`: the related-form property value as stored (`"path"`), the
source instance's id and pinned version id, its `completed_at`, and a copy of
its answers as rendered (`"data"`). Structure by reference, answers by copy:
the version is immutable, but the source can be resubmitted, reconciled, or
deleted, and a review that carries its own record is stronger evidence than
one reconstructed by joining other tables. A source that did not resolve, or
had not been started, records `"instance_id" => nil` — that nothing was
reviewed is itself on record.

At render, on Show and on a reopened Edit alike, the review type reads that
record and the source instance's event trail and calls the review stale when
the source has any event newer than the review's completion. The headline is
the latest thing that happened — "Intake was submitted again on {date}, after
this review", "Intake is being edited — reopened on {date}, not yet
resubmitted", "Intake's form changed after this review (a new version was
published)", "The Intake reviewed here was replaced", "The Intake reviewed
here has been deleted" — with a diff of the recorded answers against the
source's current ones where one makes sense (Name: Ada → Grace), titled from
the pinned definitions, and a caveat when the form's structure also changed
since the review. A current review says "Reviewed {date}. Unchanged since."
Staleness is information, never action: nothing is reopened, blocked, or
sent. The review stays editable on Edit in every state; resubmitting it
writes a fresh record, which is how it becomes current again.
`FormFlow.Web.Components.Forms.Types.Review.staleness/4` and `diff/4` are
pure and public.

- **`FormFlow.Config.Forms.Type` goes from two callbacks to five.** New:
  `snapshot_data/2` — what to record on the form's completion event,
  `%{}` for nothing; runs before the completion is written, so an error
  refuses the submit rather than completing a form without its record.
  `handle_complete/2` — called after the completion with a context derived
  fresh (`:form_instance` the completed row), the moment a host reacts at;
  its return is ignored and an error is logged and never undoes the
  completion. It shares its name with the flow type's `handle_complete/2`,
  which receives the same fresh context and answers where the user goes
  next. `show_component/1` — the Show page's answers, drawn read-only; the
  default is the disabled fieldset Show rendered itself before, and Show now
  renders through the form type, which it never consulted until now. All
  three have defaults in `FormFlow.Config.Forms.Type.Default`.
- The edit page's submit path derives the fresh context once and hands it to
  both `handle_complete/2`s. Both new callbacks are rescued at the call site:
  a raising `snapshot_data/2` shows the page's error and completes
  nothing; a raising `handle_complete/2` is logged (`Logger`, a first use in
  the library) after a completion that stands.
- **New: `FormFlow.Data.Instances.Forms.list_events/2`** — an instance's
  event trail, oldest first, `event:` filtering by kind — and
  **`latest_event/2`**, the newest of a kind or nil.
- **New: `FormFlow.Data.Instances.Forms.redact_snapshots/1`** blanks the
  answers in every review snapshot that references an instance and stamps
  `"redacted_at"` — the one sanctioned update of an event row, stated as the
  exception in `FormFlow.Data.Instances.Form.Event`'s docs. `delete_instance/2`
  runs it inside its transaction before deleting, so a failed redaction
  aborts the deletion; `redact: false` skips it, which is what
  `FormFlow.Data.Instances.Flows.delete_instance/2` passes, since a journey's
  deletion takes every copy with it. A redacted review says "Reviewed
  {date}. The record of what was reviewed has been erased."
- `reopened` events have two writers, now documented: a user's reopen, and
  the `:reopen_carry` / `:reopen_reset` publish policies, the latter with
  both version ids set. The staleness rules read `to_version_id` to tell
  them apart.
- A host that cannot hold duplicated personal data overrides
  `snapshot_data/2` in its own review type to store identifiers only;
  there is no configuration option for it.

### The review form type

**New: `FormFlow.Web.Components.Forms.Types.Review`**, a form type for
checking an earlier form's answers: the edit page shows that form read-only on
the left — the way the Show page renders submitted answers — and the review
form itself, editable, on the right. Which form is its one property,
`"source"`, a `:related_form` picked on the form edit page; at render it
resolves to that form as it stands in the flow instance. A source that doesn't
resolve — unset, blank, or a path the flow no longer has, however that came
about — is one error with one fix, an administrator choosing again: the review
page says the form to review is missing, the form edit page notes that the
saved choice is no longer in the flow, and Show renders it as missing. A
source the user hasn't reached yet is not an error and says that instead.
Paths are never guessed at: rearranging a flow under a review form is a
configuration problem to surface, not one to paper over.

- `FormFlow.Config.Default.enabled_form_types/2` now enables two types,
  `"default"` (the form as designed, first — so the fallback for a form that
  never chose) and `"review"`, so every form edit page has a "Form type"
  dropdown. A host config extends the list the same way it extends the flow
  types.
- **New: `edit_component/1` on `FormFlow.Config.Forms.Type`** — the edit
  page's form, drawn. Its assigns are `DynamicForm.form/1`'s plus `:context`
  and `:config_data`; the default renders the form alone, and a type that
  draws more around it renders the form itself by calling the default.
- **New: `FormFlow.Config.Forms.Type.related_form/2`** resolves a
  `:related_form` property value to the `FormProgress` at that path in the
  flow instance, and `FormFlow.Context` gained `:flow_instance_progress` —
  every form of the whole flow instance, in order — which is where it looks.

### Form types on the canvas

A form node on the canvas now carries its form's type the way a form subflow
node carries its flow's: a dropdown in edit mode, the type's name in show
mode, populated from `enabled_form_types/2` with the flow as the context. The
form lineage's `properties["form_type"]` stays the single stored copy —
`FormFlow.Web.Helpers.ReactFlow.to_data/1` projects it into the node's
`data.form_type` on load, and `FormFlow.Data.Templates.Flows.update/2` pops
it out and writes it through on save — and the canvas edits only the type: a
type's properties are set on the form's own page. `FormFlow.Web.Components.Editor`
takes `form_type_options`; the editor bundle was rebuilt.

- Writing a *changed* type through from the canvas, for flows and forms
  alike, drops the property values entered for the old type, since they
  belonged to it; the same type again keeps them.

### Type properties

A flow or form type can now ask an admin for settings. `FormFlow.Config.Property`
is one such setting's definition — `id`, `name`, `description`, `type`,
`options`, `required`, `default_value` — and a `FormFlow.Config.Flows.Type`
or `FormFlow.Config.Forms.Type` declares its list under `:properties`. The
types are `DynamicForm`'s question types by the same names — `:text`,
`:comment` (a textarea), `:dropdown`, `:radiogroup`, `:checkbox` (a group,
list-valued), `:boolean` (a single checkbox) — plus `:number`, a text input
that casts to a `Decimal`. The three choice types take `:options` as
`[{label, value}]`.

Two words, used strictly: a type's **properties** are these definitions; the
**property values** are what an admin entered for them.

One more type, `:related_form`, points at another form of the same flow — for
a type whose behavior involves one, like a review form showing an earlier
form's answers. It renders as a dropdown the library fills from the flow: the
forms *earlier* than the one being edited, in the order a user works them,
labeled as the user-facing pages label them. The stored value is the chosen
form's path (node ids from the root, joined with `/`), which identifies one
position even when a reusable form or subflow appears twice. A form has no
earlier forms until it sits in a flow, so on a catalog form the field says so
and offers nothing.

- The flow and form edit pages render one field per property of the *pending*
  type, right under the type dropdown; picking a different type swaps them.
  Values save with the rest of the identity form and ride the same
  unsaved-changes tracking; a required property blocks Save without a value.
  Switching types drops the previous type's values. Show pages render each
  value beside the type's name — a choice by its label, a list joined, a
  boolean as Yes or No. The canvas's form subflow nodes still pick only the
  type — a subflow's properties are set on its own page.
- Values are stored on the template under the type's own key:
  `properties["form_type_property_values"]` on a form and
  `properties["form_flow_type_property_values"]` on a flow, a map keyed by
  property key. **New: `FormFlow.Config.Forms.Type.property_values/1`** and
  **`FormFlow.Config.Flows.Type.property_values/1`** read them back, and
  `FormFlow.Context` carries the same maps as `:form_type_property_values`
  and `:flow_type_property_values`, so a type's callbacks can read either.
- The demo's `"demo_prefill"` form type declares three properties — the name
  it prefills with, a salutation dropdown, and a related form — and reads the
  first two in `initial_data/2`.

### Form edit page: "Save draft"

The form edit page's header button says "Save draft" rather than "Save": it
sits beside Publish, and what it saves is the draft.

## v0.10.0

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
  or keep working on it), `handle_complete/2` (the next form after finishing it,
  or `nil` to hand back to the flow instance), and `progress_component/1`
  (the progress drawn above the form — `nil` draws nothing, which is what the
  old `show_progress?/1` decided). `openable?/2` is `editable?/2` and
  `next_form/2` is `handle_complete/2`.
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
- **New: `FormFlow.Config.Default`, `FormFlow.Config.Flows.Type.Default`,
  and `FormFlow.Config.Forms.Type.Default`** — the public face of each
  behaviour's defaults, for a host's override to call when it extends a
  default rather than replaces it. Each is a straight pass-through to the
  implementation under `FormFlow.Web.Components`.
- **Breaking: `FormFlow.Config.Context` is `FormFlow.Context`.**
- **New: form types.** `FormFlow.Config.Forms.Type` is the form-side
  counterpart of the flow type: `enabled_form_types/2` returns its structs,
  a form stores the chosen one, and the type's module decides how the form
  behaves for a user. Its first callback is `initial_data/2` — the data the
  edit page renders the form with, keys being the definition's question
  names. The default (`FormFlow.Web.Components.Forms.Types.Default`) returns
  the user's stored answers; a host type that prefills from its own
  database merges those over its values, the same way a custom config module
  reaches `FormFlow.Config`'s defaults. It runs when the edit page mounts,
  so it covers the first start and every later visit alike. The library
  enables no form types itself: with none enabled every form gets the
  default and the form edit page shows no dropdown, so the feature is
  entirely opt-in.
- **Breaking: `form_flow_template_forms` gained a `properties` column** (a
  map, like flows'), rewritten into the initial schema pre-release style —
  drop and recreate any existing database. The chosen type is stored under
  `properties["form_type"]`; absent means the first enabled type, or the
  default. The form edit page's identity form carries a "Form type" dropdown
  populated from `enabled_form_types/2` when it returns anything, Show
  renders the stored value as its name, and `FormFlow.Web.Router` now
  forwards `config` and `config_data` to the form pages.
- `FormFlow.Context` gained `:form_instance` — the user's answers so far at
  the form in question, or `nil` until they start it.
- **Breaking: the flow type's `on_complete/2` is `handle_complete/2`**,
  following the `handle_*` convention for callbacks the library invokes.
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
