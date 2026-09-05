defmodule DemoWeb.FormFlowLive.Admin do
  @moduledoc """
  The dedicated page for FormFlow's template administration.

  Mounted on `live "/admin/*path", FormFlowLive.Admin`, so `/admin` (a landing linking
  the two indexes), `/admin/flows/*`, and `/admin/forms/*` all land here.
  FormFlow's router dispatches the remaining path to the right LiveComponent —
  this page just supplies the layout around it. `base="/admin"` is what makes
  every link the components build carry the mount prefix.
  """

  use DemoWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Admin")
     |> assign(:current_nav, :admin)}
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
          <h1 class="text-2xl font-semibold">Admin</h1>
          <p class="text-base-content/70">
            FormFlow's template administration: flows (diagrams rendered with
            ReactFlow) and the reusable form catalog. Back to the <.link navigate={~p"/"} class="link">demo index</.link>.
          </p>
        </header>

        <div id="admin-pages">
          <FormFlow.Web.router
            type="templates"
            user_id="demo-admin"
            uri={@uri}
            params={@params}
            path={@path}
            base="/admin"
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
