defmodule FormFlow.Web.Templates.Flows.Show do
  @moduledoc """
  `FormFlow.Web.Templates.Flows.Show` LiveComponent displays one flow.

  Loads the graph with `FormFlow.Data.Graphs.get/1` and renders it read-only in
  the editor canvas (see `FormFlow.Web.Components.Editor`) — pan and zoom work,
  but changing anything means clicking through to the edit page. The delete
  button removes the flow and navigates back to the index.

      <.live_component module={FormFlow.Web.Templates.Flows.Show} id="flows-show" graph_id={id} />

  `base` is the path prefix the flows pages are mounted under, used to build
  navigation targets — with the default `""`, edit links to `/flows/:id/edit`.
  """

  use Phoenix.LiveComponent

  alias FormFlow.Data.Graphs
  alias FormFlow.Web.Components.Editor
  alias FormFlow.Web.Helpers.ReactFlow

  @impl true
  def update(assigns, socket) do
    graph = Graphs.get(assigns.graph_id)
    data = graph && ReactFlow.to_data(graph)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:base, fn -> "" end)
     |> assign(graph: graph, data: data)}
  end

  @impl true
  def handle_event("form_flow:editor_mounted", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("form_flow:graph_changed", _params, socket) do
    # The canvas is read-only, so this shouldn't fire — ignored if it does
    {:noreply, socket}
  end

  @impl true
  def handle_event("delete", _params, socket) do
    {:ok, _graph} = Graphs.delete(socket.assigns.graph)

    {:noreply, push_navigate(socket, to: "#{socket.assigns.base}/flows")}
  end

  @impl true
  def render(%{graph: nil} = assigns) do
    ~H"""
    <div>
      <p class="text-sm text-zinc-500">
        Flow not found.
        <.link navigate={"#{@base}/flows"} class="underline">Back to flows</.link>
      </p>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div>
      <div class="mb-2 flex items-center justify-between gap-4">
        <h2 class="text-sm font-semibold">Flow <span class="font-mono text-xs">{@graph.id}</span></h2>
        <div class="flex items-center gap-2">
          <.link
            navigate={"#{@base}/flows"}
            class="rounded-md border border-zinc-300 px-2 py-1 text-xs hover:border-zinc-400"
          >
            Back
          </.link>
          <.link
            navigate={"#{@base}/flows/#{@graph.id}/edit"}
            class="rounded-md border border-cyan-600 px-2 py-1 text-xs text-cyan-600 hover:bg-cyan-50"
          >
            Edit
          </.link>
          <button
            type="button"
            phx-click="delete"
            phx-target={@myself}
            data-confirm="Delete this flow? Its steps and connections go with it."
            class="rounded-md border border-red-600 px-2 py-1 text-xs text-red-600 hover:bg-red-50"
          >
            Delete
          </button>
        </div>
      </div>

      <Editor.editor id={"#{@id}-editor"} data={@data} target={@myself} editable={false} />
    </div>
    """
  end
end
