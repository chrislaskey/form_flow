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

  | Path                                  | LiveComponent |
  |---------------------------------------|---------------|
  | `/`                                   | a landing linking Journeys |
  | `/journeys`                           | `FormFlow.Web.Instances.Flows.Index` (the user's journeys + starting new ones) |
  | `/journeys/:id`                       | `FormFlow.Web.Instances.Flows.Show` (positions and their progress) |
  | `/journeys/:id/instances/:instance_id`| `FormFlow.Web.Instances.Forms.Show` (the form itself) |

  Drill-in URLs carry the *node* id, not the child flow's or form's id — a
  reusable subflow or form used twice in one root is two nodes, so two
  unambiguous URLs. Versions get an explicit id suffix because several drafts
  may coexist and nothing else disambiguates them.

  `base` is the path prefix the catch-all is mounted under, so the components
  build working navigation links — `live "/admin/*path", ...` needs
  `base="/admin"`; the default suits a root-level catch-all.

  Users can opt to directly call LiveComponents instead.
  """

  attr(:type, :string, values: ["instances", "templates"], default: "instances")
  attr(:path, :any, required: true, doc: "the remaining path, as a string or `*path` segments")

  attr(:base, :string, default: "")

  attr(:user_id, :string,
    required: true,
    doc:
      "opaque host identity of the current user — stamped as the creator " <>
        "of journeys started here and as the acting user on instance " <>
        "events. Never interpreted by the library; auth stays the host's job"
  )

  attr(:config, :atom,
    default: nil,
    doc: "a module using `FormFlow.Config`, for customizing the router's behavior"
  )

  attr(:config_data, :map,
    default: %{},
    doc:
      "passed through unmodified to every `:config` callback; ignored when `:config` is not set"
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
              uri={@uri}
              params={@params}
            />
          <% :new -> %>
            <.live_component module={Flows.New} id="flows-new" base={@base} />
          <% {:show, id} -> %>
            <.live_component
              module={Flows.Show}
              id="flows-show"
              flow_id={id}
              base={@base}
              config={@config}
              config_data={@config_data}
            />
          <% {:edit, id} -> %>
            <.live_component
              module={Flows.Edit}
              id="flows-edit"
              flow_id={id}
              base={@base}
              config={@config}
              config_data={@config_data}
            />
          <% {:node_show, root_id, node_id} -> %>
            <.live_component
              module={Flows.Show}
              id="flows-show"
              root_id={root_id}
              node_id={node_id}
              base={@base}
              config={@config}
              config_data={@config_data}
            />
          <% {:node_edit, root_id, node_id} -> %>
            <.live_component
              module={Flows.Edit}
              id="flows-edit"
              root_id={root_id}
              node_id={node_id}
              base={@base}
              config={@config}
              config_data={@config_data}
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
              uri={@uri}
              params={@params}
            />
          <% :new -> %>
            <.live_component module={Forms.New} id="forms-new" base={@base} />
          <% {:show, form_id, version_id} -> %>
            <.live_component
              module={Forms.Show}
              id="forms-show"
              form_id={form_id}
              version_id={version_id}
              base={@base}
            />
          <% {:edit, form_id, version_id} -> %>
            <.live_component
              module={Forms.Edit}
              id="forms-edit"
              form_id={form_id}
              version_id={version_id}
              base={@base}
            />
          <% {:node_show, root_id, node_id, version_id} -> %>
            <.live_component
              module={Forms.Show}
              id="forms-show"
              root_id={root_id}
              node_id={node_id}
              version_id={version_id}
              base={@base}
            />
          <% {:node_edit, root_id, node_id, version_id} -> %>
            <.live_component
              module={Forms.Edit}
              id="forms-edit"
              root_id={root_id}
              node_id={node_id}
              version_id={version_id}
              base={@base}
            />
          <% nil -> %>
            <%!-- not a /forms path --%>
        <% end %>
      <% else %>
        <div :if={segments(@path) == []}>
          <h2 class="mb-2 text-sm font-semibold">Instances</h2>
          <ul class="space-y-1 text-sm">
            <li>
              <.link navigate={"#{@base}/journeys"} class="text-cyan-600 hover:underline">
                Journeys
              </.link>
              <span class="text-xs text-zinc-500">— flows being filled out</span>
            </li>
          </ul>
        </div>

        <%= case journeys_route(@path) do %>
          <% :index -> %>
            <.live_component
              module={Instances.Flows.Index}
              id="journeys-index"
              base={@base}
              user_id={@user_id}
            />
          <% {:show, id} -> %>
            <.live_component
              module={Instances.Flows.Show}
              id="journeys-show"
              journey_id={id}
              base={@base}
              user_id={@user_id}
            />
          <% {:fill, journey_id, instance_id} -> %>
            <.live_component
              module={Instances.Forms.Show}
              id="instance-forms-show"
              journey_id={journey_id}
              instance_id={instance_id}
              base={@base}
              user_id={@user_id}
            />
          <% nil -> %>
            <%!-- not a /journeys path --%>
        <% end %>
      <% end %>
    </div>
    """
  end

  defp journeys_route(path) do
    case segments(path) do
      ["journeys"] -> :index
      ["journeys", id] -> {:show, id}
      ["journeys", journey_id, "instances", instance_id] -> {:fill, journey_id, instance_id}
      _other -> nil
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
