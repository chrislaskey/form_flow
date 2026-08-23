defmodule FormFlow.Web.Templates.Flows.Edit do
  @moduledoc """
  `FormFlow.Web.Templates.Flows.Edit` LiveComponent edits an existing flow.

  Loads the graph with `FormFlow.Data.Graphs.get/1`, renders it in the editor
  (see `FormFlow.Web.Components.Editor`), tracks edits as the editor reports
  them, and on save replaces the graph's contents with
  `FormFlow.Data.Graphs.update/2` before navigating back to the show page.

      <.live_component module={FormFlow.Web.Templates.Flows.Edit} id="flows-edit" graph_id={id} />

  `base` is the path prefix the flows pages are mounted under, used to build
  navigation targets — with the default `""`, saving navigates to `/flows/:id`.
  """

  use Phoenix.LiveComponent

  alias FormFlow.Data.Graphs
  alias FormFlow.Web.Components.Editor
  alias FormFlow.Web.Helpers.ReactFlow

  @impl true
  def mount(socket) do
    {:ok, assign(socket, error: nil)}
  end

  @impl true
  def update(assigns, socket) do
    graph = Graphs.get(assigns.graph_id)
    data = graph && ReactFlow.to_data(graph)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:base, fn -> "" end)
     |> assign(graph: graph, data: data)
     |> assign(:current, data)}
  end

  @impl true
  def handle_event("form_flow:editor_mounted", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("form_flow:graph_changed", %{"nodes" => nodes, "edges" => edges}, socket) do
    {:noreply, assign(socket, :current, %{"nodes" => nodes, "edges" => edges})}
  end

  @impl true
  def handle_event("save", _params, socket) do
    attrs = ReactFlow.to_graph_attrs(socket.assigns.current)

    case Graphs.update(socket.assigns.graph, attrs) do
      {:ok, graph} ->
        {:noreply, push_navigate(socket, to: "#{socket.assigns.base}/flows/#{graph.id}")}

      {:error, %Ecto.Changeset{}} ->
        {:noreply, assign(socket, :error, "Could not save the flow. Please try again.")}
    end
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
        <h2 class="text-sm font-semibold">Edit flow</h2>
        <div class="flex items-center gap-2">
          <.link
            navigate={"#{@base}/flows/#{@graph.id}"}
            class="rounded-md border border-zinc-300 px-2 py-1 text-xs hover:border-zinc-400"
          >
            Cancel
          </.link>
          <button
            type="button"
            phx-click="save"
            phx-target={@myself}
            class="rounded-md border border-cyan-600 bg-cyan-600 px-2 py-1 text-xs text-white hover:bg-cyan-700"
          >
            Save
          </button>
        </div>
      </div>

      <p :if={@error} class="mb-2 text-xs text-red-600">{@error}</p>

      <Editor.editor id={"#{@id}-editor"} data={@data} target={@myself} />
    </div>
    """
  end
end
