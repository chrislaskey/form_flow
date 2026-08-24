defmodule FormFlow.Web.Templates.Flows.Show do
  @moduledoc """
  `FormFlow.Web.Templates.Flows.Show` LiveComponent displays one flow.

  Loads the graph with `FormFlow.Data.Graphs.get/1` and renders it read-only in
  the editor canvas (see `FormFlow.Web.Components.Editor`) — pan and zoom work,
  but changing anything means clicking through to the edit page. The delete
  button removes the flow and navigates back to the index.

  Two addressing modes, matching the router:

    * `graph_id` — a flow shown directly, `/flows/:id`
    * `root_id` + `node_id` — a subflow reached by drill-in,
      `/flows/:root_id/nodes/:node_id`; the node's `subflow_id` is the graph
      shown here, with a breadcrumb back to the root

  A subflow node's Open button pushes `form_flow:open_subflow`, which
  navigates to that node's show page under the same root — drill-in is
  navigation, so it works on this read-only page too.
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

    {:ok, assign(socket, graph: graph, data: data, root: root)}
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
  def handle_event("form_flow:open_subflow", %{"node_id" => node_id}, socket) do
    root_id = socket.assigns.root_id || socket.assigns.graph.id

    {:noreply,
     push_navigate(socket, to: "#{socket.assigns.base}/flows/#{root_id}/nodes/#{node_id}")}
  end

  @impl true
  def handle_event("delete", _params, socket) do
    case Graphs.delete(socket.assigns.graph) do
      {:ok, _graph} ->
        {:noreply, push_navigate(socket, to: "#{socket.assigns.base}/flows")}

      {:error, %Ecto.Changeset{}} ->
        # The context refuses while other flows still reference this graph
        # as a subflow — deleting it would break their canvases
        {:noreply,
         assign(
           socket,
           :error,
           "This flow can't be deleted: another flow still uses it as a subflow. " <>
             "Remove that subflow step (or delete the flow containing it) first."
         )}
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
        <h2 class="text-sm font-semibold">
          <.link navigate={"#{@base}/flows"} class="hover:underline">Flows</.link>
          <span class="text-zinc-400">/</span>
          <.link :if={@root} navigate={"#{@base}/flows/#{@root.id}"} class="hover:underline">
            {@root.name || "Untitled"}
          </.link>
          <span :if={@root} class="text-zinc-400">/</span>
          {@graph.name || "Untitled"}
          <span class="ml-1 text-xs font-normal text-zinc-500">
            {if @graph.label == "subflows", do: "Complex flow", else: "Simple flow"}
          </span>
        </h2>
        <div class="flex items-center gap-2">
          <.link
            navigate={back_path(assigns)}
            class="rounded-md border border-zinc-300 px-2 py-1 text-xs hover:border-zinc-400"
          >
            Back
          </.link>
          <.link
            navigate={edit_path(assigns)}
            class="rounded-md border border-cyan-600 px-2 py-1 text-xs text-cyan-600 hover:bg-cyan-50"
          >
            Edit
          </.link>
          <button
            :if={is_nil(@node_id)}
            type="button"
            phx-click="delete"
            phx-target={@myself}
            data-confirm="Delete this flow? Its steps, connections, and subflows go with it."
            class="rounded-md border border-red-600 px-2 py-1 text-xs text-red-600 hover:bg-red-50"
          >
            Delete
          </button>
        </div>
      </div>

      <p :if={@error} class="mb-2 text-xs text-red-600">{@error}</p>

      <Editor.editor
        id={"#{@id}-editor"}
        data={@data}
        target={@myself}
        editable={false}
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

  defp back_path(%{node_id: nil} = assigns), do: "#{assigns.base}/flows"
  defp back_path(assigns), do: "#{assigns.base}/flows/#{assigns.root_id}"

  defp edit_path(%{node_id: nil} = assigns), do: "#{assigns.base}/flows/#{assigns.graph.id}/edit"

  defp edit_path(assigns) do
    "#{assigns.base}/flows/#{assigns.root_id}/nodes/#{assigns.node_id}/edit"
  end
end
