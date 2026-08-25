defmodule FormFlow.Web.Router do
  @moduledoc """
  `FormFlow.Web.Router` module contains an optional path-based router that
  works with Phoenix `*path` catch-all routes and the default routes.

  Using the router simplifies the amount of the parent app has to define.

  Custom installations can skip the router and call the LiveComponents directly
  if that's easier.
  """

  use Phoenix.Component

  alias FormFlow.Web.Templates.Flows
  alias FormFlow.Web.Templates.Forms

  @doc """
  Optional component to route using the `*path` helper concept in Phoenix
  Routers. Dispatches the remaining path to the matching LiveComponent:

  | Path                                | LiveComponent |
  |-------------------------------------|---------------|
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

  Drill-in URLs carry the *node* id, not the child graph's or form's id — a
  reusable subflow or form used twice in one root is two nodes, so two
  unambiguous URLs. Versions get an explicit id suffix because several drafts
  may coexist and nothing else disambiguates them.

  `base` is the path prefix the catch-all is mounted under, so the components
  build working navigation links — `live "/admin/*path", ...` needs
  `base="/admin"`; the default suits a root-level catch-all.

  Users can opt to directly call LiveComponents instead.
  """

  attr(:type, :string, values: ["instances", "templates"], required: true)
  attr(:path, :any, required: true, doc: "the remaining path, as a string or `*path` segments")

  attr(:app, :string, default: "default")
  attr(:base, :string, default: "")

  def router(assigns) do
    ~H"""
    <div>
      <%= if @type == "templates" do %>
        <%= case flows_route(@path) do %>
          <% :index -> %>
            <.live_component module={Flows.Index} id="flows-index" app={@app} base={@base} />
          <% :new -> %>
            <.live_component module={Flows.New} id="flows-new" app={@app} base={@base} />
          <% {:show, id} -> %>
            <.live_component module={Flows.Show} id="flows-show" graph_id={id} app={@app} base={@base} />
          <% {:edit, id} -> %>
            <.live_component module={Flows.Edit} id="flows-edit" graph_id={id} app={@app} base={@base} />
          <% {:node_show, root_id, node_id} -> %>
            <.live_component
              module={Flows.Show}
              id="flows-show"
              root_id={root_id}
              node_id={node_id}
              app={@app}
              base={@base}
            />
          <% {:node_edit, root_id, node_id} -> %>
            <.live_component
              module={Flows.Edit}
              id="flows-edit"
              root_id={root_id}
              node_id={node_id}
              app={@app}
              base={@base}
            />
          <% nil -> %>
            <%!-- not a /flows path --%>
        <% end %>

        <%= case forms_route(@path) do %>
          <% :index -> %>
            <.live_component module={Forms.Index} id="forms-index" app={@app} base={@base} />
          <% :new -> %>
            <.live_component module={Forms.New} id="forms-new" app={@app} base={@base} />
          <% {:show, form_id, version_id} -> %>
            <.live_component
              module={Forms.Show}
              id="forms-show"
              form_id={form_id}
              version_id={version_id}
              app={@app}
              base={@base}
            />
          <% {:edit, form_id, version_id} -> %>
            <.live_component
              module={Forms.Edit}
              id="forms-edit"
              form_id={form_id}
              version_id={version_id}
              app={@app}
              base={@base}
            />
          <% {:node_show, root_id, node_id, version_id} -> %>
            <.live_component
              module={Forms.Show}
              id="forms-show"
              root_id={root_id}
              node_id={node_id}
              version_id={version_id}
              app={@app}
              base={@base}
            />
          <% {:node_edit, root_id, node_id, version_id} -> %>
            <.live_component
              module={Forms.Edit}
              id="forms-edit"
              root_id={root_id}
              node_id={node_id}
              version_id={version_id}
              app={@app}
              base={@base}
            />
          <% nil -> %>
            <%!-- not a /forms path --%>
        <% end %>
      <% end %>
    </div>
    """
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
