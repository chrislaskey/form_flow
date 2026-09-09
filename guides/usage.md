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

* **`flows`** — which flow templates the page is about, as
  `FormFlow.Data.Templates.Flow` structs or slugs. The page offers them to
  start and refuses to start any other; its instance pages refuse an
  instance of any other; and, when `instances` is left to its default, the
  listing shows the user's own instances of them alone. Omitted, the page
  is about every root flow of the tenant.
* **`instances`** — whose instances the listing shows, as an Ecto query
  over `FormFlow.Data.Instances.Flow`. Omitted, the current user's own.
  `FormFlow.Data.Instances.Flows.list_query/1` builds one: with no options
  it is every instance of every user; `user_id:`, `tenant_id:`, and `flow:`
  narrow it; `narrow_flow/2` and `narrow_tenant/2` do the same to a query
  the host wrote.
* **`perspectives`** — which kind of user is looking, as one or more of the
  perspective ids the host declared on its flow types. Each "forms" flow in
  a template is for one or more perspectives, set by the administrator; the
  instance page and the form pages show the viewer the flows for their
  perspectives and refuse the others, and say "your part is done" when the
  viewer's forms are complete and the instance is not. A viewer with no
  perspective sees every form.

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

## Three pages

A licensing host with two root flows, "Dog License" (slug `dog-license`)
and "Cat License". The host's flow types declare two perspectives,
`applicant` and `reviewer`; the administrator has built Dog License as two
subflows, Intake for the applicant and Review for the reviewer.

### One flow at one URL

The applicant's page is about Dog License and nothing else.

    live "/users/applications/*path", MyAppWeb.ApplicationsLive

    <FormFlow.Web.router
      path={@path} params={@params} uri={@uri}
      base="/users/applications"
      user_id={@current_user.id}
      perspectives="applicant"
      flows={["dog-license"]}
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
      flows={[]}
      flow_types={Types.flow_types()}
      form_types={Types.form_types()}
      on_mount={&MyApp.FormFlow.Gate.staff_only/2}
    />

`instances` with no options is every instance of every user; `flows={[]}`
offers nothing to start, since applicants start applications and reviewers
do not. `/staff/reviews/:id` shows the reviewer Review and hides Intake; the
same instance seen from the applicant's page shows the reverse.

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

## Years, pilots, and closing a flow

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
`flows={["dog-license-2027"]}` sees nothing of it, not even an instance
they somehow have. An admin opens it from the flow's show page (the status
badge in the header opens a dialog), from the flows index (the row's ⋮
menu), or from the edit page (the Status field under the canvas, saved with
everything else). **Pre-release** is a draft that some people may use:
the router's `pre_release_user_ids` names them, by the host's own user
ids, and to them the flow is open — offered, continued, seen — while to
everyone else it stays a draft. The pages are the gate; the data layer
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
3. Point the applicants' page at it — `flows={["dog-license-2027"]}` — or,
   if the page names both years, leave 2026 in the list: a user with a 2026
   instance still sees it there.
4. Open 2027. Move 2026 to winding down on the deadline, or the day the
   new one opens.

A pre-release is the same flow with a smaller audience: move it to
**Pre-release** and name the people in `pre_release_user_ids` on the page
that should offer it; when it has proved itself, open it. The pre-release
instances stay in the flow, marked — duplicate the flow before opening if
the trial run must not mix with the real one. A rule change from a date —
"filings after 1 July need a certificate" — is a copy opened on the date
while the original winds down.

Two things follow for host code. The status is the pages' rule, not the
data layer's: `FormFlow.Data.Instances.Flows.create/2` and
`FormFlow.Data.Instances.Forms.update_status/4` do what they are asked,
so that your own admin and support tooling can take an appeal after the
deadline or repair a record in an archived year without a back door. A
route of your own that should honour the status asks
`FormFlow.Data.Templates.Flow.allows?/2` first, as the pages do. And a
gate or
callback that keys on `context.form_node.slug` sees the copy's prefix
(`dog-license-2027_owner`, not `dog-license-2026_owner`): key on the part
after the `_`, or on `context.form.slug` when the step reuses a catalog
form, which is the same lineage in both years.

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
