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

## Rendering the LiveComponents directly

A host that would rather own its routing can render
`FormFlow.Web.Instances.Flows.Index`, `Flows.Show`, `Forms.Show`, and
`Forms.Edit` itself, passing the same attrs the router does. The links they
render are still built from `base` in the shape above, so the router — or
routes of the same shape — must answer at that `base`, or the links point
at nothing.
