defmodule DemoWeb.FlowsLive do
  @moduledoc """
  The dedicated page for FormFlow's flows CRUD.

  Mounted on `live "/flows/*path", FlowsLive`, so `/flows`, `/flows/new`,
  `/flows/:id`, and `/flows/:id/edit` all land here. FormFlow's router
  dispatches the path to the right LiveComponent — this page just supplies the
  layout around it.
  """

  use DemoWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Flows")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :path, ["flows" | Map.get(params, "path", [])])}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-6">
        <header class="space-y-2">
          <h1 class="text-2xl font-semibold">Flows</h1>
          <p class="text-base-content/70">
            Flows are stored as graphs by <code>FormFlow.Data.Graphs</code> and
            rendered with ReactFlow. Back to the <.link navigate={~p"/"} class="link">demo index</.link>.
          </p>
        </header>

        <div id="flows-pages" class="rounded-lg border border-base-300 p-4">
          <FormFlow.Web.router type="templates" path={@path} />
        </div>
      </div>
    </Layouts.app>
    """
  end
end
