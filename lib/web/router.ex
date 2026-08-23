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

  | Path              | LiveComponent |
  |-------------------|---------------|
  | `/flows`          | `FormFlow.Web.Templates.Flows.Index` |
  | `/flows/new`      | `FormFlow.Web.Templates.Flows.New` |
  | `/flows/:id`      | `FormFlow.Web.Templates.Flows.Show` |
  | `/flows/:id/edit` | `FormFlow.Web.Templates.Flows.Edit` |

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
          <% nil -> %>
            <%!-- not a /flows path --%>
        <% end %>

        <.live_component
          :if={matches?("/forms", @path)}
          module={Forms.Index}
          id="forms-index"
          app={@app}
        />

        <.live_component
          :if={matches?("/forms/1", @path)}
          module={Forms.Show}
          id="forms-show"
          app={@app}
        />
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
      _other -> nil
    end
  end

  defp matches?(pattern, path) do
    "/#{Enum.join(segments(path), "/")}" == pattern
  end

  defp segments(path) when is_list(path), do: path
  defp segments(path) when is_binary(path), do: String.split(path, "/", trim: true)
end
