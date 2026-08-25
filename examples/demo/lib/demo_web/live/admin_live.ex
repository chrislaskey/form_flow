defmodule DemoWeb.AdminLive do
  @moduledoc """
  The dedicated page for FormFlow's template administration.

  Mounted on `live "/admin/*path", AdminLive`, so `/admin` (a landing linking
  the two indexes), `/admin/flows/*`, and `/admin/forms/*` all land here.
  FormFlow's router dispatches the remaining path to the right LiveComponent —
  this page just supplies the layout around it. `base="/admin"` is what makes
  every link the components build carry the mount prefix.
  """

  use DemoWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Admin")}
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
    <Layouts.app flash={@flash}>
      <div class="space-y-6">
        <header class="space-y-2">
          <h1 class="text-2xl font-semibold">Admin</h1>
          <p class="text-base-content/70">
            FormFlow's template administration: flows (graphs rendered with
            ReactFlow) and the reusable form catalog. Back to the <.link navigate={~p"/"} class="link">demo index</.link>.
          </p>
        </header>

        <div id="admin-pages" class="rounded-lg border border-base-300 p-4">
          <FormFlow.Web.router
            type="templates"
            path={@path}
            base="/admin"
            uri={@uri}
            params={@params}
          />
        </div>
      </div>
    </Layouts.app>
    """
  end
end
