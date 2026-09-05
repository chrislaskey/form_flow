defmodule DemoWeb.FormFlowLive.Users do
  @moduledoc """
  The dedicated page for FormFlow's user-facing form instances.

  Mounted on `live "/users/*path", FormFlowLive.Users`, so `/users` (the
  listing of the user's flow instances), `/users/:id` (one instance), and
  `/users/:id/forms/*` (a form inside it) all land here. FormFlow's router
  dispatches the remaining path to the right LiveComponent — this page just
  supplies the layout around it. `base="/users"` is what makes every link
  the components build carry the mount prefix.
  """

  use DemoWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Users")
     |> assign(:current_nav, :users)}
  end

  @impl true
  def handle_params(params, uri, socket) do
    {:noreply,
     socket
     |> assign(:path, Map.get(params, "path", []))
     |> assign(:params, params)
     |> assign(:uri, uri)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_nav={@current_nav}>
      <div class="space-y-6">
        <header class="space-y-2">
          <h1 class="text-2xl font-semibold">Users</h1>
          <p class="text-base-content/70">
            FormFlow's user-facing form instances: flows (diagrams rendered with
            ReactFlow) and the reusable form catalog. Back to the <.link navigate={~p"/"} class="link">demo index</.link>.
          </p>
        </header>

        <div id="users-pages">
          <FormFlow.Web.router
            user_id="demo-user"
            uri={@uri}
            params={@params}
            path={@path}
            base="/users"
            flow_types={DemoWeb.FormFlowLive.Types.flow_types()}
            form_types={DemoWeb.FormFlowLive.Types.form_types()}
            callback_data={%{hello: "world"}}
          />
        </div>
      </div>
    </Layouts.app>
    """
  end
end
