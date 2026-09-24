# Usage

FormFlow has two sides, and a host application mounts each where it wants
them. The **template** side is where an administrator builds flows and forms;
the **user-facing** side is where people fill them in. Both are served by
one component, `FormFlow.Web.router/1`, dispatching the remainder of a
Phoenix catch-all route to the right LiveComponent. This guide is about the
user-facing side: what the URLs look like, what the attrs decide, and three
pages a host typically builds.

## The user-facing mount

    # router.ex
    live "/users/*path", MyAppWeb.ApplicationsLive

    # applications_live.ex
    def handle_params(params, uri, socket) do
      {:noreply,
       socket
       |> assign(:path, Map.get(params, "path", []))
       |> assign(:params, params)
       |> assign(:uri, uri)}
    end

    def render(assigns) do
      ~H"""
      <FormFlow.Web.router
        path={@path}
        params={@params}
        uri={@uri}
        base="/users"
        user_id={@current_user.id}
        flow_types={MyApp.FormFlow.Types.flow_types()}
        form_types={MyApp.FormFlow.Types.form_types()}
      />
      """
    end

The mount root is the listing. With `base="/users"`:

| URL                                | Page |
|------------------------------------|------|
| `/users`                           | the user's flow instances, and the flows they can start |
| `/users/:id`                       | one instance: its forms and their progress |
| `/users/:id/forms/*path`           | the answers at one form, read-only |
| `/users/:id/forms/*path/edit`      | the form itself — opening this page is what starts it |

There is no landing page and no `/flows` segment on this side: it has one
section, so the root is its index. (The template side keeps both, because it
has two — flows and the reusable forms catalog.) `*path` is the chain of
node ids from the root flow down to the form, one segment per subflow. Every
link the components render is built from `base` by
`FormFlow.Web.Instances.Paths`, so a host that mounts the router at a
`base` never writes one of these URLs itself.

`uri` and `params` are always passed: the listing's table takes its sorting
and pagination from them.

## What the attrs decide

Three attrs shape what a page lists and offers, each defaulting to no
narrowing. They are listing conveniences, not access control — `on_mount`
is the gate.

* **`flows`** — which flow templates the page is about, and what it lets a
  user do with each: a list of `FormFlow.Config.Flows.Allowed`, built with
  `Allowed.new(flow_slug: "dog-license")`. Each names one flow — by `flow`,
  `flow_id` or `flow_slug`, exactly one of the three — and answers two
  questions about it: `start` a new journey here, and `continue` work
  inside one. Both are `true` unless you say otherwise; `start: true` with
  `continue: false` is refused, since the page would begin a journey it
  then will not open. Naming a flow is what lets the page see it at all:
  its instance pages refuse an instance of a flow the list leaves out, and
  when `instances` is left to its default, the listing shows the user's own
  instances of the named flows alone. Omitted, the page is about every root
  flow of the tenant, everything allowed — so a flow authored later turns
  up on its own. The flow's status is asked as well, and an action needs
  both: a `winding_down` flow is not offered however this attr reads.
* **`instances`** — whose instances the listing shows, as an Ecto query
  over `FormFlow.Data.Instances.Flow`. Omitted, the current user's own.
  `FormFlow.Data.Instances.Flows.list_query/1` builds one: with no options
  it is every instance of every user; `user_id:`, `tenant_id:`, `flow:`,
  and `status:` (the instance's own, `"in_progress"` or `"completed"`)
  narrow it; `narrow_flow/2` and `narrow_tenant/2` do the same to a query
  the host wrote.
* **`perspectives`** — which kind of user is looking, as one or more of the
  perspective ids the host declared on its flow types. Each "forms" flow in
  a template is for one or more perspectives, set by the administrator; the
  instance page and the form pages show the viewer the flows for their
  perspectives and refuse the others, and say "your part is done" when the
  viewer's forms are complete and the instance is not. A viewer with no
  perspective sees only the flows that name no perspective - the flows for
  everyone.

Two more decide who may see a page at all and what the host's callbacks
receive:

* **`on_mount`** — a function of the page's `FormFlow.Context` and
  `callback_data`, asked before every user-facing page draws. `nil` allows;
  `{:ok, assigns}` allows and merges assigns; `{:error, message}` renders
  the message alone; `{:redirect, to}` navigates. The listing asks it too.
* **`callback_data`** — the host's own map, passed unmodified as the second
  argument of every callback FormFlow makes: `on_mount` and the type
  callbacks alike.

A callback or gate that needs to know *which step* it is about reads
`context.form_node.slug` — the step's slug, set on the step's page and
stable across environments where node ids differ. `context.form.slug` is a
catalog form's, shared by every flow reusing it, and `nil` for a form a
step owns.

`tenant_id`, when the host has tenants, is applied on top of everything.

## Flow types, for both kinds of flow

A flow has a type, chosen by the administrator on its identity form and on
its step on the canvas, and the type is where a host teaches FormFlow how
its flows are worked. One struct, `FormFlow.Config.Flows.Type`, serves both
kinds of flow; its `kind` says which. A host passes one list as the
router's `flow_types`, both kinds together, and every page offers a flow the
types of its kind.

* **`:forms`** types are for a "forms" flow: how its forms are presented.
  The library ships the in-order wizard and the any-order wizard. A type
  answers `visible?/2` (whose forms these are - the perspectives test by
  default), `editable?/2` (the order rule), `handle_complete/2` (where the
  user goes next), and `progress_component/1`.
* **`:subflows`** types are for a "subflows" flow: the order its subflows
  are worked in. The library ships **In order** - a subflow opens when the
  ones before it are done - and **Any order** - any unfinished subflow can
  be worked. A type answers `enterable?/2` (may this step be entered now)
  and `handle_complete/2` (which step comes next).

The two compose down the tree. To edit a form, every "subflows" flow above
it must say the step on the way down may be entered, and then the form's
own "forms" type must say the form may be edited. A Dog License that is In
order holding a License Info subflow that is In order holding an Applicant
wizard: the applicant's second form waits for the first (the wizard), the
Licensing subflow waits for Applicant (License Info), and the Reviewer
subflow waits for everything before it (Dog License). Switch Dog License to
Any order and the reviewer may start on day one - while License Info still
opens Licensing only after Applicant. Perspective is checked before any of
this: a form that is not the viewer's is refused whatever the doors say.

    def flow_types do
      FormFlow.Config.Flows.Type.defaults() ++ [checklist(), side_by_side()]
    end

    defp side_by_side do
      %FormFlow.Config.Flows.Type{
        id: "side_by_side",
        kind: :subflows,
        module: MyApp.FormFlow.SideBySide,
        name: "Side by side"
      }
    end

## Three pages

A licensing host with two root flows, "Dog License" (slug `dog-license`)
and "Cat License". The host's flow types declare two perspectives,
`applicant` and `reviewer`; the administrator has built Dog License as two
subflows, Intake for the applicant and Review for the reviewer.

### One flow at one URL

The applicant's page is about Dog License and nothing else. Every page below
aliases the struct the `flows` attr takes:

    alias FormFlow.Config.Flows.Allowed

    live "/users/applications/*path", MyAppWeb.ApplicationsLive

    <FormFlow.Web.router
      path={@path} params={@params} uri={@uri}
      base="/users/applications"
      user_id={@current_user.id}
      perspectives="applicant"
      flows={[Allowed.new(flow_slug: "dog-license")]}
      pre_release_user_ids={MyApp.Licensing.pre_release_user_ids()}
      flow_types={Types.flow_types()}
      form_types={Types.form_types()}
    />

`/users/applications` lists the applicant's own Dog License instances — not
their Cat License, not their renewals — with one "Start" button.
`/users/applications/:id` is one of them, showing Intake and hiding Review.
Opening `/users/applications/:id` for a Cat License instance is refused,
because the page did not name that flow.

### A reviewer's page

The reviewer's page lists every applicant's instance and shows the reviewer
their part of each.

    live "/staff/reviews/*path", MyAppWeb.ReviewsLive

    <FormFlow.Web.router
      path={@path} params={@params} uri={@uri}
      base="/staff/reviews"
      user_id={@current_user.id}
      perspectives="reviewer"
      instances={FormFlow.Data.Instances.Flows.list_query()}
      flows={[Allowed.new(flow_slug: "dog-license", start: false)]}
      flow_types={Types.flow_types()}
      form_types={Types.form_types()}
      on_mount={&MyApp.FormFlow.Gate.staff_only/2}
    />

`instances` with no options is every instance of every user. `flows` names
the same flow the applicant's page names, with `start: false`, since
applicants start applications and reviewers do not — so this page has no
Start section at all. `/staff/reviews/:id` shows the reviewer Review and
hides Intake; the same instance seen from the applicant's page shows the
reverse.

Name the flows a reviewer reviews rather than leaving the attr off. A flow
authored next year should reach a reviewer because you said so, not because
somebody saved a draft.

The listing itself does not yet filter by the viewer's perspective — an
instance still in Intake is listed here too, with nothing for the reviewer
to do inside it yet. Because the listing is wider than the user's own, the
page is gated:

    def staff_only(%FormFlow.Context{} = context, _callback_data) do
      if MyApp.Accounts.staff?(context.user_id), do: nil, else: {:error, "Staff only."}
    end

### Two flows on two pages

Renewals are a separate root flow at an unrelated URL: a second mount, a
second `flows`.

    live "/users/applications/*path", MyAppWeb.ApplicationsLive
    live "/users/renewals/*path", MyAppWeb.RenewalsLive

Each page passes its own `base` and names its own flow. Nothing is shared
between them but the type lists — the one value that must be the same on
every page, the admin pages included, because a type chosen on one side
acts on the other.

## Years, pre-release, and closing a flow

A flow is not versioned. Dog License 2026 and Dog License 2027 are two
flows, the second a copy of the first, and the difference between "this
year's" and "last year's" is each flow's **status** — the one fact a flow
keeps about what users may do with it.

| Status | Start a new instance | Continue one | See their instances |
|---|---|---|---|
| `draft` | no | no | no |
| `pre_release` | the page's pre-release users | the page's pre-release users | the page's pre-release users |
| `open` | yes | yes | yes |
| `winding_down` | no | yes | yes |
| `read_only` | no | no | yes |
| `archived` | no | no | no |

A flow is born a **draft**: built, checked, and never offered — a user with
`flows={[Allowed.new(flow_slug: "dog-license-2027")]}` sees nothing of it,
not even an instance they somehow have. An admin opens it from the flow's show page (the status
badge in the header opens a dialog), from the flows index (the row's ⋮
menu), or from the edit page (the Status field under the canvas, saved with
everything else). **Pre-release** is a draft that some people may use:
the router's `pre_release_user_ids` names them, by the host's own user
ids — a list, or a function of the page's `FormFlow.Context` and
`callback_data` that returns one, for a role or a team (`fn context, _data ->
if staff?(context.user_id), do: [context.user_id], else: [] end`; the
context is the page's, with no flow in it, so the rule is per page) — and
to them the flow is open — offered, continued, seen — while to everyone
else it stays a draft. The pages are the gate; the data layer
takes a pre-release start from anyone and marks the instance's `metadata`
with `"form_flow" => %{"pre_release" => true}`, so once the flow opens the
pre-release run's instances can be told from the real ones. **Open** is the
normal state. **Winding down** is a deadline that has passed: the listing
names the flow with "No longer taking new starts." where its Start button
was, and everyone already in it finishes and keeps seeing their record — a
reviewer finishing reviews after applications closed included; this is the
state for "applications closed, reviews continuing". **Read-only** is the
year over:
nobody starts or continues — the edit page says "This flow is read-only
now; your answers are kept as they are." — but everyone still sees, prints,
and downloads their own. **Archived** puts it away: users see nothing of
it, admins keep the flow, its instances, and its history. Draft and
archived allow the same nothing; they differ in meaning, never opened and
put away. Any status can move to any other; every move is logged with who
made it (`FormFlow.Data.Templates.Flow.Event`).

So the year rolls over like this:

1. On Dog License 2026's show page, **Duplicate Flow**: name it "Dog
   License 2027", slug `dog-license-2027`. The copy is a draft, whole —
   steps, connections, subflows, its own forms — with fresh ids.
2. Edit the copy, publish its forms, read its health.
3. Point the applicants' page at it —
   `flows={[Allowed.new(flow_slug: "dog-license-2027")]}` — or, if the page
   names both years, leave 2026 in the list: a user with a 2026 instance
   still sees it there. `Allowed.new(flow_slug: "dog-license-2026",
   start: false)` says the same thing the `winding_down` status says, from
   the page's side rather than the flow's.
4. Open 2027. Move 2026 to winding down on the deadline, or the day the
   new one opens.

A pre-release is the same flow with a smaller audience: move it to
**Pre-release** and name the people in `pre_release_user_ids` on the page
that should offer it; when it has proved itself, open it. The pre-release
instances stay in the flow, marked; as the flow leaves Pre-release, the
status dialog says how many were started during it and offers to delete
them with the change — logged on the flow's history — or duplicate the
flow before opening if the trial run must not mix with the real one. A
rule change from a date — "filings after 1 July need a certificate" — is
a copy opened on the date while the original winds down.

Two things follow for host code. The status is the pages' rule, not the
data layer's: `FormFlow.Data.Instances.Flows.create/2` and
`FormFlow.Data.Instances.Forms.update_status/4` do what they are asked,
so that your own admin and support tooling can take an appeal after the
deadline or repair a record in an archived year without a back door. A
route of your own that should honour the status asks
`FormFlow.Data.Templates.Flow.allows?/2` first — and, since `allows?/2`
answers the table and the table says a pre-release flow is open, checks
its own pre-release users for that one status, as the pages do through
`FormFlow.Web.Instances.Shared.status_allows?/3` — which a route can call
too, with a bare map for the page: `status_allows?(flow, :see,
%{user_id: id, pre_release_user_ids: ids})`. And a gate or
callback that keys on `context.form_node.slug` sees the copy's prefix
(`dog-license-2027_owner`, not `dog-license-2026_owner`): key on the part
after the `_`, or on `context.form.slug` when the step reuses a catalog
form, which is the same form template in both years.

### Prefilling this year from last year

Every form type the library ships carries one setting: **Prefill with
answers from**, on the form's own settings page, naming a form of another
flow. Set it on 2027's identity form to 2026's, and the form opens filled
in with what *this same user* answered there, in their most recent journey
of that flow. The answers go under anything they have typed here, merged
by question name, so a prefill never replaces an answer, and a question
only one of the two forms asks is left alone. A user with no earlier
journey — and a viewer with no `user_id` — gets the empty form an unset
setting gives, with no explanation: nothing crosses between people, and
nothing is said about a year that is not there.

It is a setting an admin makes rather than something read off the copy, on
purpose. A copy records *that* it happened (`copied_from_form_id`), not
that anybody wanted last year's answers carried forward. An admin copies a
flow for a new year, for a regional variant, or to try something out, and
only the first of those means "prefill from the original".

So **copying a flow clears it**. 2028 copied from 2027 arrives with the
field empty rather than still pointing at 2026 — which would resolve
perfectly, at the wrong year. The duplicate dialog lists what it is about
to clear before you confirm. A pointer at a step of the flow's *own* tree
is not cleared: the copy re-points it at the copied steps, where it stays
right.

`FormFlow.Data.Templates.Flows.copy/2` requires `flow_types:` and
`form_types:` for this, and raises without them. Which settings clear is
read off the types, and a copy that silently kept one is not a thing you
can find afterwards.

A pointer that stops resolving — the flow deleted, the step removed, or no
Start reaching it — is one of
`FormFlow.Data.Templates.Flows.Health`'s checks. A pointer that is merely
*old* is not, and cannot be: an old pointer that resolves is not wrong.
Clearing on copy is what handles that one.

A host's own form type offers the same field by putting
`FormFlow.Config.Forms.Type.Default.properties/0` after its own. A setting
of its own can clear on copy too — `clear_on_copy: true` on a
`FormFlow.Config.Property`.

## Taking the answers away

A user looking at a form they have filled in can save it as a PDF or open it
to print. Both are links out of the LiveView, because a LiveView holds a
websocket and cannot send a file, so they need a pair of ordinary routes
mounted once — before any catch-all, and inside a pipeline that
authenticates:

    import FormFlow.Router

    scope "/" do
      pipe_through [:browser, :require_authenticated_user]

      form_flow_router_download_routes()
    end

That is the whole of it. `FormFlow.Web.Instances.Forms.Show` draws Download
PDF and Print once a form has been started, and the route resolves the
position the same way that page does
(`FormFlow.Web.Instances.Forms.Shared.resolve/1`), so what is printed is what
is shown. The two differ by one header: Download sends `attachment`, which
saves a file, and Print sends `inline`, which opens the document in the
browser's own viewer, where the user reads it, prints it, and saves it if
they want to. Exactly how each browser honours that differs between Chrome,
Firefox and Safari; the header is all a server can say about it.

### How a download is authorized

The gate is not asked twice. `FormFlow.Web.Instances.Forms.Show` already ran
your `on_mount`, the flow type's `visible?`, and the page's `flows` scope in
order to decide what to draw, and Download and Print are drawn wherever the
answers are; when the user clicks either it mints a
short-lived encrypted token — 60 seconds by default,
`config :form_flow, download_token_max_age:` — and the request carries that
instead of an argument. The endpoint reads the token and ignores every other
query param, so a token cannot be pointed at a form it was not minted for.

Minting happens on the click rather than when the page was drawn, which is
what lets a tab left open for days still print: the token is always seconds
old, whatever the page is.

Two things follow that are worth knowing:

  * **Anyone holding the URL can redeem it until it expires.** FormFlow
    cannot bind a token to a session without knowing your current user, which
    is the thing the token exists to avoid. Mount the route inside a pipeline
    that authenticates — an anonymous holder is then turned away before
    FormFlow sees the token — and layer any further checks you want in front
    of it. A user who can mint a link can already save the PDF and send that
    instead, so the link is a briefer version of a capability they had.
  * **Your own endpoint gets the same token.** `FormFlow.decode_token/3`
    reads it back:

        def show(conn, %{"token" => token}) do
          case FormFlow.decode_token(conn, token) do
            {:ok, %{user_id: user_id, flow_instance_id: id, path: path}} -> ...
            {:error, :expired} -> ...
            {:error, :invalid} -> ...
          end
        end

### Choosing what the file looks like

The PDF is written by FormFlow itself — no Chrome, no wkhtmltopdf, nothing to
install — and is deliberately plain: a heading, the details, and each
question's answer under its label. Everything about how it is drawn is in
`FormFlow.Web.Downloads.Renderer.PDF.Writer`, which is also where the format's
limits are written down.

Wanting more than that is a renderer, not a setting. FormFlow flattens the
resource into a `FormFlow.Web.Downloads.Document` — headings, fields, values, no
format — and hands it to a `FormFlow.Web.Downloads.Renderer`. Mount a different
one and the same document comes out the other way:

    # a printable HTML page instead, printed through the browser
    form_flow_router_download_routes(renderer: FormFlow.Web.Downloads.Renderer.HTML)

    # or the host's own, usually a real HTML-to-PDF engine
    form_flow_router_download_routes(renderer: MyApp.FormFlowRenderer)

A renderer receives the document, the page's `FormFlow.Context`, and the
host's `callback_data`, and returns bytes and a content type. See
`FormFlow.Web.Downloads.Renderer`.

### Where the links point

One route answers both Download and Print, and the path carries nothing —
the form, the position, and which of the two was clicked all ride in the
query string:

    <download_path>?disposition=download&flow_instance_id=…&path[]=…

So the mount can go anywhere. **Saying where is also what turns downloads
on**: until an application configures a path, the form pages draw no Download
or Print link, which is the right default for an app that does not offer
them. One line sets both the route and the links:

    config :form_flow, download_path: "/form-flow/downloads"

`FormFlow.Web.router/1`'s **`download_path`** attr overrides that for one
mount, which is how a page points somewhere the library does not serve at
all:

    <FormFlow.Web.router
      user_id={@current_user.id}
      path={@path}
      base="/users"
      download_path={~p"/exports/forms"}
    />

Point it at an endpoint of your own and FormFlow declares no route in it:
your controller reads `flow_instance_id`, `path[]` (repeated, one segment per
node, so it arrives as a list) and `disposition` off the query string, and
generates the document however it likes — its own template, its own engine,
its own authorization. The page stops caring what happens after the click.

## Rendering the LiveComponents directly

A host that would rather own its routing can render
`FormFlow.Web.Instances.Flows.Index`, `Flows.Show`, `Forms.Show`, and
`Forms.Edit` itself, passing the same attrs the router does. The links they
render are still built from `base` in the shape above, so the router — or
routes of the same shape — must answer at that `base`, or the links point
at nothing.
