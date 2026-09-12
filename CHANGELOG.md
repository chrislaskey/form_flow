# Changelog

## v0.25.0

### Every page that draws a form can fill it in

The form pages draw the form's prefills over the form they render
(`FormFlow.Web.Components.Forms.PrefillPicker`): a searchable select of the
sets saved against this form — placeholder **Prefill** — and a **⋮** menu of
New prefill, Edit prefill, Capture prefill, and Delete prefill, each writing
through `FormFlow.Web.Components.Forms.PrefillDialog` (a name, and the
answers as the JSON object of question names to values they are stored as).
Choosing one fills the form in, so a definition can be looked at with answers
in it instead of empty, and `FormFlow.Web.Templates.Forms.Preview` takes
those answers as the `"data"` key of its session. What the three pages agree
on about writing one is `FormFlow.Web.Components.Forms.Prefills`.

**Capture prefill** goes the other way: fill the preview in by hand and press
it, and the answers on screen open the same dialog, ready to save — with the
selected prefill's name, so it writes over that one, or empty, so it writes a
new one. Capture is not a third way to save a prefill; it is New or Edit with
the answers already there, which is why it opens the dialog rather than
writing straight away. Which form it reads is an explicit attr, because a
template page draws two and the editor's own fields are the definition rather
than answers: it is always the preview's
(`FormFlow.Web.Templates.Forms.Preview.form_id/1`), and on a form instance it
is the form the user is filling in.

It reads the rendered `<form>` in the browser and pushes it as the body a
submit would send, decoded with `Plug.Conn.Query`. That is one mechanism for
a page whose form is in a child LiveView and a page whose form is in its own
process, and it captures what is on screen exactly — invalid answers
included, since a form is tested with bad answers as often as good ones. What
the browser hands over is what it would submit, so an unchecked box or a
disabled question is missing rather than empty and a question hidden by a
condition is present; the dialog says so.

Three pages have it. `FormFlow.Web.Templates.Forms.Edit` is where a draft is
written; `FormFlow.Web.Templates.Forms.Show` has it too, because a prefill
belongs to the form rather than to a version — a form with everything
published has no draft to edit, and so no edit page, and this is where it
keeps them. `FormFlow.Web.Instances.Forms.Edit` has the whole of it while its
flow is a `draft` or in `pre_release`
(`FormFlow.Web.Instances.Forms.Shared.prefills_offered?/1`): the answers a
prefill supplies are merged *under* the user's own, so filling a form in can
never replace something they typed, and nothing is stored until they submit.
Capture earns its place here — a journey walked by hand is the cheapest way
to reach an interesting set of answers, and it is saved where it was reached
rather than rebuilt on an admin page.

Applying a prefill is ungated, as it was: the answers land in the user's own
form and are values they could have typed. **Writing** one is guarded on that
same status behind the menu, because a prefill is readable by everyone who
can reach the form — there is no per-user set, and nothing hides one. The
dialog says so where the answers are typed, which is the whole of the
protection. Who may write one in an `open` flow is not answered yet.

The selection lives in the URL (`?prefill=Happy+path`), so it survives a
refresh and can be handed to someone else as a link. That makes choosing one
a navigation, which a draft holding unsaved editor content would lose — so
the page asks first, the way the flow canvas asks before a breadcrumb
discards an edit, and the dialog's **Save & Continue** is the editor's own
submit button, with the navigation waiting for the save to land.

Writing a prefill never touches the draft: prefills belong to the form.
Creating one selects it and renaming one follows the new name, both
navigations; deleting one leaves the URL naming a prefill that is not there,
which selects nothing — the same state a link to a prefill someone else
deleted arrives in.

### A form carries prefills for testing

A form template now has a `prefills` column: the named sets of test answers
an admin saves to fill the form with while trying it out — a map of the name
they typed to an entry holding that set's `data`, keyed by the definition's
question names the way a form instance's answers are.
`FormFlow.Data.Templates.Form.Prefill` is one entry, and
`FormFlow.Data.Templates.Forms` reads and writes them:
`list_prefills/1`, `get_prefill/2`, `create_prefill/2`, `update_prefill/3`,
`delete_prefill/2`. A name is a form's own handle, so saving a second
prefill under one it already has is refused, and updating under another name
is how one is renamed.

They live on the **lineage**, not on a version, because prefills are not
version specific: one set travels with the form through every publish, and
an older set applied to a newer definition leaves its new questions blank —
which is the point, since those blanks are what a user sees when a
definition moves under them. `Forms.copy/2` carries the set, so a form
rolled over for next year opens with last year's answers.

The column is its own, not a key in `properties` — that map is the host's
open domain data — and it moves only through `Form.prefills_changeset/2`,
so an ordinary form update cannot drop it. The whole set is one value: a
write rewrites it, and the last write wins.

### A new catalog form starts the way a step's form does

Creating a form from the catalog used to end on the form's page, with a
blank draft waiting to be found and edited separately: the details first,
then, on another page, the definition. `FormFlow.Web.Templates.Forms.New`
now lands on that blank draft's edit page instead, which opens on the same
choice a step's new form gets — Custom form, or Copy form — and then edits
the details and the definition together, the way a step's form does until
it is first published. The name typed on the New page is the start of the
form, not the end of creating it.

### From the catalog, Copy offers every form

The chooser's Copy form and the editor's Copy existing form listed only the
catalog when opened from the catalog, so a catalog form could be started
from another catalog form but never from the form a step already had. Both
now offer **every form**: the catalog first, by name, then each flow's
steps, flow by flow — "Dog License - Application / About your dog
(about-your-dog)" — the way a step's own page names the current flow's
forms. A catalog form a step reuses is offered once, from the catalog.
Archived flows are left out, as the flows index leaves them out. Through a
step the list is as it was: the current flow's forms, then the catalog.

### The templates landing says what the catalog is for

The admin landing's second link reads **Reusable forms**, not "Forms", and
the line under it says what the catalog is for: a catalogue of reusable
forms that can be used in multiple flows and kept in sync.

### The data model has a guide

`guides/data-modeling.md` is the demo's `/docs/data-modeling` page as a
guide: Flows and Forms, templates and instances, the ten tables the
migration creates, the three that cross over to Neo4j, and the three ways a
graph can be read back out of SQL — with screenshots of the two diagrams the
page draws, and a pointer to the demo for the interactive versions. The
Neo4j guide stays what it was, the mapping itself.

## v0.24.0

### Every table says whether it holds a template or an instance

Ten of FormFlow's eleven tables are named `form_flow_<scope>_<subject>`,
where the scope is `template` or `instance` — the split
`FormFlow.Data.Templates` and `FormFlow.Data.Instances` draw in the module
tree. Four tables were not: the flow template's own tables carried no scope
segment at all, so `form_flow_flows` sat next to `form_flow_instance_flows`
saying nothing about which side of the line it was on, and `form_flow_nodes`
and `form_flow_relationships` read as though they belonged to the schema at
large rather than to a flow template. They now say it:

| Before | After |
|--------|-------|
| `form_flow_flows` | `form_flow_template_flows` |
| `form_flow_flow_events` | `form_flow_template_flow_events` |
| `form_flow_nodes` | `form_flow_template_flow_nodes` |
| `form_flow_relationships` | `form_flow_template_flow_relationships` |

No columns changed, and the `"flow_id"` and `"tenant_id"` keys the schemas
copy into `properties` for the Neo4j dual-write are untouched. The eleventh
table is neither a template nor an instance — it records which version of the
migration has run — and says so: **`form_flow_migrations` is now
`form_flow_database_migrations`**. It is created by
`FormFlow.Data.Migrations.Version`, which reads the applied version out of it;
a database migrated by an earlier release has the old table, and reads as
never migrated.

**One index is named in the migration rather than derived.** The unique index
on `form_flow_template_flow_relationships` over `source_id`, `target_id`, and
`label` is now
`form_flow_template_flow_relationships_source_target_label_index` — the name
Ecto derives from the columns is 69 characters, past Postgres's 63-byte
identifier limit, and Postgres would have truncated it silently out of step
with the name the changeset maps errors from.
`FormFlow.Data.Templates.Flow.Relationship` declares both that name and the
one Ecto derives, because SQLite cannot report which index a violation came
from and its adapter rebuilds Ecto's name from the columns in the error.

### Three columns say which side of the line they point at

The same rule the table names now follow, applied to the columns that broke
it. Nothing else changed: `flow_id`, `subflow_id`, `form_id`, `tenant_id` and
`slug` on `form_flow_template_flow_nodes` are dual-written into `properties`
for Neo4j, so renaming one would orphan stored property data — which is why
the `form_id`/`template_form_id` split below is settled in the direction it
is.

| Table | Before | After |
|-------|--------|-------|
| `form_flow_instance_flows` | `flow_id` | `template_flow_id` |
| `form_flow_template_form_versions` | `template_form_id` | `form_id` |
| `form_flow_instance_form_events` | `snapshot_data` | `snapshot` |

**A journey's flow is a template flow, and now says so.** On an instance row
a bare `flow_id` sat next to the `instance_flow_id` used everywhere else and
pointed at neither of the obvious things. Its association renames with it:
`belongs_to(:template_flow, Templates.Flow)`, so
`FormFlow.Data.Instances.Flows.list/1` preloads `:template_flow`, a listing
that preloads its own asks for `preload: [:template_flow]`, and
`Instances.Flows.create/2` takes `template_flow_id` in its attrs.

**A version belongs to a form.** `template_form_id` becomes `form_id`, and
its association `:template_form` becomes `:form` — matching
`form_flow_template_flow_nodes.form_id`, which points at the same table and
cannot move. The unique index follows to
`form_flow_template_form_versions_form_id_version_index`.

**One name for one payload.** `snapshot_data` was the same free-form map that
both event logs already call `snapshot`. The column, the field, and the
things named after it move together: the `FormFlow.Config.Forms.Type`
callback **`snapshot_data/2` is now `snapshot/2`** (a form type that
implements it renames the function), and the `snapshot_data:` option of
`FormFlow.Data.Instances.Forms.complete/4` is now `snapshot:`.

The rule the three leave behind: on the template side a bare `flow_id` or
`form_id` means the template; on the instance side every reference is
qualified — `template_flow_id`, `template_form_version_id`,
`instance_flow_id`, `instance_form_id`. Role names on self-references
(`owner_flow_id`, `copied_from_form_id`, `based_on_version_id`,
`subflow_id`) keep their roles.

### A node and a relationship carry their own id in `properties`

`FormFlow.Data.Templates.Flow.Node` and
`FormFlow.Data.Templates.Flow.Relationship` already dual-wrote their
infrastructure columns into `properties`, the map that becomes the Neo4j
property map — everything except the row's own `id`, which meant a Cypher
query could match a flow by id (`(:Flow {id: $id})`) but a node only by
`slug` or `flow_id`. Both now copy `id` as well, so every record in the
future graph is addressable by the id the rest of the system knows it by.

The copy travels **one way only**: the column is authoritative, a stale
`"id"` arriving in `properties` is overwritten from it, and nothing reads it
back into the column — so no round-trip through the editor and no copy or
paste can re-point a record at another record's identity. A flow copy is the
case that proves it: the copied node's `properties` are the source's, `id`
included, and the changeset overwrites it with the copy's own.

**Ids for new records are now minted in the changeset** rather than by the
adapter at insert, since a copy of a column that does not exist yet is no
copy at all. A caller-supplied id still wins, and a loaded record keeps the
id it has.

Stored rows written before this change have no `"id"` in `properties` until
they are next written — which for nodes and relationships is the next save of
their flow, since `Flows.update/2` replaces them wholesale.

**The migration is edited in place, not superseded.** `version: 1` creates
the tables and columns under their new names; there is no rename migration. A
database migrated by an earlier release has the old ones and is not carried
over.

### Destructive actions are ghost buttons, and a bare Delete is its icon

**Delete**, **Delete draft**, and **Discard changes** were solid red, which
made the most dangerous thing on a page the loudest. They are now
`btn btn-error btn-ghost`: transparent until hovered, where the red returns.
Where the label was the single word **Delete** — a form's own page and a
flow's — the button is the waste basket alone, labelled for screen readers
and for a tooltip; the ones that say what they delete keep their words.
The basket is drawn through `Core.icon`, which is new: it dispatches
`icon/1` the way the rest of `FormFlow.Web.Components.Core` dispatches
buttons and badges, so **a host's own `icon/1` draws FormFlow's icons** and
its delete icon is the one these pages show. The name passed is Heroicons'
(`hero-trash`); a host with no `icon/1` of its own falls back to
`FormFlow.Web.CoreComponents.icon/1`, which emits the class name and leaves
the drawing to the `hero-*` classes the host's Tailwind build generates.
The full width toggle's arrows go the same way
(`hero-arrows-pointing-out`/`-in`), and so does anything FormFlow draws
that Heroicons has a name for. The health badge's **stethoscope is the
exception, and a clause of `Core.icon` itself**: Heroicons has none, and a
host's `icon/1` written for `hero-*` names would raise on the name, so it
never leaves FormFlow.

### The form edit page is one column beside its preview, and the preview can take the width

**Form details** and **Form version** share a single column again — the
identity fields no longer run the full width above the version — and the
**Preview** is the column beside them, 60/40 from `lg` up. The form's column
stops at `max-w-3xl` — fields stop widening where a form stops being
readable — and the preview takes the slack a wide screen leaves.

**The preview's heading has a Full width toggle**, beside Auto-refresh. It
drops the column split: the preview moves to the top of the page at the
page's width, with the whole form underneath it, and it lets go of the
sticky positioning and the scroll container it wears beside the form, since
a preview given the width is meant to run as tall as the form it shows. The
toggle is view state — it is not saved with the draft, and a reload comes
back beside the form. Going full width also scrolls the preview back into
view, since an admin deep in the elements would otherwise be left below a
preview that had moved to the top of the page; coming back does not, the
column it returns to being sticky. The scroll is a colocated hook on a
marker that exists only in the wide state, so it runs once the new layout
is in the DOM, and it is smooth unless the browser asks for reduced
motion.

**The preview sits on a canvas**, the dotted surface the flow editor draws
at the same 16px pitch, with the form on it as a card at `max-w-3xl` — so
going full width grows the canvas around the form rather than stretching
the form. **A version with no elements previews as "Nothing to preview
yet"** and a line saying how to fill it, rather than as a form whose only
control is Submit. A definition that will not parse still reaches the
preview, which says what is wrong with it.

Both are `FormFlow.Web.Templates.Forms.Components.Canvas`, and the form's
**show page previews on the same canvas** — it takes the definition as the
map a saved version carries where the edit page hands it the JSON string
its editor holds.

### Form details have their own page once a form has been published

A form's **details** — its name, slug, description, and type with the
type's property values — belong to the lineage, not to a version: they
change the moment they are saved, and every version shows the change,
published ones included. The draft editor had them above the definition
under one Save, which read as if they were part of the draft. Now the
editor **carries the details only until the form is first published**.
After that, where the Form details section was, the page says the details
are shared by every version and links to **Edit form details** —
`FormFlow.Web.Templates.Forms.Details`, a new page at `/forms/:id/edit`
and `/flows/:root/nodes/:node_id/form/edit`. It has the same fields, its
own Save, a banner saying a save reaches every version at once, and a link
back to the form's page, where drafts are. A save on the draft editor of a
published form writes the definition and nothing else; a value for a
detail in the request is not a field of the page and is ignored.

**The show page lists the details** as a fact sheet under the header, four
to a row — name, slug, description, type, and the type's property values, with the
step's name and slug through a node, the way the fields that edit them
read — and its header has **Edit form details**, which leads to the new
page at any time, published or not. **New draft from this version is
primary while there is no draft** to continue; beside Continue editing
latest draft it stays plain.

`FormFlow.Web.Templates.Forms.Shared` is new: the data the details fields
read and write — the form data, the saved baseline `dirty?` compares
against, the save that writes each value to its owner (the step's name and
slug to the node, the rest to the form row), and the labels — so the two
pages that edit them agree on what a save does. The version editor's
`type_callout` and `section_heading` moved there with it.

Both pages say this in a **Note** — `FormFlow.Web.Templates.Components.Note`,
new: a bordered white card the width of the page opening with **Note:**,
rather than an alert — above the form on the draft editor, so it does not
sit inside the form's column, and above the fields on the details page.

### The flow's fields are three to a row, and the show page lists them

**A flow's edit page lays its own fields out in two `DynamicForm` groups**
under the canvas instead of one narrow stack: who the flow is — name, slug,
status — then what it is — form flow type, perspectives, and the type's
properties, wrapping three to a row. The page lays the groups out from
outside the form, by the `data-dynamic-form-group` attribute the library
stamps on each: a three-column grid in place of the library's content-sized
flex row, so every member takes exactly a column, stacking to one column
below `md`. The status summary sits between the two groups at the page's
width. It is what splits them: an owned subflow has no status, so its
fields are one group and fill each row in turn rather than leaving a
column empty after name and slug.

**A flow's show page lists the same fields under the canvas**, in the same
three-column layout, read rather than edited — name, slug, status with its
summary, type, perspectives, and each of the type's properties, a dash for
one without a value. Through a node the name and slug are the step's, as
the edit page's fields are. The header's metadata line keeps the type,
properties, and perspectives it already showed.

### A choice that decides the page is a card, not a row of radios

`FormFlow.Web.Templates.Components.ChoiceCard` is new: one radio drawn as a
card carrying its name, a line under it saying what picking it does, and a
fill when it is the one picked. It is for the choices a page makes a
decision out of rather than collects an answer to, where the options differ
in consequence and not just in kind — a row of plain radios cannot say so
before the click, and one of the draft editor's three replaces the whole
definition.

**The draft editor's editor picker is the first of them.** It is still the
same radio group: `definition_editor` keeps its `options`, so the changeset
validates it exactly as before, and `visible_if` reads it exactly as
before. Only the control is FormFlow's, through a `DynamicForm` `<:field>`
with a body — the documented escape hatch, where the library keeps the
label, the errors, and the validation while the page draws the control. The
three descriptions and the radio's values come from one list, so the cards
and the values the changeset accepts cannot drift. The picker carries no
label of its own (`label={false}`): three cards that each describe
themselves need no sentence over them.

**The New flow page's kind picker is the second**, and the reason the card
is a component rather than markup on one page — the two now cannot drift
apart. Those cards had no picked state at all before.

The fill is daisyUI's **`primary`**, so a card wears the host application's
brand color rather than one of FormFlow's own, and the description follows
the card's text color into it as `opacity` rather than as a second palette
that would have to be picked for every theme a host might set.

### The draft editor says which draft, and what the fields are

**Form version** is now **Draft**, and the strip that sat under it has moved
into it: what the draft is based on, and when it was last saved, as both
"2 hours ago" and `2026-09-11 at 4:21pm UTC` — the relative phrase for the
glance, the absolute one for the record. **Form version elements** is now
**Form fields**.

**The notes moved to where the fields they talk about were.** The note
saying the form's details are global and edited on their own page was above
the form, at the page's width; it is now in the version group, under the
Draft heading, where the details fields sat until the form was published.
The link that said how many other drafts exist joins it as a note of its
own rather than as a sentence trailing the heading.

**An element leads with its name and its label.** The builder's first row
was Type and Name with the label below; it is now Name and Label, with the
type dropdown on its own row under them — what an element *is called* before
what it *is*. The group renames with it, `type_and_name` to `name_and_label`.

### Every label is `text-sm`, including the ones another library draws

The `dt` labels on the flow and form show pages and the health page, the
fact-sheet and section headings, the fieldset legends, and the checkbox
input's own label were `text-xs` while the values beside them were `text-sm`.
They are all `text-sm` now.

**Three of them were not FormFlow's to set.** `DynamicForm` renders inputs
through the components module it is given, per function, and
`FormFlow.Web.CoreComponents` defined `input/1` but not the rest — so text,
select and textarea labels were FormFlow's while radio groups, checkbox
groups and custom controls fell back to the library's own, which sit inside
a daisyUI `.fieldset` and inherit its `0.75rem`. One field on a page drawn
smaller than every other. `FormFlow.Web.CoreComponents` now also defines
**`input_radio_group/1`**, **`input_checkbox_group/1`** and **`label/1`** —
the named functions `DynamicForm.ComponentResolver` looks for — so every
label FormFlow draws is the same size, wherever it is drawn from. A host
that passes its own components module is unaffected: the resolver asks that
module first, as it always did.

### The flows index filters, and an id is a column

**A Filters tab over status, name, and slug.** Slab compiles the
`filter[...]` URL params into WHERE conditions: status is a select of the
statuses, name and slug are case-insensitive contains. Like the sort and the
page they live in the URL, so a filtered listing survives a reload and can
be sent to someone. **Archived is off the status filter's options while
archived flows are hidden** — the rows already exclude them, so picking it
could only empty the table; **Show archived** puts it back.

**The id has its own column and the slug sits under the name.** The id was a
grey line beneath the name and the slug was a column of its own; they have
swapped. The slug column's sort goes with it — the name's remains.

## v0.23.0

### Renewing from last year, and the rest of the status work

**Last year's answers, this year.** `FormFlow.Data.Instances.Flows.list_query/1`
and `list/1` take **`status:`** — the journey's own stamp, `"in_progress"`
or `"completed"`, not the flow's — so a host that stamps journeys
(`Instances.Flows.complete/2`, which nothing in the library calls yet) can
ask for a user's finished ones. The demo's new **`"demo_renewal"`** form
type (`DemoWeb.FormFlowLive.Renewal`) is the worked example the guide's
"Years, pre-release, and closing a flow" section now gives: from this
year's form to last year's lineage through `copied_from_form_id`, to last
year's flow through the lineage's `owner_flow_id`, to the user's journeys
in it with `list/1`, and to the form they *submitted* there, whose answers
it offers under the user's own from `initial_data/2`; a year the user
skipped is walked past. It reads the form's completion, not the journey's
stamp, and says why.

**Pre-release users can be a rule, not a list**: `pre_release_user_ids`
takes a function of the page's `FormFlow.Context` and `callback_data`
returning the list — `[context.user_id]` when the viewer qualifies, `[]`
when not — as well as a list; each page resolves it once, as soon as it
has a context (**`FormFlow.Web.Instances.Shared.resolve_pre_release_user_ids/1`**),
and the context is the page's, with no flow in it, so the rule is per page.
`FormFlow.Web.Instances.Shared.status_allows?/3` reads two keys of the
map it is given — `user_id`, and `pre_release_user_ids` as a list — so a
host's own route asks it with a bare map; asked about a pre-release flow
before the attr is resolved it raises rather than guesses. **As a flow
leaves Pre-release, the status dialog offers to delete the trial run**: it
says how many instances were started during pre-release (the marker in
`metadata`, read by the new `FormFlow.Data.Instances.Flow.pre_release?/1`
and listed by **`Instances.Flows.list_pre_release/1`**) and draws a box,
Delete them, unticked; Save with the box calls
**`Instances.Flows.delete_pre_release/2`**, which deletes each through
`delete_instance/2` and logs one **`pre_release_instances_deleted`** event
with the count, in one transaction (`FormFlow.Web.Templates.Shared.save_status/3`
is the dialog's Save, for both pages; the status write and the deletion
are two transactions, and its message says so if the second fails). The
offer is made for that one move only; on any other the box is ignored.
The Edit page's Status field makes no such offer.

**The flows index puts archived flows away**: the listing filters them out
(`Flows.roots_query/1` takes **`status:`** and **`exclude_status:`**) and
says how many are hidden with a **Show archived** link, which patches
`?archived=true` onto the page's URL — sort kept, page dropped — and lists
them greyed, with Hide archived to go back; a listing of nothing but
archived flows says "Every flow here is archived." and offers the link.
**`Flows.get_row/1`** fetches a flow's row without its tree, for the
clicks on the user-facing pages that want its status alone.

**Ignoring a health entry is logged**: `Health.ignore/3` and
**`Health.stop_ignoring/3`** (breaking: it takes the admin's `user_id` now,
as `ignore/3` always did) each write an event on the flow's log in the
same transaction as the record — **`health_ignored`** and
**`health_unignored`**, with the entry's `code`, `path`, and `subject` in
`snapshot` — and the History page reads them as "Ignored health check:
form not published at Intake", the check named as the health page names it
(**`FormFlow.Web.Templates.Shared.check_name/1`**). `Health.check/2` given
an owned subflow's id now checks its root, so a report — and what is
ignored from it — always lands on the root, as `refresh/2` already did.
The health page passes its `user_id` to both. The status dialog's dropdown
is a `select` through `FormFlow.Web.Components.Core.input/1`, which grew
`options` and `prompt` for it, so a host's `components` module draws it.

## v0.22.0

### A flow has a status, and a log of how it got there

**`FormFlow.Data.Templates.Flow.status`** says what users may do with a
flow — three facts: may they **start** a new instance, **continue** one
already started, **see** their instances at all — and a status is the set
it allows. Six values, the schema's table: **`draft`** (born this way; not
offered, and hidden — nobody starts, continues, or sees),
**`pre_release`** (open to the users a page names in the router's new
**`pre_release_user_ids`** attr, a draft to everyone else; a journey
started meanwhile carries `"form_flow" => %{"pre_release" => true}` in its
`metadata`), **`open`** (the
normal state), **`winding_down`** (no new starts; anyone in it finishes and
keeps seeing it), **`read_only`** (nothing changes; everyone still sees,
prints, and downloads their own), **`archived`** (put away; users see
nothing, admins keep everything). Transitions are any-to-any:
**`Flows.update_status/3`** moves a flow to any status the table names,
refusing only an unknown one (`{:error, :unknown_status}`) or a flow
deleted since it was loaded (`{:error, :not_found}`), and the same status
again is a no-op. `Flow.allows?/2` and `Flow.statuses_allowing/1`
are how pages and queries ask.

Every move is logged. **`FormFlow.Data.Templates.Flow.Event`**
(`form_flow_flow_events`) is the template side's append-only audit trail,
the third of its kind after the two instance logs and under their
discipline — the responsible `user_id`, a free-form `snapshot`, rows never
updated, a `:restrict` foreign key, deleted deliberately by
`Flows.delete/1` before the flow. `Flows.create/2` (new `opts`, `user_id:`)
writes `created` for the root it makes, `Flows.copy/2` does the same for
the copy (and takes `user_id:` too), and `update_status/3` writes
`status_changed` with `"from"` and `"to"`. Events are audit, not state:
nothing reads the log to decide what a page does.

**A copy is a draft**, whatever its source's status.

**On the user-facing side**, the status is the pages' rule and not the
data layer's: `FormFlow.Data.Instances.Flows.create/2` and
`FormFlow.Data.Instances.Forms.update_status/4` do what they are asked, so
a host's admin and support tooling can repair state without a back door,
and a host route that should honour the status asks `Flow.allows?/2`
first, as the pages do — the listing asks again at the click, from the
row as it now is, and so do Reopen on the instance page and the form's
show page. `Flow.allows?/2` answers the table; the pages ask
**`FormFlow.Web.Instances.Shared.status_allows?/3`**, which adds the one
rule about a person — who a pre-release flow's users are — and a host
route honouring the status does the same for that status.
**`Instances.Flows.narrow_allowed/2`** narrows a listing query to instances
of flows whose status allows `:start`, `:continue`, or `:see`. A read-only
flow's instances are listed as View,
their pages open, and their form edit pages say "This flow is read-only
now; your answers are kept as they are." — Continue and Reopen are not
drawn, and a form type's `editable?/2` is never asked. The
instances index offers Start for open flows — and pre-release ones, to the
users the page names — lists a winding-down flow
the page is about with "No longer taking new starts." in place of its
button, applies `:see` on top of whatever it lists (the host's query
included, the way it applies the tenant), says "No flows are open." when
nothing is (it used to say "No flows have been published yet."), and
answers a stale click with "That flow is no longer taking new starts.".
Every instance page refuses an instance of a flow nobody may see with
"This flow is not available right now.", before the host's `on_mount`.

**On the admin side**, the flow's fields form under the Edit page's canvas
gains a **Status** dropdown for root flows, with a summary of the chosen
status under it — what users can do, and how many instances the change
reaches (**`Flows.instance_counts/1`**, the flow-level twin of the forms
function) — redrawn as the choice is made, the way the form edit page
explains its type. A changed status is an unsaved edit like any other and
is written by Save through `update_status/3`, signed by the page's
`user_id`; an unchanged one writes nothing. The Show page's header and the
flows index draw the status as a badge whose title is the same summary —
and both change it too: the header's badge opens a dialog
(**`FormFlow.Web.Templates.Flows.Components.StatusDialog`**), the index's
⋮ row menu has **Change status**, each a dropdown with the same summary
and counts under it, saved on the click through `update_status/3`.
The router now passes **`user_id`** to every template component — the
flows pages, where the event has an author wherever it is written, and the
forms pages, for the events they will write; a host rendering the
components itself should pass it too.

Owned subflows have no log of their own — a save that creates one writes
no `created` event — and the log is deleted deliberately on both paths that
remove a flow row, `Flows.delete/1` and the save's sweep of unreachable
subflows. `update_status/3` reads the row again inside its transaction, so
the event's `"from"` is the status the flow had at the write. Download and
Print refuse a flow whose status hides it from users — a page in all but
name, and the token's lifetime is the one window in which that can change
after the page drew.

**Schema:** `form_flow_flows.status` (not null, default `draft`, indexed —
every user-facing listing narrows by it) and the
`form_flow_flow_events` table are in **v01**, edited in place — the project
is pre-release. A database that has already run v01 will not pick these
up: Ecto records the host's migration as applied, so drop and recreate it.

### A flow has a history page

**`/flows/:id/history`** (**`FormFlow.Web.Templates.Flows.History`**)
lists the flow's log newest first — "Created", "Draft → Open" — with who
did it and when (relative, the absolute on hover). Roots only; an owned
subflow's id lands on its root's page. **`Flows.list_events/1`** is the
query behind it. Reached from the show page's **History** button and the
flows index's ⋮ menu, where it is the one link: a lesser page than
Overview and Health, there for auditing, and where other historical data
about a flow would go. **`Templates.Shared.relative/1`** is the "3 hours
ago" the health page already drew, now shared.

### Duplicate Flow, from the show page and the flows index

The flow copy's button says **Duplicate Flow**: the canvas's ⋮ node menu
already has a Copy that means "to the clipboard, paste later", and one word
with two behaviours in one UI is one too many. In code — `copy/2`,
`CopyDialog`, the `copy` event, the "(copy)" name default — the word stays
*copy*. The button sits beside Flow Overview on a root flow's Show page,
and is gone from the Edit page: a copy is of what is saved, and the page
for what is saved is Show (the dialog's saved-version note went with it).

The flows index gained a **⋮ menu** on every row for actions that do
something rather than go somewhere — Duplicate Flow today — beside its
links, now **Overview**, Show, and Edit; and a **Slug** column, sortable,
between Name and Kind. The router passes the index `flow_types` and
`form_types` for the copy's health check, and a host rendering
`FormFlow.Web.Templates.Flows.Index` itself should too.
`FormFlow.Web.Templates.Shared.copy_flow/3`'s third argument is now
`opts` — the types as before, plus `user_id:` for the copy's `created`
event.

## v0.21.0

### A flow is copied by `Flows.copy/2`, and the copy is whole

**Breaking:** `FormFlow.Data.Templates.Flows.duplicate/2` is now
**`FormFlow.Data.Templates.Flows.copy/2`** — the word `Forms.copy/2` and
the prose already used. The copy now plans every node's new id across the
whole tree before writing anything, and what refers to a node is
re-pointed as it is copied: a `:related_form` property value — a step path
— in a copied owned form's properties now names the copied steps rather
than the source's (it used to point into the source tree, where health
reported it missing); an ignored health entry comes along re-pointed at
the copied node (**`Health.for_copy/2`**; the cached status still does
not, and an owned copy carries no bookkeeping at all — `Health.forget/1`
is for those); and an entity two steps share — a step the canvas
duplicated, on one owned form or one subflow — is copied once and shared
by both copied steps, where it used to become two.

`copy/2` takes **`name:`** for the copy's name (subflows under it keep
theirs). `owner_flow_id:` is now checked: an id no flow has is
`{:error, :owner_not_found}`, a flow of another tenant's tree is
`{:error, :other_tenant}` (the rule `reuse_form/3` applies to forms), and
naming an owned subflow as the owner makes the copy owned by that
subflow's root, since ownership is flat. An owned flow copied as a root
takes a slug from its name, as `create/1` would, and its steps are
rewritten under it — it used to get none, and its steps kept the old
root's prefix. A refused insert — a taken `slug:` — returns
`{:error, changeset}` with nothing written, where it raised.

`FormFlow.Data.Templates.Forms.copy/2` takes **`properties:`**, the copy's
properties in place of the source's, which is how the flow copy hands
over re-pointed values in one write.

### A flow is copied from its pages

**Copy**, on a root flow's Show and Edit pages, opens a dialog
(**`FormFlow.Web.Templates.Flows.Components.CopyDialog`**) prefilled with
the copy's name — the source's with "(copy)" after it — and the slug
`copy/2` would pick (**`Flows.copy_slug/1`**, new), calls `copy/2` with the
host's types so the copy's health is cached, and lands on the copy's show
page. A refused slug keeps the dialog open with the reason and what was
typed; a blank name takes the one offered. On the Edit page with unsaved
edits the dialog says the copy is made now from the last saved version, and
the page stays open with the edits after copying, saying where the copy
went — the link leaves through the same save-first prompt as every other
way off the page. An owned subflow's pages have no Copy: a subflow is
copied by pasting its step.

`FormFlow.Data.Templates.Flow` preloads its nodes and relationships in
stored order (`inserted_at`, then `id`), which the save's "canvas order"
rules — which of two same-named steps takes the bare slug, which position a
pasted path is rebased to — relied on without asking.

### A shared form cannot point at a step

A catalog form is one lineage for every step reusing it, with one place
for its type's property values, so a `:related_form` value — a position in
one flow — can be right in one flow only. `reuse_form/3` already refused
picking such a form for a step; now the form's own edit page refuses the
choice from the other side, naming the fix (copy the form into the flow,
or clear the choice), and **`FormFlow.Data.Templates.Flows.Health`**
reports the state as **`:related_form_shared`** should it arrive another
way — a copied flow whose step reuses such a form, a host writing
properties directly. The type alone, its property unset, is fine.

**Breaking:** `Flows.copy/2` no longer takes `owner_flow_id:`. A copy is
always a root flow beside its source; a subflow wanted inside a tree is
copied by pasting its step, which makes the copy and the step pointing at
it in one save — where a copy made owned with no step pointing at it was
swept on the tree's next save. An owned subflow can still be copied out
as a root of its own.

### A step can be pasted

A node saved with `data.copy_of_node_id` — the id of the node it was
copied from — is a **pasted step**: before anything else in the save reads
the nodes, `Flows.update/2` copies the entity behind the source for it, the
way `copy/2` copies a tree. An owned form becomes a new lineage owned by
this tree, with provenance; a subflow is copied whole, its steps' slugs
under this root's prefix; a catalog form stays the same shared reference.
The marker is consumed, never stored, so nothing is copied twice; the
pasted step's label and type write through to the copy like any step's.
The save is refused with an error on `:nodes` when the source no longer
exists or belongs to another tenant — and the page shows that sentence:
**`FormFlow.Web.Templates.Shared.save_error/2`** now surfaces a `:nodes`
refusal (a pasted step whose source is gone, a step the tree does not own,
a removed form that still has data) where it used to show the generic
retry. Where the pasted node's data names no type, the source entity's
fills in, so a copy never lands on the default type with its property
values dropped.

On the canvas, a form or subflow step's ⋮ menu — on the read-only canvas
too, since copying writes nothing — has **Copy** — disabled
until the step has been saved, since the save copies from the source by its
real id — and the toolbar shows **Paste “<step>”** beside the add buttons
whenever the clipboard holds a step that fits this canvas: a subflow step
on a "subflows" canvas, a form step on a "forms" one. The clipboard is the
browser's `localStorage`, so a step copied on one flow's canvas can be
pasted on another's, or in another tab; a copy older than a day is ignored
and dropped. Paste adds the copied node's snapshot as a new node wearing a
**Copy** mark until Save, when the server copies the entity behind it and
the mark goes with the marker. Nothing is written before Save.

A `:related_form` path inside what is copied is **rebased to where the
paste lands**: the source flow's prefix is swapped for the destination
flow's and the copied nodes mapped, so a Review pasted into another
flow's subflow still reviews its own copied About. A path pointing outside
what was copied is kept as it is — still right anywhere in the same tree,
a stale choice health reports in another. `copy/2` rebases the same way,
which also fixes an owned subflow copied as a root: its forms' paths lose
the prefix they had under the old root instead of keeping a segment the
new root does not have.

### `Core.badge` has a solid variant

`variant="solid"` drops the default `badge-soft`, the way `button`'s
`variant="primary"` drops its soft style, for a badge that must read at a
glance; a host's `components` override reaches it as before.

### The admin pages share one header

The Overview and Health pages pass the flow as the header's `root` and
their own name as the page's, so the title reads "Flow  Overview" and the
trail walks Flows / Flow (a link to its show page) / Overview.

Every templates page — the two indexes, New, Show, Edit, Overview, the
form pages — now draws the same header
(**`FormFlow.Web.Templates.Components.Header`**, replacing
`Components.Breadcrumb`). On the left, a **title**: the root flow, then,
lighter, the subflow or form reached inside it, then what the page knows
about it — its kind, its type, its version, its perspectives — each after
a middle dot — none between the root and the name reached inside it. Under
it, smaller, the **breadcrumb**, whose first crumb is
now **⧉ Form Flow** rather than Templates; the templates landing draws the
same header, with that crumb alone. On the right, the page's actions
as buttons; the Show and Edit pages' **Overview** is a button now, not a
text link. The breadcrumb keeps its rules — a drill-in walks through Flows,
the edit page's crumbs go through the "navigate" event so unsaved changes
prompt first, `mode=edit` keeps Root and Parent pointed at their editors.

### A flow reports its health

**`FormFlow.Data.Templates.Flows.Health`** checks a root flow — the whole
tree, subflows included — and answers with what it finds, worst first, and
the worst level as one word. What it lists are **entries**, each a
**`FormFlow.Data.Templates.Flows.Health.Entry`**: a level (`:error`,
`:warning`, `:info` — the alerts' and badges' own kinds), a stable code, one
sentence for an admin naming the step by the way down ("Review / Check pet
details"), the step or flow it is about (`subject`), a paragraph on why it
matters (`explanation`) and a sentence on what to do (`fix`) — both per
code, from `Entry.explanation/1` and `fix/1`, so a host drawing its own page
has the words — and where it is (the flow, the node, the position path). An
entry rather than a problem, because a check reads the flow's shape and can
be wrong about what is fine on purpose. `check/2` takes a root flow's id,
or a resolved tree (`Flows.resolve_tree/1`) for a check that touches no
database — what the tests use, and what a check of unsaved canvas contents
would build. Both take the host's `flow_types:` and `form_types:`. The
report counts what it evaluated, in `checks_run`, so a page can say how many
checks passed (`Health.passing/1`) beside an empty list.

The checks, at every connected level: no Start, no End, Start not reaching
End, a step whose form or subflow is missing, a form with no published
version, a type property the type requires left unset, a related form
pointing at a position the tree no longer has or one no Start reaches (the
runtime looks it up among the connected positions) — all errors, since a
user cannot work the flow. A node no Start reaches, a node nothing follows,
Start wired straight to End, a type the host no longer offers, a stale
perspective — warnings. A draft with changes not yet published — info.
What is behind an unconnected step is not checked: it is reported once,
as unconnected.

**The status is cached on the root flow**, under
`properties["_health_metadata"]["status"]` — the level, the counts, the
summary, `checks_run`, and when — and **`Health.status/1`** reads it off a
flow struct with no query. **`Health.refresh/2`** recomputes it: the full
check, written back, once, at the end of each save, by the page or the
operation that owns the whole save — the New page's create, the flow edit
page's canvas and identity save, a step's rename, a form's publish, archive,
draft saved, copied, or deleted, a step deleted, a form reused — never from
inside the context functions a save calls many times. `Flows.duplicate/2`
leaves the source's bookkeeping behind, so a copy starts never checked, and
checks it once when given `flow_types:` and `form_types:`. `Health.refresh_for_form/2` is the form pages' call: every root with
a step on the form, since a catalog form's lineage is shared. A save that
bypasses the pages leaves the badge behind; the health page brings it up to
date, since it runs the check on every visit. The write touches the
`properties` column alone, so a check never moves the flow's `updated_at`,
and a root deleted under an open report answers `{:error, :not_found}`
rather than raising. The `_` prefix marks the key as the library's own
bookkeeping beside the admin-set keys in the same map (see
`guides/neo4j.md`), and **`Flows.update/2` keeps the stored `_` keys** over
whatever map a caller passes — a page saving the copy of `properties` it
loaded cannot take the bookkeeping written since with it. A demo database from before this change may hold
the earlier `_health_ignored_entries` key; recreate it.

**An entry can be ignored.** An admin who always sees "5 warnings" stops
reading them. `Health.ignore/3` records an entry on the root flow — under
`properties["_health_metadata"]["ignored_entries"]`, by its `code` and
`path`, with the `user_id` and the time — and from then on the check lists
it marked (`Entry`'s `:ignored`) but leaves it out of `level` and `counts`,
so the badge says what is new. `Health.stop_ignoring/2` removes the record.
Both write the status too, from the report they hold. Records for entries
the check no longer finds are dropped on the next write, `refresh/2`
included, so a duplicate's copy starts clean. `Health.open/1` and
`Health.ignored/1` split a report the same way; `Health.healthy?/1` and
`Health.wrong/1` answer the badge's question — is anything wrong, meaning an
open error or warning — for a report or a cached status, beside `ok?/1`'s
"is anything open at all".

**Every flow page carries the badge**, drawn by
**`FormFlow.Web.Templates.Components.Health`** — a function component that
reads the cached status off the root flow it is given and links to the
flow's health page: an icon button with a mark on its shoulder — the count
of open **errors and warnings** in the colour of the worst, a check when
there are none (green, or in the info colour when only info entries are
open: a draft with unpublished changes is the normal state of a form being
worked on, so the tooltip reads "healthy · 2 to review" and the flow reads
as healthy), a grey dash for a flow never checked. On the flows index per
row (the listing runs no check), in the Show, Edit, and Overview headers
from any depth, and on a form page reached through a flow — always the
root's; on the edit page it goes through the "navigate" event, so unsaved
changes prompt first.

**`/flows/:id/health`** is the health page, **`FormFlow.Web.Templates.Flows.Health`**,
added to the router as the overview was. Its header names the flow — the
trail leads back to its show page — with **Flow Overview** beside it (the
Show and Edit pages' Overview button is named the same); under it, when it
was checked and what the report is of (the flow's kind, steps, subflows,
forms, perspectives, and flow types — the report's `summary`), then how it
stands (the open entries by level, the ignored ones, and how many checks
passed). Then two panes: on the
left every entry as a row — a dot in its level's colour, grey once ignored,
and where it is — and on the right the selected entry: its level, message,
why it matters, where and which check, what to do, an **Open** button to the
step (a form step's form page, a subflow's canvas, or the containing flow's
editor for a Start or End node and an entry with the flow itself), and the
**Ignore** switch, the same control as the flow pages' Show/Edit switch,
with who ignored it and when once on. The selection rides in the URL as
`?entry=<code>@<path>`, so a toggle keeps it and a link can name one entry;
without it, the first open entry is selected. `FormFlow.Web.router/1`
passes it `user_id` and `params`. Nothing gates on the result: saves and
publishes go through as before.

### Steps have slugs; owned subflows and forms do not

**Breaking: the slug moves to the step.** A form or subflow node — a step —
now carries a `slug` on `FormFlow.Data.Templates.Flow.Node`: optional,
editable, unique per tenant among steps, never following a rename,
dual-written into `properties["slug"]`. It is the handle a host names a
step by in seeds, gates, and callbacks, stable across environments where
node ids are not. Reusing a catalog form had exposed the gap: an owned
form's slug doubled as its step's, and reuse deleted the form, leaving the
step nameable by nothing but its id. Root flows and catalog forms keep
their own slugs. The three uses are distinct — a host naming a step knows
it is naming a step — so uniqueness stays per table.

- **Every step gets a default at save**: its label's segment under the root
  flow's slug — the "Owner contact" step of `dog-license` is
  `dog-license_owner-conta` — with `-2`, `-3`, … when taken among the
  tenant's steps. Start and End nodes get none. A seed sets a step's slug
  by passing `slug:` in the node's attributes to `Flows.create/1` or
  `Flows.update/2`.
- **Owned subflows and owned forms have no slug.** `Flows.create/1` and
  `Forms.create/1` generate none when `owner_flow_id` is set;
  `Forms.copy/2` with `owner_flow_id:` gives none unless `slug:` is
  passed, and a catalog copy of an owned form defaults from its name.
  `Flows.get_by_slug/2` and `Forms.get_by_slug/2` return `nil` for them:
  look the step up with **`Flows.get_node_by_slug/2`** (`tenant_id:` as
  the others take it) and follow `node.form_id` or `node.subflow_id`.
- **The canvas cannot change a slug.** A save carries each surviving
  node's slug across by id and overwrites the properties copy the canvas
  round-trips; unlike `form_id`, a slug is never taken from properties, so a
  tab opened before an admin changed a slug cannot put the old one back.
- **`Flows.duplicate/2` re-slugs copied steps**: a default under the
  source's slug is rewritten under the copy's (`dla2026_user-inform`
  becomes `dla2027_user-inform`); a hand-set one gets a free suffix.
  `reuse_form/3` leaves the step's slug alone — nothing about the node
  changes but `form_id`.
- **`Flows.update_node/2` replaces `rename_node/2`**, taking `:label` and
  `:slug` — what the step's page edits on the node itself. A blank label
  renames nothing; a blank slug clears it; a slug another step holds is
  refused with an error on `:slug`.
- **`FormFlow.Context.form_node`** is the step of the form in scope, beside
  `subflow_node`. `context.form_node.slug` in `handle_complete/2`, the type
  callbacks, and `on_mount` says which step, where `context.form.slug` is
  a catalog form's, shared by every flow reusing it, and `nil` for an
  owned form. `FormFlow.Data.Instances.FormProgress` gains `:node`.
- **Pages.** Reached through a step, the form edit page's Slug field is
  **Step slug** and writes the node; when the step reuses a catalog form,
  the catalog form's own slug is named under the field. The flow edit
  header, drilled into a subflow, edits the step's slug the same way. The
  copy chooser labels a flow's forms by their step's slug and the catalog's
  by the form's; the reuse confirmation names the deleted form by name.
- **Tenancy on the graph tables.** `form_flow_nodes` and
  `form_flow_relationships` gain `tenant_id`, stamped from the flow at
  insert, immutable, dual-written into `properties` — a Neo4j query
  narrows to a tenant without a hop to the flow, and the step slug's
  per-tenant unique index needs it on the row.
- **Breaking: the v01 migration changed again.** `form_flow_nodes` gains
  `slug` and `tenant_id`, with a partial unique index over `slug` and
  `COALESCE(tenant_id, '')`; `form_flow_relationships` gains `tenant_id`.
  Drop and recreate any database migrated before this version.

### A flow can be read whole: the overview page

The canvas builds a flow one level at a time — a subflow node's Open
button drills into that subflow's own canvas. **`/flows/:id/overview`
shows the whole flow at once**, read-only: every subflow expanded in place
as a group holding its inner flow, recursively, laid out left to right.
Only the steps a user can reach are drawn — at each level, the nodes a
Start node reaches along the flow's connections — so an unwired step or a
fragment wired only to End is left to the drill-down, where it is fixed.
Open on a form node or a group's header goes where the Show page's Open
goes. The Show and Edit pages link to it as **Overview**, from any depth,
for the root.

**`FormFlow.Data.Templates.Flows.connected_tree/1`** narrows a resolved
tree (`resolve_tree/1`) to those nodes and the connections among them,
recursively — the same reading of "reachable" `FormFlow.Data.Instances.FlowProgress`
walks with. **`FormFlow.Web.Helpers.ReactFlow.to_tree_data/1`** encodes a
tree as nested ReactFlow data for the canvas. **`FormFlow.Web.Templates.Flows.Overview`**
is the page, **`FormFlow.Web.Components.Overview`** the canvas component;
the React bundle gains a `mountOverview` export beside `mount` and lays the
tree out itself from measured node sizes, since ReactFlow has no layout of
its own.

## v0.20.0

### Subflows are always owned; sharing by reference is for forms alone

**Breaking: reusable subflows are gone.** A subflow is a subtree — its own
forms, the paths through it, its perspectives and type — and sharing one
across trees made every operation on it ambiguous about which tree it was
happening to: which root a usage belongs to, whose canvas typed it, whose
users a strand reaches. A form is a leaf, one lineage and one version pin
per instance, and that is where reuse stays (see below). A subflow wanted
in a second tree is copied there with `FormFlow.Data.Templates.Flows.duplicate/2`.

- `FormFlow.Data.Templates.Flow` loses `made_reusable_at`;
  `FormFlow.Data.Templates.Flows` loses `make_reusable/1` and
  `list_reusable/1`. **The v01 migration changed again**: `form_flow_flows`
  drops the column and its partial index. Drop and recreate any database
  migrated before this version.
- **Saving a flow refuses a subflow step that points at a flow the tree
  does not own** — another root's subflow, or a root flow — with an error
  on `:nodes`: "a subflow step must point at a flow this flow owns — copy
  the flow to use it here". Every subflow's `owner_flow_id` is the root of
  the tree it sits in, and `duplicate/2` copies every subflow along with
  its source; there is no shared reference to keep.
- **`Flows.delete/1` refuses an owned flow** rather than scanning for
  embedding nodes outside the tree: a subflow is deleted by removing its
  step (`delete_node/1`). The flow Show page now shows the context's reason
  for every refusal — "it is a subflow of another flow", "flow instances
  have been started against it", an owned form with submitted data — where
  it used to say "another flow still uses it as a subflow" for all of them.
- The router's `flows` attr and `FormFlow.Web.Instances.Forms.Shared.resolve_flows/2`
  offer every root flow of the tenant; there is no longer a reusable set to
  leave out. The flow edit page's Step name field no longer has a
  reusable-flow note: a step's subflow is always renamed with it.

### A step can reuse a catalog form

A form step points at a form lineage, and saving a flow gives every new
form step a blank owned lineage of its own. **A step can now be pointed at a
catalog form instead** — one lineage shared by every flow whose steps point
at it, so an edit reaches them all and one publish migrates the instances
of all of them. Reuse a form when every flow should change together; copy
it when the flows will drift.

**`FormFlow.Data.Templates.Flows.reuse_form/3`** repoints a step at a
catalog form and deletes the owned form the step abandons (its slug is free
again at once). Refused as `{:error, :owned_form}` (only catalog forms are
shared — an owned form is deleted with its tree), `{:error, :other_tenant}`,
`{:error, :related_form}` (the form's type declares a `:related_form`
property, whose value is a step path in one flow; the host's types come in
as `form_types:`, the library's by default), and
`{:error, :step_form_published}` (the step's own form has a published
version, which may have instances; a never-published one cannot, and goes
whether or not it has content). A step leaves a catalog form the way it
leaves any form: removed from the canvas and added again, it is a new step
with a fresh owned form and the chooser, where Copy form makes a private
copy; the new step has a new id, so users who had started the old one are
stranded there, as after any removed step.
**`form_usages/1`** lists every step pointing at a lineage with its flow
and that flow's root, for the pages that say where a shared form is used.
`FormFlow.Config.Forms.Type.related_form_property/2` finds the property
that ties a form to one flow.

**Breaking: `FormFlow.Data.Templates.Forms.delete/1` refuses a form that
steps point at, as `{:error, :in_use}`.** It used to raise on the node
foreign key. `FormFlow.Web.Templates.Forms.Show` names the flows: "This
form can't be deleted: Dog License and Cat License use it. Remove those
steps first." `Forms.instance_counts_by_flow/1` attributes a lineage's
instance counts to the root flows they were started in.

**Breaking: the canvas writes a form type through only to an owned form.**
`Flows.update/2`'s `data.form_type` write-through follows the label's
ownership rule: a catalog form is typed on its own page, once for every
flow reusing it, and a type picked for it on one flow's canvas is not
written — the canvas shows the form's true type again on its next load. A
reusable subflow's `data.form_flow_type` still writes through.

On `FormFlow.Web.Templates.Forms.Edit`, reached through a step, the
never-published-and-blank chooser offers **Reuse form** beside Custom form
and Copy form: a select of the catalog alone (never an owned form, never
one whose type ties it to a flow; a never-published one is marked "draft,
never published", since a step reusing it cannot be started until it
publishes) and a confirmation that says what is agreed to — edits reach
every flow using the form, publishing it can reset or reopen users' forms
in all of them, this step's own form is deleted, and leaving the form later
means re-adding the step. Selecting leaves for the step's form page, since
the URL named the deleted draft. Standalone, where there is no step to point,
the chooser is Custom form and Copy form as before.

Sharing is visible everywhere it matters: a step's form page (Show and
Edit) wears a badge, **Catalog form · "Owner contact" · used in Dog
License, Cat License**, that also says how to stop; the publish dialog
attributes its counts, "In progress: 1 in Dog License, 1 in Cat License";
and the catalog index gains a **Used in** column, a catalog form's Show
page a "Used in" line.

### Copy existing form is the radio's third choice

**"Edit form version using:" on `FormFlow.Web.Templates.Forms.Edit` now
offers Form builder, JSON, or Copy existing form.** The "Copy definition
from existing form" select and its button used to sit under the JSON
textarea; they are a mode of their own now, with a heading that says what
moves (the definition) and what stays (name, slug, description, form
type). Whatever was typed in the other editors is held while Copy is
showing, so Save from there saves it; switching to Copy from JSON that does
not parse is refused the way the form builder refuses it. The choice is
offered only while there is another form to copy from, as the select
always was. Hosts that drive the radio by value in tests pass
`definition_editor: "copy"` to reach the control.

**Both copies offer this flow's forms as well as the catalog.** The
chooser's Copy form and the editor's Copy existing form used to list the
catalog alone. Opened from a flow, they now list that root flow's forms
first — subflows included, in the order a user works them — then the
catalog. Every option says where its form comes from, then how that place
shows it, then its slug: "Current flow - Documents / Proof of address
(proof-of-address)" for a step, "Reusable form - W-2 (w2)" for a catalog
form (which used to read "W-2 · w2"). Never the form being edited; a catalog form
reused in this flow appears once, at its step. The two lists come from two places
(`FormFlow.Web.Templates.Shared.flow_forms/1`, new, and
`FormFlow.Data.Templates.Forms.list/1`) and are merged on the page, so
reusing a catalog form — which is the catalog alone — is unchanged.

### A version's page leads to the draft under way, and archived versions can be forked

**Breaking: `FormFlow.Data.Templates.Forms.create_draft/2` accepts an
archived `based_on:`, and refuses a draft base as `{:error, :based_on_draft}`
(was `:based_on_not_published` for both).** A draft forked from an archived
version copies its definition and records it as the base, so
`stale_draft?/1` reports it stale whenever something else is published —
which it is.

On `FormFlow.Web.Templates.Forms.Show`, a published version's actions gain
**Continue editing latest draft**, shown while the lineage has a draft and
leading to the newest one's editor: the default view is the latest
published version, so a draft already started was easy to miss. An archived
version's page, which offered nothing before, now offers that and **New
draft from this version**; only a published version can be archived, as
before.

### Form type follows Description, and says what it does

On `FormFlow.Web.Templates.Forms.Edit`, the **Form type** dropdown now
sits after **Description** rather than before it, and a callout under the
dropdown — "About Review form type" — shows the picked type's description
(`FormFlow.Config.Forms.Type`), following the pick as it changes — so the
choice explains itself before the type's properties ask for anything.

### A step's name is the node's, and stays in step with an owned form or subflow

**Breaking: the canvas no longer loads a form's or subflow's `name` over the
node's label.** `FormFlow.Web.Helpers.ReactFlow.to_data/1` used to project
the entity's current name into every form and subflow node's `data.label`
on load, so a catalog form pointed at from two flows renamed both steps to
the catalog's name, and a rename on a form's own page reached users only
after the next canvas save. The node's stored label is now the step's name
everywhere — it always was on the instance side
(`FormFlow.Data.Instances.FlowProgress`) — and the two pages that rename a
step keep the entity behind it in step from both sides:

  * **The canvas save** (`FormFlow.Data.Templates.Flows.update/2`) still
    writes the label through to the form or subflow, but **only when this
    flow tree owns it**. A catalog form or a reusable subflow keeps its own
    name for every consumer; the step's label is this flow's word for it.
  * **The form and flow edit pages** reached through a node now edit the
    step — the field reads **Step name** — and write the node's label
    (`FormFlow.Data.Templates.Flows.rename_node/2`, new) *and* an owned
    entity's `name` in one save, so there is no longer a state where the
    admin sees one name and users another. From a step, a catalog form's or
    reusable flow's own name is left alone, and the field says so. A
    catalog form's own page (`/forms/:id`) and a root flow's own page keep
    editing the entity's name as before.
  * **Copy form** no longer writes the source's name onto the form being
    started: a copy brings description, type, and definition, and the step
    keeps its name.

Hosts that renamed forms or subflows through `FormFlow.Data.Templates.Forms.update/2`
or `Flows.update/2` directly, expecting the canvas to pick the new name up,
now rename the step too (`rename_node/2`), or do it on the pages.

### Fixed

- **`FormFlow.Data.Templates.Forms.copy/2` carries the source's
  `properties`.** A copy used to come back with none, so every owned form
  of a duplicated flow lost its form type and the type's property values.
  A `:related_form` value is a step path in the source's tree and shows in
  the copy as a choice to make again, as it does after any rearrangement.

## v0.19.0

### The definition can be built as a form, not only typed as JSON

**New radio on `FormFlow.Web.Templates.Forms.Edit` — "Edit form version
using:" Form builder or JSON.** The JSON textarea is the second choice now.
The first is a `DynamicForm` nested form with one entry per element — type
and name, then the fields that apply to that type: label, input type,
choices (one per line, `value | Label` to store one thing and show
another), rating bounds, HTML, placeholder, help text, default value,
Required, and Visible if. Entry fields are named after the SurveyJS
properties they set, and input types read "Input - Text", "Input - Rating"
and so on, so the two container types below stand apart. Element names
must be unique, as the definition needs them to be; Type and Name carry the
required mark so a half-made element is never a mystery in the preview.

Both editors sit in the one form, so there is still one Save; whichever is
hidden keeps its content and stops being required. Content crosses between
them when the radio changes: the JSON decodes into entries, or the entries
are written back as the JSON's `elements` — every other top-level key is
kept. A definition the builder has no control for (`readOnly`, validators, a
`file` question, ...) or JSON that does not parse **refuses the switch** and
says why, rather than losing what it cannot show. The builder opens by
default whenever it can show the saved definition, so a blank draft starts
there. Copy definition belongs to the JSON editor: it is a field of the form
now, hidden with the textarea.

**Groups and nested forms.** Two more element types: a **group** (`panel`)
and a **nested form** (`paneldynamic`, repeating entries). Either holds
its members in an "Elements inside" list within its own entry — the same
kind of entry, one level deep — written back as `elements` or
`templateElements` by type. A group's members share the form's scope, so a
name repeated between a group member and an element outside it is refused
on Save; a nested form's template is a scope of its own. A group offers its
layout; a nested form its entry title, fewest and most entries, and add
button text.

**Move up and down.** Every element carries arrows. They set a hidden
`move` field, fire the form's change on the client, and clear it again, so
the request arrives with every other value as the admin left it — in that
one change and no other — and the page hands the reordered entries back as
the form's data.

### The edit page is two parts: the form, then this version beside its preview

**Form details** runs the full width: Name and Slug on one row, then Form
type, then Description. **Form version** — the draft strip, the editor
radio, and the builder or the JSON under its own "Form version JSON"
heading — sits in a left column with the **Preview** on the right, which
stays in view while the editor scrolls. Each part has a heading and a line
saying what belongs there; the slug's and the element name's guidance moved
into their placeholders.

The layout reaches the form's groups by the name DynamicForm 1.1.0 stamps on
them (`data-dynamic-form-group`), so **the page needs `dynamic_form` 1.1.0
or later** — `mix.lock` points at it; on an older version everything
renders full width.

**Form type is required** and shows the first type the page offers when
none is saved — the type the form was governed by anyway, since the instance
pages fall back the same way — so a form that never picked one saves what it
was already getting, explicitly. The dropdown offers no blank.

### Required fields show their mark

`FormFlow.Web.CoreComponents.input/1` renders the mark DynamicForm asks for
beside a required field's label — `*` by default, another string if the
definition sets one, none if it blanks the mark while staying required —
for text, select, textarea, and checkbox inputs. Before, the request landed
as a stray attribute on the control. This shows on every required field
FormFlow renders through its own components, including questions on the
instance pages. A required select that already holds a value offers no
blank option, since it could never be submitted.

### Fixed

- `FormFlow.Web.CoreComponents.button/1` declares `type` and `disabled` as
  attributes rather than globals. DynamicForm renders its add-entry and
  submit buttons through it with `type:` beside an explicit `rest`, and
  Phoenix folds undeclared assigns into `rest` only when none is given — so
  the type was dropped: Add element was a submit button that silently saved
  the draft, and the Save buttons on instance pages carried no type.
- `FormFlow.Web.Templates.Forms.Preview` catches a definition that parses
  but cannot build a form (a question with no name) and shows it inline,
  where before the error surfaced inside DynamicForm's component at render
  time and the preview crashed.

### Changed

- The edit page no longer debounces DynamicForm's change pass; it debounces
  the preview refresh alone (500ms of quiet, while auto-refresh is on), so
  the dirty flag, an editor switch, a moved element, and every other
  consequence of a change happen at once.
- Dirtiness compares the definition as the map that is saved, not as its
  text — re-indenting JSON is no longer a change.
- A blank `form_type` param keeps the current type rather than clearing it,
  so the required error stays on screen; tests that submitted `""` to unset
  the type now see it refused. Tests that submit raw JSON to the edit form
  pass `definition_editor: "json"`, since a blank draft no longer opens on
  the JSON field.

## v0.18.0

### A blank, never-published draft asks Custom form or Copy form first

**New chooser on `FormFlow.Web.Templates.Forms.Edit`**, shown only for a
draft that is both blank (`definition == %{}`) and has never been
published — the same "nothing at stake yet" state `ever_published?/1`
already names elsewhere on this side. Until a choice is made, **the chooser
is the whole page** — no identity form, no definition field, no Save or
Publish. Custom form's **Select** reveals the rest with nothing changed;
Copy form's own **Select** picks another form and writes its name,
description, form type (and that type's property values), and definition
onto this one — never its slug, which already carries this form's own
place (a flow node's, or its own).

Copy changes the data, which is what makes the chooser stop offering
itself on its own. Custom form doesn't, so it leaves a `?start=custom` on the
URL — the one thing that has to persist across the `push_navigate` its own
Select performs, since nothing else does. Copy's dropdown labels each
option with the form's slug alongside its name.

**New, separate: a "Copy definition" control under the Definition (JSON)
field**, available any time (not gated by the chooser above) — a plain
select ("Copy definition from existing form…") and button that write only
the chosen source's definition, leaving name, slug, description, and form
type untouched.

### Auto-refresh defaults on; Delete draft needs another version to delete

**`FormFlow.Web.Templates.Forms.Edit`'s Auto-refresh toggle now defaults
on.** One consequence worth knowing: `DynamicForm`'s `change_debounce_in_ms`
is tied to it, so every field on the page — not only the definition JSON —
now debounces its change pass by 500ms while the toggle is on, including
the Save button's dirty/clean styling. Turning Auto-refresh off restores
instant feedback, as before.

**Delete draft is hidden on `Forms.Show` and `.Edit` when the draft is the
lineage's only version.** A second version — another draft, or a published
one — is what brings the button back.

### Status messages and badges are components, and daisyUI ones

**New: `alert/1` and `badge/1` on `FormFlow.Web.CoreComponents`**, resolved
through the `components` attr like every other component FormFlow renders —
so a host that wants FormFlow's messages and badges to look like the rest of
its application defines them and owns them. Neither is part of the
Phoenix-generated `CoreComponents` set, so a host that defines neither gets
FormFlow's own, the way any undefined function already falls back.

Every status message on both the templates and the user-facing pages now
draws through `alert/1` instead of its own hand-rolled box, so the two sides
say the same kind of thing the same way: a form that was not found, a page
the host refused, a form not started yet, a draft based on a stale version,
answers stranded at a position the flow no longer has. Every state pill —
Available / In progress / Done / Pending, a flow instance's status in the
listing, a form's step in the progress row — draws through `badge/1`.

- **Breaking: `FormFlow.Web.Instances.Components.FormPage.notice/1` is
  gone.** Each page writes its message as `FormFlow.Web.Components.Core.alert/1`
  at its own `render/1` clause. `breadcrumb/1` is unchanged and is all the
  module holds now.
- **Breaking: `FormFlow.Web.Instances.Components.Flows.Progress.badge/1`
  returns `{text, kind}`** — the `alert/1`/`badge/1` palette atom — where it
  returned `{text, classes}`, a string of Tailwind colors.
- **The assigns handed to a flow type's `progress_component/1` now carry
  `:components`**, so the badges it draws resolve through the host's module
  too. A type that passes its assigns straight to `flow_progress/1` (as the
  built-in types do) needs no change.
- Download PDF and Print on `FormFlow.Web.Instances.Forms.Show` are buttons
  rather than bare links, as are Start, Continue, View and Reopen on the
  flow instance's page. Start, Continue and View are still links underneath:
  a form's URL addresses its *position*, so navigating to one is the whole
  action.

The user-facing pages were also sized up: body text at `text-base` rather
than `text-xs`, page headings at `text-base`, list rows separated rather
than crowded. `FormFlow.Web.Router`'s own admin landing (the page linking
Flows and Forms at the mount root) got the same treatment.

- **Breaking: `FormFlow.Web.Templates.Forms.Show` no longer has a
  "Definition" panel** showing the version's raw JSON. Versions now comes
  first, ahead of Preview, in the space it left.

### Opening a form node from the flow editor lands on Show, not a draft

**Breaking: `FormFlow.Web.Templates.Flows.Edit`'s "Open" on a form node no
longer lands on the form's edit page.** It lands on the form's *show* page,
the same place Open takes you from the read-only canvas
(`FormFlow.Web.Templates.Flows.Show`). The flow canvas's own edit mode is
still sticky — Save stays here, and opening a *subflow* node still lands on
its edit canvas — but a form is a different workspace with its own save
model, and crossing into one is the ordinary boundary now, not a
continuation of the canvas's.

This also removes a side effect: Open used to silently create a fresh draft
version for a form that had none, purely so there would be something to
land the edit page on. It creates nothing now.

One exception: a form nobody has ever published has nothing on Show worth
seeing — no history, no content a draft might overwrite — so Open still
lands straight on its (sole) draft's editor there, exactly as it did
before. `FormFlow.Data.Templates.Forms.ever_published?/1` is what decides
it, the same check `FormFlow.Web.Templates.Forms.Show` already uses to skip
its publish-migration dialog for the same reason.

### The Show/Edit toggle is gone from the form template pages

**Breaking: `FormFlow.Web.Templates.Forms.Show` and `.Edit` no longer draw a
Show/Edit toggle switch in the header.** Edit already links back to Show
(the form name in its breadcrumb); Show gains a plain **Edit draft** button
next to Delete draft and Publish, in that order, so a draft stays reachable
without the switch. Archive is now labeled **Archive version**.

### A form's breadcrumb remembers you were editing its flow

**New: `FormFlow.Web.Templates.Components.Breadcrumb`**, the shared
Templates / Flows|Forms / Root / Parent trail all four templates pages
(`Flows.Show`, `Flows.Edit`, `Forms.Show`, `Forms.Edit`) now render through,
replacing four near-identical copies of the same markup. Each page supplies
only its own trailing crumb through `inner_block`.

The point of unifying it: opening a form node from a flow's *edit* canvas
now carries a `mode=edit` query param onto the form page it lands on (see
"Opening a form node..." above), and the breadcrumb reads it — Root and any
Parent subflow crumb target their `/edit` pages instead of their show pages,
so backing out of a form you reached while editing its flow lands you back
in the editor, not a read-only view. Reached any other way (a bookmark, the
read-only canvas), the crumbs are the plain show links they always were.

- **New: `FormFlow.Web.Helpers.Paths.preserve_query_params/3`** forwards a
  whitelisted set of query params from `params` onto a path a page builds
  for its own internal navigation — how `mode` survives Show ↔ Edit and the
  Publish/Archive/Delete-draft redirects on the form pages, rather than
  evaporating at the first click that isn't the breadcrumb itself.
- `FormFlow.Web.Templates.Forms.Show` and `.Edit` now assign `:params`
  (`FormFlow.Web.Router` forwards it to both, and to `Flows.Show`/`.Edit`
  too, for symmetry) — previously only the two Index pages received it.

### Each user-facing page names the state it is in

**New: `FormFlow.Web.Instances.Shared`**, holding `page_state/1` and
`form_page_state/1`. Each user-facing page computes its state once, where
the loading and the host's `on_mount` ran, and assigns it as `:page_state`.
Every `render/1` clause matches on it and every event guards on it.

A LiveComponent's `handle_event/3` is reachable whenever the component is
mounted, and these pages are mounted even when they drew a refusal instead
of themselves — so which buttons were rendered gated nothing. Four
user-visible consequences:

- **Breaking (security): `FormFlow.Web.Instances.Flows.Show` no longer
  reopens a position it did not offer.** Its Reopen event took the position
  from the client and was not checked against the rows the page drew, and
  the write it made was not a reopen: an unstarted position fell through to
  `FormFlow.Data.Instances.Forms.update_status/4`'s create, which resolves
  the node with a bare lookup — no tenant, no flow narrowing. A legitimate
  viewer of their own journey could insert a row into it pinned to **another
  tenant's** form version. The event now requires the page to be drawing its
  rows *and* the position to be a completed row it drew that has an
  instance. The data-layer half is unchanged and is the follow-up:
  `create_at/3` still accepts any node id, so any caller passing a
  client-supplied path has the same hole.
- **`FormFlow.Web.Instances.Flows.Index` no longer crashes on `start` after
  a refusal.** Its listing is built inside the gate's `on_ok`, so a refused
  viewer had no `page_flows` and the event raised `KeyError`. It now refuses
  silently. This was a crash, not an unauthorized write.
- **`FormFlow.Web.Instances.Forms.Edit` refuses a submit the gate would
  refuse**, and refuses a stale one — a submit landing after the page has
  already re-rendered as submitted. (A rapid double submit is unchanged: it
  arrives before the page re-renders, and stays as safe as it was, on
  `FormFlow.Data.Instances.Forms.update_status/4` being idempotent.)
- **A submitted form whose stored definition will not parse now says so on
  Edit**, instead of "This form has already been submitted." There is
  nothing to edit either way, and the parse error is the more informative of
  the two. Show already said the parse error.

Two smaller changes follow from computing the state once:

- **A *stranded* position — one the flow no longer has — can now be
  downloaded and reopened from its own page.** Both were additionally gated
  on the flow type's `visible?`, which is false for every stranded position,
  while the page itself still drew the answers. So Download and Print were
  absent, and Reopen was **drawn but silently did nothing** when clicked.
  Both now work: what is printed is what is shown, and a button the page
  draws is a button that acts. Nothing else about stranded positions moved —
  Edit already worked one reached by URL, and the flow instance's page still
  lists none of them, still pointing the user at an administrator.
- **A state no page accounted for now raises at render** rather than
  falling through to a catch-all clause and drawing the whole page. None of
  the pages has a `def render(assigns)` catch-all any more.

For a host, the pages behave as before in every state they already drew;
only the four bullets above change. `:page_state` is a page assign, not part
of any callback's arguments.

### One router module for every route a host mounts

**New: `FormFlow.Router`**, the single place the route macros live. A host
imports it once and calls the groups it wants, all of them before any
catch-all route.

- **Breaking: `FormFlow.Web.Assets.Router` is gone, and `form_flow_assets/1`
  with it.** The editor bundle's route is now
  `FormFlow.Router.form_flow_router_asset_routes/1`, same options and same
  behaviour:

  ```elixir
  # before
  import FormFlow.Web.Assets.Router

  scope "/" do
    form_flow_assets()
  end

  # after
  import FormFlow.Router

  scope "/" do
    form_flow_router_asset_routes()
  end
  ```

- `FormFlow.Router.form_flow_router_download_routes/1` joins it there — see
  below.

### A form's answers can be downloaded and printed

**New: `FormFlow.Web.Controllers.Downloads`**, an ordinary `GET` route that
sends one form instance's answers as a file. A LiveView holds a websocket and
cannot send a response, so taking answers away is a link out of the page:
`FormFlow.Web.Instances.Forms.Show` now draws **Download PDF** and **Print**
once a form has been started. The two send the same document and differ by one
header — `attachment` saves a file, `inline` opens it in the browser's own
viewer to read and print.

**Mount them once, before any catch-all**, with the new
`FormFlow.Router.form_flow_router_download_routes/1`:

```elixir
import FormFlow.Router

scope "/" do
  pipe_through [:browser, :require_authenticated_user]

  form_flow_router_download_routes()
end
```

- **One route, and the request in the query string**:
  `<download_path>?disposition=download|print&flow_instance_id=…&path[]=…`.
  The path carries nothing, so a host can mount it anywhere, however deeply
  nested. `path[]` repeated is the position — the chain of node ids, as the
  user-facing pages address it — so it arrives as the list it is rather than a
  string with a separator to know. `disposition` is the only difference
  between Download and Print; anything but `print` is a download.
- **Downloads are opt-in.** `config :form_flow, download_path: "..."` is what
  turns them on: until an application names a path, the form pages draw no
  Download or Print link at all, so a host that does not want the feature
  carries no trace of it.
  `FormFlow.Web.Controllers.Downloads.path/0` is that value, `nil` by default;
  `mount_path/0` is where the route macro mounts, falling back to
  `/form-flow/downloads` since a declared route has to answer somewhere.
- **New `download_path` attr on `FormFlow.Web.router/1`** and the instance
  LiveComponents: where the two links point, per mount, overriding the
  config. It is how an
  application points the links at an endpoint of its own and generates the
  document itself: read `flow_instance_id`, `path[]`, and `disposition` off
  the query string and FormFlow's route need not be mounted at all. The base
  resolves when the link is drawn, so the config is read live rather than
  baked into an attr default.
- **The PDF is written by FormFlow, with no dependency** —
  `FormFlow.Web.Downloads.Renderer.PDF` and its
  `FormFlow.Web.Downloads.Renderer.PDF.Writer`, a small text-and-pagination layer
  over the PDF format. No Chrome, no wkhtmltopdf, nothing to install beside
  the application. Helvetica and Helvetica-Bold with their real metrics, so
  wrapping is measured; WinAnsi text, so Latin-1 and the typographic
  characters that keep appearing in pasted answers come through and anything
  outside them becomes `?`.
- **New: `FormFlow.Web.Downloads.Document`**, what a resource becomes before a
  format is chosen — a title, the details about the resource itself, and
  sections of `{:field, label, value}`, `{:text, text}`, and `{:group, title,
  entries}` entries. Parsers turn resources into it, renderers turn it into
  bytes, and the two never multiply. Parsers sit beside the components that
  draw the same resource on screen, and
  `FormFlow.Web.Components.Forms.Downloads.Parsers.FormInstance` is the first
  of them: a static panel becomes a section, a repeating question a section
  of one group per entry, a hidden question is left out, an unanswered one is
  kept, and values render for reading — a choice prints its text, a boolean
  Yes or No.
- **Nesting is followed all the way down.** A panel inside a repeating
  question's template becomes a group inside that entry's group, and a
  repeating question inside one — users, each with their email addresses — a
  group of groups, as deep as the form goes. Visibility inside an entry is
  judged the way `DynamicForm` judges it, against the entry's own values over
  the form's plus the `panel.`-prefixed copies a `{panel.field}` condition
  resolves through, while the answers come from the entry alone. An entry is
  headed the way the page heads it — the template's `templateTitle` with
  `{panelIndex}` filled in, and no heading where the template sets none — so
  the paper never says more than the screen. The PDF indents each level and
  stops widening the indent past four, so a deep form keeps a readable
  column.
- **New: `FormFlow.Web.Downloads.Renderer`**, the behaviour a host implements to
  draw the document its own way — `render/3` over the document, the page's
  `FormFlow.Context`, and `callback_data`, plus `extension/0`. Mounted per
  route: `form_flow_router_download_routes(renderer: MyApp.FormFlowRenderer)`.
  `FormFlow.Web.Downloads.Renderer.HTML`, a self-contained printable page, ships
  alongside the PDF renderer for hosts that would rather print through the
  browser.
- **New: `FormFlow.Web.Instances.Forms.Shared.resolve/1`**, the loading that
  was inside `assigns/1`, now over a plain map of attrs rather than a socket.
  The download route resolves a position through it, which is what makes a
  printed form and the page it was printed from the same answers rather than
  two readings that can drift. `assigns/1` calls it and is otherwise
  unchanged.
- **`:phoenix` is now a declared dependency.** It was always there —
  `phoenix_live_view` requires it — but `FormFlow.Web.Controllers.Downloads`
  calls `Phoenix.Controller.send_download/3` directly, so the library now says
  so.
  No resolution changes for an existing host.
- **A download is authorized by a short-lived token, not by re-deciding.**
  The page already ran the host's `on_mount`, the flow type's `visible?`, and
  the `flows` scope in order to render; when the user clicks, it mints a
  token saying *this user may take this form away*, and the request carries
  that. Re-deciding in the controller would mean handing the host's gate to a
  route as well as a page — and a route has neither `callback_data` nor the
  page's `flows` attr, so the two would answer differently the first time one
  changed.
  **New: `FormFlow.Web.Downloads.Token`**, encrypted (not merely signed, so
  the ids stay out of logs and history) and good for 60 seconds
  (`config :form_flow, download_token_max_age:`). **New:
  `FormFlow.decode_token/3`**, the stable public name for reading one back —
  what a host serving downloads from its own endpoint calls to find out who
  asked for what.
- **The token is the whole request.** `?token=…` and nothing else: the
  endpoint reads the payload and ignores the rest of the query string, so
  swapping a `path` param cannot widen what a token was minted for. The
  identity the page had — `user_id`, `tenant_id`, `perspectives` — now
  reaches the document's `FormFlow.Context`, where before the request
  resolved with none.
- **Minted on the click, not on the render**, by a colocated hook, so a tab
  left open for days prints as readily as a fresh one: the token is always
  seconds old whatever the page is. The hook opens the print tab
  synchronously with the click and fills it when the URL arrives — a
  `window.open` after the round trip is what popup blockers exist for.
  Download and Print are buttons now rather than `<a href>`, so they need
  JavaScript, as every other interaction on the page already does.
- **Known and accepted: a minted link works for whoever holds it until it
  expires.** FormFlow cannot bind it to a session without knowing the host's
  current user, which is the thing tokens exist here to avoid. The route sits
  inside the host's own pipeline, so an anonymous holder is turned away
  before FormFlow sees the token; and a user who can mint a link can already
  save the file and send that instead. A host wanting more layers its own
  checks in front of the route.
- **`handle_event` is now guarded by the gate's verdict.** A LiveComponent's
  events are reachable whenever it is mounted — which
  `FormFlow.Web.Instances.Forms.Show` is even when the page drew a refusal —
  so which buttons were rendered gates nothing. The gate's answer is computed
  once, where the gate ran, and both the markup and every event read it.
  **This closes a hole in Reopen**: a viewer looking at "This form is not part
  of your work here" could push `reopen` at the component and flip a form
  they could not see back to in progress.

### The flow editor builds left to right

**The canvas is horizontal now**, matching how a flow reads: `Start`'s
connection handle is on its right, every other node's target handle is on
its left and source handle on its right, and a dropped node's `position` is
its left-centre rather than its top-centre. `assets/js/editor.jsx` changed;
`priv/static/form_flow_editor.mjs` is rebuilt from it (`assets/build.sh`).

- **`Flows.starter_nodes/0`'s seed is laid out left to right** — `Start` at
  `x: 0`, `End` at `x: 900` — and, since `Flows.get/1` loads a flow's nodes
  in insertion order and the editor's add actions place a new node to the
  right of the *last* one, `End` is listed (and so inserted) first so that
  `Start` — inserted last — is what a freshly seeded flow's first added node
  lands beside, not `End`.
- **The flow edit page's layout is breadcrumbs/actions, then the canvas,
  then the flow's own Name/Slug/type fields** — the canvas used to sit below
  that details form; now the diagram people are here to build is the first
  thing they see.
- **Every header and modal button on the flow and form template pages is
  sized like `FormFlow.Web.CoreComponents.button/1`** now, not just the
  primary ones — Save and Save draft (soft while clean, solid once there's
  something to save, via `variant`), Publish (`variant="primary"`), Discard
  changes, Delete, and Delete draft (`btn btn-error btn-soft`), the discard
  modal's confirm (`btn btn-error`), and Refresh, Archive, New draft from
  this version, and the modals' Keep editing (plain `btn`). The custom
  Tailwind classes these all used are gone.
- **The Show/Edit toggle sits before the action buttons, not after them** —
  Discard changes and Save on the flow edit page, Delete draft and Save
  draft/Publish on the form edit page, Delete draft and Publish on the form
  show page — so every CTA reads to the toggle's right.
- **The Show/Edit and Auto-refresh toggles are a size up** (`h-6 w-11`
  track, `h-5 w-5` knob, was `h-5 w-9`/`h-4 w-4`) to match the now-larger
  buttons beside them.
- **A page notice (e.g. "Saved.") is a full-width banner** —
  `bg-green-50 p-6 rounded-lg w-full my-3 text-sm` — instead of a small
  line of green text.
- **`.ff-node` is a fixed width (`180px`), not a `min-width`** — an editable
  node holds a `<select>` a read-only one doesn't, which let the shrink-to-fit
  `min-width` stretch it wider than its read-only twin; every node is now the
  same width in both modes regardless of content.

## v0.17.0

### `FormFlow.Web.CoreComponents`, and a `components` override attr

**New: `FormFlow.Web.CoreComponents`**, a Phoenix 1.8-generated, Tailwind
and daisyUI-styled components module (ported from `examples/demo`'s),
FormFlow's own UI renders through by default. **New:
`FormFlow.Web.ComponentResolver`**, mirroring `DynamicForm`'s
`ComponentResolver` (`deps/dynamic_form`): dispatches per function, falling
back to the built-ins only for whatever a host's own module doesn't define.

- **New `components` attr** on `FormFlow.Web.router/1`, reaching every
  LiveComponent on both sides — including the template Index/New pages,
  which skip `flow_types`/`form_types`/`callback_data` since a styling
  override is not a type callback. `nil` (the default) renders everything
  with the built-ins.
- Unlike `DynamicForm.ComponentResolver`, there is no `Application.get_env`
  fallback — consistent with `FormFlow.Config` having been removed in
  v0.16.0 in favor of everything being an explicit attr, `components` is
  attribute-only.
- **New `FormFlow.Web.Components.Core`**, thin HEEx wrappers
  (`<Core.button>`, `<Core.error>`, `<Core.input>`, `<Core.table>`,
  `<Core.list>`) around `FormFlow.Web.ComponentResolver.render/3`, so
  FormFlow's own templates dispatch through a host's `components` module the
  same way a raw `<.button>` would. Every admin (templates) and user-facing
  (instances) LiveComponent's buttons, inline error messages, the flow
  creation form's Name/Slug inputs, and the review type's changed-answers
  table and reviewed-answers list now render through it — a role="switch"
  toggle and Slab's own listing tables are left as they were, since neither
  has a `CoreComponents` equivalent. Most buttons keep their exact prior
  Tailwind classes via `Core.button`'s `class` override; a handful of
  primary calls to action (New flow, New form, Create flow, Publish, Save &
  Continue) adopt `variant="primary"`'s daisyUI look instead.
- Passing a host's `components` module into `<DynamicForm.form>` calls is
  still a follow-up, not done here.

### The user-facing mount root is the listing

**Breaking: the user-facing URLs lost their `/flows` segment.** With
`base="/users"`, the listing is `/users`, an instance is `/users/:id`, and a
form inside it is `/users/:id/forms/*path` and `/users/:id/forms/*path/edit`.
The landing page the mount root used to draw is gone with the segment. The
user-facing side has one section, so its mount root is that section's
index; the template side keeps its landing page and its `/flows` and
`/forms` segments because it has two. `FormFlow.Web.Instances.Paths` builds
the new shape, so every link and redirect the components make follows.
Nothing redirects from the old URLs; a host with links to `/users/flows/…`
updates them.

### The flows a page names are the flows it lists

**`flows` narrows the listing, not only the flows to start.** When the
`instances` attr is left to its default, the listing shows the current
user's own instances of the flows named by `flows` — so a page mounted
for Dog License lists the user's Dog License instances and not their
renewals. `flows` omitted (or `nil`) keeps today's behaviour, the user's
own instances of every flow. A host's own `instances` query is never
narrowed by what the page offers to start.

- **The instance pages refuse an instance of a flow the page did not name.**
  With `flows` set, `FormFlow.Web.Instances.Flows.Show`, `Forms.Show`, and
  `Forms.Edit` render "This flow is not available here." for an instance of
  any other flow, before the host's `on_mount` is asked and before `Edit`
  starts anything — the counterpart of the listing refusing to start a flow
  it did not offer. `flows` omitted accepts every instance, as before.
  `FormFlow.Web.Instances.Forms.Shared.resolve_flows/2` resolves the attr —
  structs, slugs in the tenant — for the listing and the pages alike.
- **`FormFlow.Data.Instances.Flows.list_query/1` and `list/1` take
  `flow:`** — a `FormFlow.Data.Templates.Flow`, an id, or a slug, or a list
  of them; `[]` matches nothing. `narrow_flow/2` applies the same to any
  query over instances, beside `narrow_tenant/2`. Slugs are per tenant, so
  a slug alone matches in every tenant; pair it with `tenant_id:`.

## v0.16.0

### Every entry point takes values: `FormFlow.Config` is gone

**Removed: `FormFlow.Config`**, its behaviour, `use FormFlow.Config`,
`FormFlow.Config.Default`, and the `config` and `config_data` attrs. Nothing
in the library reaches back into a host module by convention any more:
every way a host shapes a page is a value it passes to the router or the
LiveComponents. The `FormFlow.Config.*` namespace stays for the structs and
behaviours a host builds with — `Flows.Type`, `Forms.Type`, `Perspective`,
`Property`.

- **`flow_types` and `form_types` attrs** replace `enabled_flow_types/2`
  and `enabled_form_types/2`: lists of the type structs, defaulting to
  `FormFlow.Config.Flows.Type.defaults/0` and
  `FormFlow.Config.Forms.Type.defaults/0`. They are the one thing that must
  be the same value on the admin pages and on every instance page, since a
  type chosen on one side acts on the other — a host keeps them in one
  function of its own and passes it everywhere. The rule that flow types
  apply to "forms" flows only is the pages' now, not each list's.
- **`callback_data` replaces `config_data`**: the host's own map, passed
  unmodified as the second argument of every callback FormFlow calls — the
  types' and `on_mount` — beside the `FormFlow.Context`. Every type callback
  keeps its arity; only the name changed.
- **`on_mount` replaces `handle_instance_mount/2`**: a function of the
  page's context and `callback_data` returning the same three answers, asked
  on every user-facing page before anything is drawn. `nil` allows
  everything. A host shares one gate across pages by pointing at the same
  function.
- **`instances` replaces `flow_instances_query/2`**: the listing's query,
  `nil` for the user's own. **`flows` replaces `enabled_instance_flows/2`**:
  the templates the listing offers to start, structs or slugs, `nil` for
  every root of the tenant. The router's `tenant_id` is applied on top of
  both, as before.

## v0.15.0

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

*Superseded within this release by "Every entry point takes values" below:
the two callbacks became the `instances` and `flows` attrs, with the same
defaults and tenant handling.*

**New: `flow_instances_query/2` on `FormFlow.Config`.** The listing page
shows whatever query the host's config returns — by default the current
user's own flow instances, exactly as before. A reviewer's desk returns
`FormFlow.Data.Instances.Flows.list_query/1` bare to list everyone's; a
host with finer rules layers its own `where` on top. The router's
`tenant_id` is applied after the callback answers, so a multitenant host
never lists across tenants by accident, and the host never has to think
about tenants in its query (`FormFlow.Data.Instances.Flows.narrow_tenant/2`
is the public helper that does it).

- **Breaking: `handle_mount/2` is now `handle_instance_mount/2`.** The
  config module serves both sides of the router, so callbacks only one side
  reads say which in their name: `enabled_flow_types/2` and
  `enabled_form_types/2` stay as they are because the template and instance
  pages both read them, while this one — like `flow_instances_query/2` — is
  instance-only.
- **New: `enabled_instance_flows/2` on `FormFlow.Config`.** The flows the
  listing offers to start — by default every root of the tenant not made
  reusable, exactly as before. An entry point for one flow names it by slug;
  a reviewer's desk returns `[]` and the picker disappears. `nil` entries are
  dropped, the router's `tenant_id` is applied on top, and the page refuses
  to start a flow it did not offer. Ignored by the template pages.
- **`handle_instance_mount/2` now gates the listing as well.** Every user-facing page
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

### Perspectives: which kinds of user a flow is for

**New: `perspectives` on `FormFlow.Config.Flows.Type`**, a list of
`FormFlow.Config.Flows.Perspective` structs beside the type's `properties` —
the kinds of user a flow of that type can be for, each with an `id`, a
`name`, a `description`, and whatever the host wants to carry in
`metadata`. Roles belong with the type that gives them meaning: a review
type declares its reviewers and approvers, a plain wizard declares none. The
host's config sets the list when it builds the type structs in
`enabled_flow_types/2`, the library's built-in wizards included. When the
chosen type declares some, the identity form of a "forms" flow — the
drill-in page of a subflow, or a simple flow's own — gains a Perspectives
multi-select under the type dropdown, and the admin says which kinds of
user that flow's forms are for: "this subflow is for applicants, this one
for reviewers". The picked ids are stored on the flow under
`properties["perspectives"]`; none means everyone. Perspective is set on a
flow of forms and nowhere else — the forms inside read their flow's, and a
flow whose forms belong to different perspectives is split into subflows.
There are no per-form or per-node overrides, by design. The library's
types declare nothing, which shows no field and stores nothing.

The property *states* which perspectives a flow is for; what that means is
the flow type's to implement:

- **New: `visible?/2` on `FormFlow.Config.Flows.Type`** — whether the flow's
  forms are for this viewer at all. The default reads the stored
  perspectives against the viewer's: a flow naming none is for everyone, a
  viewer with none sees everything, otherwise they must share one. The
  pages ask it before `editable?/2`, which stays the order rule alone, so a
  type never repeats the perspective test. A type that wants "visible to
  everyone, worked by some" overrides `visible?/2` and keeps the default
  `editable?/2`.
- **The viewer's perspectives arrive through a `perspectives` attr** on
  `FormFlow.Web.router/1` and every instance LiveComponent — a string or a
  list of ids, `[]` by default — and reach every callback as
  `FormFlow.Context.perspectives`. `FormFlow.Context.flow_perspectives`
  carries the structs the `:subflow` is for, resolved through its type,
  so a type sees the host's metadata, not just the id.
- **The instance pages consume it.** The flow instance's page lists only
  the forms for the viewer; a position for another perspective is refused
  by name, started or not, on both form pages; after a submit the viewer
  moves to the nearest form that is theirs, skipping other perspectives'
  flows; and when every form they can see is done but the instance is not,
  the page says their part is done. `Flows.complete?/1` is unchanged —
  completion is about the instance, visibility about the viewer.
- **Perspective is routing and hiding, not authorization.** The gate is
  still `handle_instance_mount/2`.
- The template Show page names a flow's perspectives beside its type, and
  the canvas names them on each form subflow node, under a user icon —
  read-only there, since they are set on the subflow's own page; the ids
  ride the node's data as a display projection the save drops. A stored id
  the type no longer declares is flagged on the edit page and dropped on
  the next save, as a stale related-form choice is.
- Every instance LiveComponent now also receives `uri` and `params` from
  the router, whether or not it reads them today, so a host rendering the
  components directly passes one set of attrs that never needs rewiring.

## v0.14.0

Not released — the version went from v0.13.0 straight to v0.15.0.

## v0.13.0

Both instance schemas gained the host identities they carry today:
`FormFlow.Data.Instances.Form` gained `user_id`, and it and
`FormFlow.Data.Instances.Flow` both gained `tenant_id` — opaque host values,
stamped at creation and immutable afterwards, that FormFlow enforces nothing
with. `tenant_id` became an optional attr on `FormFlow.Web.router/1` and the
instance LiveComponents, and `FormFlow.Data.Instances.Flows.list_query/1`
narrows by both. The templates got the same treatment in v0.15.0, which is
where the whole of it is written up.

**Breaking: the v01 migration changed** — `form_flow_instance_flows` gained
`tenant_id`, `form_flow_instance_forms` gained `user_id` and `tenant_id`, and
both gained indexes on them. Drop and recreate any database migrated before
this version.

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

## v0.9.0

Flow types blocked out: a flow carries a type, `FormFlow.Config` grew the
override format that describes one, and the flow pages and the canvas act on
it. The editor gained a vertical node menu, and the flow edit and show pages
a round of refinements.

## v0.8.0

The first user-facing UI: `FormFlow.Web.Instances.Flows.Show` and
`Instances.Forms.Show`, and the routes that reach them, so a user could see a
flow instance and the answers inside it rather than only the admin's side of
it. The config module moved to its own file.

## v0.7.0

The first pass at instance data: `FormFlow.Data.Instances.Flow` and
`Instances.Form`, and the progress derived over them — where a user is in a
flow and which forms are done. No UI yet; that arrived in v0.8.0. The module
config pattern was wired up alongside.

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

## v0.5.0

Form preview, so an admin could see a draft the way a user will, and delete
draft alongside publish. The index pages became `Slab.table`s.

## v0.4.0

Subflows and reusable flows: a flow can embed another, in the data and on the
canvas. Forms arrived beside them — form versioning, form CRUD, forms
connected to flow nodes, and the form template UX rendered with
`DynamicForm`. The editor learned to warn about unsaved changes on every way
out of the page: an Elixir navigation, a browser back/forward, and closing
the tab.

## v0.3.0

The shape of the library: the module structure, the migration pattern hosts
run inside their own migrations, the pattern for a LiveComponent shipping its
own JavaScript, and the ReactFlow integration. Graph data got its migrations
and schemas, and `examples/demo` was added — a real Phoenix app to exercise
all of it against.

## v0.2.0

The initial library skeleton, packaged: mix metadata, a licence, ex_doc, and
the guides scaffolding.
