defmodule FormFlow.Web.Templates.Flows.Edit do
  @moduledoc """
  `FormFlow.Web.Templates.Flows.Edit` LiveComponent edits an existing flow.

  Loads the graph with `FormFlow.Data.Graphs.get/1`, renders it in the editor
  (see `FormFlow.Web.Components.Editor`), tracks edits as the editor reports
  them, and on save replaces the graph's contents with
  `FormFlow.Data.Graphs.update/2` before navigating back to the show page.
  Saving a subflows flow also creates the children of any freshly added
  subflow nodes — see `FormFlow.Data.Graphs`.

  Two addressing modes, matching the router:

    * `graph_id` — a flow edited directly, `/flows/:id/edit`
    * `root_id` + `node_id` — a subflow reached by drill-in,
      `/flows/:root_id/nodes/:node_id/edit`; the node's `subflow_id` is the
      graph edited here

  A subflow node's Open button pushes `form_flow:open_subflow`, which
  navigates to that node's edit page under the same root.
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
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:base, fn -> "" end)
      |> assign_new(:root_id, fn -> nil end)
      |> assign_new(:node_id, fn -> nil end)

    graph = resolve_graph(socket.assigns)
    data = graph && ReactFlow.to_data(graph)
    root = socket.assigns.node_id && Graphs.get(socket.assigns.root_id)

    {:ok, assign(socket, graph: graph, data: data, current: data, root: root)}
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
  def handle_event("form_flow:open_subflow", %{"node_id" => node_id}, socket) do
    case Graphs.get_node(node_id) do
      nil ->
        {:noreply, assign(socket, :error, "Save the flow before opening a new subflow.")}

      _node ->
        root_id = socket.assigns.root_id || socket.assigns.graph.id

        {:noreply,
         push_navigate(socket,
           to: "#{socket.assigns.base}/flows/#{root_id}/nodes/#{node_id}/edit"
         )}
    end
  end

  @impl true
  def handle_event("rename", %{"value" => name}, socket) do
    case Graphs.update(socket.assigns.graph, %{name: name}) do
      {:ok, graph} -> {:noreply, assign(socket, :graph, graph)}
      {:error, _changeset} -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("save", _params, socket) do
    attrs = ReactFlow.to_graph_attrs(socket.assigns.current)

    case Graphs.update(socket.assigns.graph, attrs) do
      {:ok, _graph} ->
        {:noreply, push_navigate(socket, to: show_path(socket.assigns))}

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
        <div class="flex items-center gap-2 text-sm font-semibold">
          <%!-- Breadcrumbs stay in edit mode: backing out of a subflow lands
                on the parent's editor, not its show page --%>
          <.link navigate={"#{@base}/flows"} class="hover:underline">Flows</.link>
          <span class="text-zinc-400">/</span>
          <.link
            :if={@root}
            navigate={"#{@base}/flows/#{@root.id}/edit"}
            class="hover:underline"
          >
            {@root.name || "Untitled"}
          </.link>
          <span :if={@root} class="text-zinc-400">/</span>
          <input
            type="text"
            name="name"
            value={@graph.name || "Untitled"}
            phx-blur="rename"
            phx-target={@myself}
            class="rounded-md border border-zinc-300 px-2 py-1 text-sm font-semibold"
          />
          <span class="text-xs font-normal text-zinc-500">
            {if @graph.label == "subflows", do: "Complex flow", else: "Simple flow"}
          </span>
        </div>
        <div class="flex items-center gap-2">
          <.link
            navigate={show_path(assigns)}
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

      <Editor.editor
        id={"#{@id}-editor"}
        data={@data}
        target={@myself}
        flow_label={@graph.label}
      />
    </div>
    """
  end

  defp resolve_graph(%{node_id: nil} = assigns), do: Graphs.get(assigns.graph_id)

  defp resolve_graph(assigns) do
    case Graphs.get_node(assigns.node_id) do
      %{subflow_id: subflow_id} when not is_nil(subflow_id) -> Graphs.get(subflow_id)
      _other -> nil
    end
  end

  defp show_path(%{node_id: nil} = assigns), do: "#{assigns.base}/flows/#{assigns.graph.id}"

  defp show_path(assigns) do
    "#{assigns.base}/flows/#{assigns.root_id}/nodes/#{assigns.node_id}"
  end
end
