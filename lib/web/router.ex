defmodule FormFlow.Web.Router do
  @moduledoc """
  `FormFlow.Web.Router` module contains an optional path-based router that
  works with Phoenix `*path` catch-all routes and the default routes.

  Using the router simplifies the amount of the parent app has to define.

  Custom installations can skip the router and call the LiveComponents directly
  if that's easier.
  """

  use Phoenix.Component

  alias FormFlow.Web.Instances
  alias FormFlow.Web.Templates.Flows
  alias FormFlow.Web.Templates.Forms

  @doc """
  Optional component to route using the `*path` helper concept in Phoenix
  Routers. Dispatches the remaining path to the matching LiveComponent:

  | Path                                | LiveComponent |
  |-------------------------------------|---------------|
  | `/`                                 | a landing linking the Flows and Forms indexes — the mount root is generic, not owned by either section |
  | `/flows`                            | `FormFlow.Web.Templates.Flows.Index` |
  | `/flows/new`                        | `FormFlow.Web.Templates.Flows.New` |
  | `/flows/:id`                        | `FormFlow.Web.Templates.Flows.Show` |
  | `/flows/:id/edit`                   | `FormFlow.Web.Templates.Flows.Edit` |
  | `/flows/:root/nodes/:node_id`       | `FormFlow.Web.Templates.Flows.Show` (the node's subflow) |
  | `/flows/:root/nodes/:node_id/edit`  | `FormFlow.Web.Templates.Flows.Edit` (the node's subflow) |
  | `/forms`                            | `FormFlow.Web.Templates.Forms.Index` (the catalog) |
  | `/forms/new`                        | `FormFlow.Web.Templates.Forms.New` |
  | `/forms/:id`                        | `FormFlow.Web.Templates.Forms.Show` (latest published, else newest draft) |
  | `/forms/:id/versions/:version_id`   | `FormFlow.Web.Templates.Forms.Show` (a specific version or draft) |
  | `/forms/:id/versions/:version_id/edit` | `FormFlow.Web.Templates.Forms.Edit` (drafts only) |
  | `/flows/:root/nodes/:node_id/form`  | `FormFlow.Web.Templates.Forms.Show` (the node's form, with breadcrumb) |
  | `/flows/:root/nodes/:node_id/form/versions/:version_id` | `FormFlow.Web.Templates.Forms.Show` |
  | `/flows/:root/nodes/:node_id/form/versions/:version_id/edit` | `FormFlow.Web.Templates.Forms.Edit` |

  The routes above serve `type="templates"` (the admin editor).
  `type="instances"` (the default) serves the user-facing side:

  | Path                       | LiveComponent |
  |----------------------------|---------------|
  | `/`                        | `FormFlow.Web.Instances.Flows.Index` (the user's flow instances + starting new ones) |
  | `/:id`                     | `FormFlow.Web.Instances.Flows.Show` (one instance: its forms and their progress) |
  | `/:id/forms/*path`         | `FormFlow.Web.Instances.Forms.Show` (the answers at a position, read-only) |
  | `/:id/forms/*path/edit`    | `FormFlow.Web.Instances.Forms.Edit` (the editable form — the page that opens the position) |

  The user-facing side has no landing page and no `/flows` segment: it has
  one section, so the mount root is its index. `live "/users/*path", ...`
  with `base="/users"` makes `/users` the listing and `/users/:id` an
  instance. The template side keeps both because it has two sections, flows
  and the reusable forms catalog, and needs a root that belongs to neither.

  Every instance component receives `user_id`, `tenant_id`, `perspectives`,
  `flow_types`, `form_types`, `callback_data`, `on_mount`, `instances`,
  `flows`, `uri`, and `params`, whether or not it reads them today — a host
  calling the components directly should pass the same, so a later feature
  that needs one never means rewiring.

  Nothing here reaches back into a host module by convention: every way a
  host shapes a page is a value it passes. The two type lists are the one
  thing that must be the *same* value on the admin pages and on every
  instance page, since a type chosen on one side acts on the other — a host
  keeps them in one function of its own and passes it everywhere.

  The two sides use the same nouns on purpose: the mount root already says
  which world you are in, so `/admin/flows/:id` is a flow *template* and
  `/users/:id` is a flow *instance* — the names
  `FormFlow.Data.Templates.Flow` and `FormFlow.Data.Instances.Flow` already
  give themselves.

  Drill-in URLs carry the *node* id, not the child flow's or form's id — a
  reusable subflow or form used twice in one root is two nodes, so two
  unambiguous URLs. Versions get an explicit id suffix because several drafts
  may coexist and nothing else disambiguates them.

  On the instances side a form is addressed by its **position** rather than by
  its instance row: `*path` is the chain of node ids from the root flow down
  to the form node — the same `path` a `FormFlow.Data.Instances.Form` stamps
  at creation — so a form two subflows deep has three segments. The template
  side needs no such chain, because every path to a shared subflow reaches
  the same template; two paths through an *instance* are two different sets
  of answers. Addressing the position also means the URL exists before the
  row does, which is what makes every navigation to a form an ordinary link:
  `/edit` is the one page that opens a position (see
  `FormFlow.Web.Instances.Forms.Edit`), and `FormFlow.Web.Instances.Paths`
  builds all of them.

  `base` is the path prefix the catch-all is mounted under, so the components
  build working navigation links — `live "/admin/*path", ...` needs
  `base="/admin"`; the default suits a root-level catch-all.

  The usage guide (`guides/usage.md`) walks through the user-facing mount
  and three pages a host typically builds with these attrs. Users can opt to
  directly call LiveComponents instead.
  """

  attr(:type, :string, values: ["instances", "templates"], default: "instances")
  attr(:path, :any, required: true, doc: "the remaining path, as a string or `*path` segments")

  attr(:base, :string, default: "")

  attr(:user_id, :string,
    required: true,
    doc:
      "opaque host identity of the current user — stamped as the creator " <>
        "of flow instances started here and as the acting user on instance " <>
        "events. Never interpreted by the library; auth stays the host's job"
  )

  attr(:tenant_id, :string,
    default: nil,
    doc:
      "opaque host identity of the current user's tenant — stamped on the " <>
        "flow and form templates created here, on flow instances started " <>
        "here, and on form instances started inside them; the index pages " <>
        "list only that tenant's. Only multitenant hosts set it; the default " <>
        "leaves the column nil. Never interpreted by the library"
  )

  attr(:perspectives, :any,
    default: [],
    doc:
      "the kinds of user the current user is here as — one or more " <>
        "`FormFlow.Config.Flows.Perspective` ids, a string or a list. The " <>
        "instance pages show, offer, and open only the flows for those " <>
        "perspectives; the default, none, sees everything. Ignored by the " <>
        "template pages"
  )

  attr(:flow_types, :list,
    default: FormFlow.Config.Flows.Type.defaults(),
    doc:
      "the `FormFlow.Config.Flows.Type` structs a \"forms\" flow may be given, " <>
        "in display order — the admin pages offer them, the instance pages act " <>
        "on them, so pass the same list to both. Defaults to the library's " <>
        "wizards (`FormFlow.Config.Flows.Type.defaults/0`); a host's list " <>
        "usually starts from those"
  )

  attr(:form_types, :list,
    default: FormFlow.Config.Forms.Type.defaults(),
    doc:
      "the `FormFlow.Config.Forms.Type` structs a form may be given, in display " <>
        "order — the same on both sides, like `flow_types`. Defaults to the " <>
        "library's default and review types (`FormFlow.Config.Forms.Type.defaults/0`)"
  )

  attr(:callback_data, :map,
    default: %{},
    doc:
      "the host's own data, passed unmodified as the second argument of every " <>
        "callback FormFlow calls — the types' and `on_mount` — beside the " <>
        "`FormFlow.Context`. Whatever the page knows that a type may need: a " <>
        "reviewer's region, a prefill source"
  )

  attr(:on_mount, :any,
    default: nil,
    doc:
      "the instance pages' gate: a function of the page's `FormFlow.Context` " <>
        "and `callback_data` returning `{:ok, assigns}` to render (merging the " <>
        "assigns), `{:error, message}` to render the message alone, or " <>
        "`{:redirect, to}`. Asked on every user-facing page, the listing " <>
        "included, before anything is drawn; on the edit page before the form " <>
        "is started. Where a host authorizes by record. `nil` allows everything. " <>
        "Ignored by the template pages"
  )

  attr(:instances, :any,
    default: nil,
    doc:
      "the flow instances the listing shows, as a composable query over " <>
        "`FormFlow.Data.Instances.Flow` — `FormFlow.Data.Instances.Flows.list_query/1` " <>
        "is the building block; `nil` lists the current user's own, of the " <>
        "flows named by `flows` when it names some. The router's `tenant_id` " <>
        "is applied on top. A listing convenience, not access control: gate " <>
        "the page with `on_mount`. Ignored by the template pages"
  )

  attr(:flows, :any,
    default: nil,
    doc:
      "the flow templates the listing is about, in display order — " <>
        "`FormFlow.Data.Templates.Flow` structs or slugs, `nil` entries dropped. " <>
        "The page offers them to start and refuses to start any other, its " <>
        "instance pages refuse an instance of any other, and when `instances` " <>
        "is `nil` the listing shows the user's own instances of them alone. `nil` offers and lists every root flow of the tenant " <>
        "(those not made reusable, for starting). The router's `tenant_id` is " <>
        "applied on top. Ignored by the template pages"
  )

  attr(:uri, :string,
    default: nil,
    doc:
      "the current request URI from handle_params/3; drives the index tables' " <>
        "sortable headers and pagination links"
  )

  attr(:params, :map,
    default: %{},
    doc:
      "the current request params from handle_params/3; carries the index " <>
        "tables' sort and pagination state"
  )

  def router(assigns) do
    ~H"""
    <div>
      <%= if @type == "templates" do %>
        <%!-- The mount root is generic — it belongs to neither section, it
              links to both. `live "/admin/*path", ...` with base="/admin"
              makes /admin this landing, /admin/flows and /admin/forms the
              indexes. --%>
        <div :if={segments(@path) == []}>
          <h2 class="mb-2 text-sm font-semibold">Templates</h2>
          <ul class="space-y-1 text-sm">
            <li>
              <.link navigate={"#{@base}/flows"} class="text-cyan-600 hover:underline">
                Flows
              </.link>
              <span class="text-xs text-zinc-500">— graph-based user flows</span>
            </li>
            <li>
              <.link navigate={"#{@base}/forms"} class="text-cyan-600 hover:underline">
                Forms
              </.link>
              <span class="text-xs text-zinc-500">— the reusable form catalog</span>
            </li>
          </ul>
        </div>

        <%= case flows_route(@path) do %>
          <% :index -> %>
            <.live_component
              module={Flows.Index}
              id="flows-index"
              base={@base}
              tenant_id={@tenant_id}
              uri={@uri}
              params={@params}
            />
          <% :new -> %>
            <.live_component
              module={Flows.New}
              id="flows-new"
              base={@base}
              tenant_id={@tenant_id}
            />
          <% {:show, id} -> %>
            <.live_component
              module={Flows.Show}
              id="flows-show"
              flow_id={id}
              base={@base}
              flow_types={@flow_types}
              form_types={@form_types}
              callback_data={@callback_data}
            />
          <% {:edit, id} -> %>
            <.live_component
              module={Flows.Edit}
              id="flows-edit"
              flow_id={id}
              base={@base}
              flow_types={@flow_types}
              form_types={@form_types}
              callback_data={@callback_data}
            />
          <% {:node_show, root_id, node_id} -> %>
            <.live_component
              module={Flows.Show}
              id="flows-show"
              root_id={root_id}
              node_id={node_id}
              base={@base}
              flow_types={@flow_types}
              form_types={@form_types}
              callback_data={@callback_data}
            />
          <% {:node_edit, root_id, node_id} -> %>
            <.live_component
              module={Flows.Edit}
              id="flows-edit"
              root_id={root_id}
              node_id={node_id}
              base={@base}
              flow_types={@flow_types}
              form_types={@form_types}
              callback_data={@callback_data}
            />
          <% nil -> %>
            <%!-- not a /flows path --%>
        <% end %>

        <%= case forms_route(@path) do %>
          <% :index -> %>
            <.live_component
              module={Forms.Index}
              id="forms-index"
              base={@base}
              tenant_id={@tenant_id}
              uri={@uri}
              params={@params}
            />
          <% :new -> %>
            <.live_component
              module={Forms.New}
              id="forms-new"
              base={@base}
              tenant_id={@tenant_id}
            />
          <% {:show, form_id, version_id} -> %>
            <.live_component
              module={Forms.Show}
              id="forms-show"
              form_id={form_id}
              version_id={version_id}
              base={@base}
              flow_types={@flow_types}
              form_types={@form_types}
              callback_data={@callback_data}
            />
          <% {:edit, form_id, version_id} -> %>
            <.live_component
              module={Forms.Edit}
              id="forms-edit"
              form_id={form_id}
              version_id={version_id}
              base={@base}
              flow_types={@flow_types}
              form_types={@form_types}
              callback_data={@callback_data}
            />
          <% {:node_show, root_id, node_id, version_id} -> %>
            <.live_component
              module={Forms.Show}
              id="forms-show"
              root_id={root_id}
              node_id={node_id}
              version_id={version_id}
              base={@base}
              flow_types={@flow_types}
              form_types={@form_types}
              callback_data={@callback_data}
            />
          <% {:node_edit, root_id, node_id, version_id} -> %>
            <.live_component
              module={Forms.Edit}
              id="forms-edit"
              root_id={root_id}
              node_id={node_id}
              version_id={version_id}
              base={@base}
              flow_types={@flow_types}
              form_types={@form_types}
              callback_data={@callback_data}
            />
          <% nil -> %>
            <%!-- not a /forms path --%>
        <% end %>
      <% else %>
        <%!-- One section, so the mount root is its index: `live "/users/*path", ...`
              with base="/users" makes /users the listing and /users/:id an
              instance. --%>
        <%= case instances_route(@path) do %>
          <% :index -> %>
            <.live_component
              module={Instances.Flows.Index}
              id="instance-flows-index"
              base={@base}
              user_id={@user_id}
              tenant_id={@tenant_id}
              perspectives={@perspectives}
              flow_types={@flow_types}
              form_types={@form_types}
              callback_data={@callback_data}
              on_mount={@on_mount}
              instances={@instances}
              flows={@flows}
              uri={@uri}
              params={@params}
            />
          <% {:flow, id} -> %>
            <.live_component
              module={Instances.Flows.Show}
              id="instance-flows-show"
              flow_instance_id={id}
              base={@base}
              user_id={@user_id}
              tenant_id={@tenant_id}
              perspectives={@perspectives}
              flow_types={@flow_types}
              form_types={@form_types}
              callback_data={@callback_data}
              on_mount={@on_mount}
              instances={@instances}
              flows={@flows}
              uri={@uri}
              params={@params}
            />
          <% {:form, id, form_path} -> %>
            <.live_component
              module={Instances.Forms.Show}
              id="instance-forms-show"
              flow_instance_id={id}
              path={form_path}
              base={@base}
              user_id={@user_id}
              tenant_id={@tenant_id}
              perspectives={@perspectives}
              flow_types={@flow_types}
              form_types={@form_types}
              callback_data={@callback_data}
              on_mount={@on_mount}
              instances={@instances}
              flows={@flows}
              uri={@uri}
              params={@params}
            />
          <% {:form_edit, id, form_path} -> %>
            <.live_component
              module={Instances.Forms.Edit}
              id="instance-forms-edit"
              flow_instance_id={id}
              path={form_path}
              base={@base}
              user_id={@user_id}
              tenant_id={@tenant_id}
              perspectives={@perspectives}
              flow_types={@flow_types}
              form_types={@form_types}
              callback_data={@callback_data}
              on_mount={@on_mount}
              instances={@instances}
              flows={@flows}
              uri={@uri}
              params={@params}
            />
          <% nil -> %>
            <%!-- not an instances path --%>
        <% end %>
      <% end %>
    </div>
    """
  end

  defp instances_route(path) do
    case segments(path) do
      [] -> :index
      [id] -> {:flow, id}
      [id, "forms" | rest] when rest != [] -> form_route(id, rest)
      _other -> nil
    end
  end

  # Everything after `/forms/` is the position — a chain of node ids — with an
  # optional `edit` suffix. Node ids are UUIDs, so "edit" can never be one of
  # them.
  defp form_route(id, rest) do
    case Enum.split(rest, -1) do
      {[], ["edit"]} -> nil
      {path, ["edit"]} -> {:form_edit, id, path}
      _no_suffix -> {:form, id, rest}
    end
  end

  defp flows_route(path) do
    case segments(path) do
      ["flows"] -> :index
      ["flows", "new"] -> :new
      ["flows", id] -> {:show, id}
      ["flows", id, "edit"] -> {:edit, id}
      ["flows", root_id, "nodes", node_id] -> {:node_show, root_id, node_id}
      ["flows", root_id, "nodes", node_id, "edit"] -> {:node_edit, root_id, node_id}
      _other -> nil
    end
  end

  defp forms_route(path) do
    case segments(path) do
      ["forms" | rest] ->
        catalog_forms_route(rest)

      ["flows", root_id, "nodes", node_id, "form" | rest] ->
        node_forms_route(root_id, node_id, rest)

      _other ->
        nil
    end
  end

  defp catalog_forms_route(rest) do
    case rest do
      [] -> :index
      ["new"] -> :new
      [id] -> {:show, id, nil}
      [id, "versions", version_id] -> {:show, id, version_id}
      [id, "versions", version_id, "edit"] -> {:edit, id, version_id}
      _other -> nil
    end
  end

  defp node_forms_route(root_id, node_id, rest) do
    case rest do
      [] -> {:node_show, root_id, node_id, nil}
      ["versions", version_id] -> {:node_show, root_id, node_id, version_id}
      ["versions", version_id, "edit"] -> {:node_edit, root_id, node_id, version_id}
      _other -> nil
    end
  end

  defp segments(path) when is_list(path), do: path
  defp segments(path) when is_binary(path), do: String.split(path, "/", trim: true)
end
