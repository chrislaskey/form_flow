defmodule FormFlow.Web.Templates.Flows.Edit do
  @moduledoc """
  `FormFlow.Web.Templates.Flows.Edit` LiveComponent edits an existing flow.

  Loads the graph with `FormFlow.Data.Graphs.get/1`, renders it in the editor
  (see `FormFlow.Web.Components.Editor`), tracks edits as the editor reports
  them, and on save replaces the graph's contents with
  `FormFlow.Data.Graphs.update/2`. Saving a subflows flow also creates the
  children of any freshly added subflow nodes — see `FormFlow.Data.Graphs`.

  Edit mode is sticky: saving stays here rather than bouncing to the show
  page — flow editing is a workspace loop, often across several levels. After
  a save the persisted graph is pushed back into the canvas
  (`form_flow:set_graph`), so editor-temporary node ids become the real UUIDs
  — which is what makes Open work on a just-saved subflow node.

  Two addressing modes, matching the router:

    * `graph_id` — a flow edited directly, `/flows/:id/edit`
    * `root_id` + `node_id` — a subflow reached by drill-in,
      `/flows/:root_id/nodes/:node_id/edit`; the node's `subflow_id` is the
      graph edited here

  A subflow node's Open button pushes `form_flow:open_subflow`, which
  navigates to that node's edit page under the same root — unless the canvas
  has unsaved changes (`current` differs from the last-persisted `data`) or
  the node itself was only just added and has never been saved at all (so
  `FormFlow.Data.Graphs.get_node/1` can't find it yet), in which case
  navigation pauses for a prompt to save first or cancel. Declining leaves the
  canvas exactly as it was; nothing is discarded. Saving resolves the node's
  editor-temporary id to whatever it was actually saved as (see
  `FormFlow.Web.Helpers.ReactFlow.to_graph_attrs/1`'s `id_map`), so Open still
  lands on the right subflow even when it was never saved before this click.
  """

  use Phoenix.LiveComponent

  alias FormFlow.Data.Graphs
  alias FormFlow.Web.Components.Editor
  alias FormFlow.Web.Helpers.ReactFlow

  @impl true
  def mount(socket) do
    {:ok, assign(socket, error: nil, notice: nil, pending_node_id: nil)}
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
    {:noreply,
     socket
     |> assign(:current, %{"nodes" => nodes, "edges" => edges})
     |> assign(:notice, nil)}
  end

  @impl true
  def handle_event("form_flow:open_subflow", %{"node_id" => node_id}, socket) do
    if Graphs.get_node(node_id) && not unsaved_changes?(socket.assigns) do
      {:noreply, navigate_to_node(socket, node_id)}
    else
      {:noreply, assign(socket, :pending_node_id, node_id)}
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
    case persist_current(socket) do
      {:ok, socket, _id_map} -> {:noreply, assign(socket, :notice, "Saved.")}
      {:error, socket} -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("save_and_open", _params, socket) do
    node_id = socket.assigns.pending_node_id

    case persist_current(socket) do
      {:ok, socket, id_map} ->
        resolved_id = Map.get(id_map, node_id, node_id)

        {:noreply, socket |> assign(:pending_node_id, nil) |> navigate_to_node(resolved_id)}

      {:error, socket} ->
        {:noreply, assign(socket, :pending_node_id, nil)}
    end
  end

  @impl true
  def handle_event("cancel_open", _params, socket) do
    {:noreply, assign(socket, :pending_node_id, nil)}
  end

  # Whether the canvas has edits the last save doesn't reflect yet —
  # `current` tracks every reported `graph_changed`, `data` only what
  # `Graphs.update/2` last persisted.
  defp unsaved_changes?(assigns), do: assigns.current != assigns.data

  defp navigate_to_node(socket, node_id) do
    root_id = socket.assigns.root_id || socket.assigns.graph.id

    push_navigate(socket, to: "#{socket.assigns.base}/flows/#{root_id}/nodes/#{node_id}/edit")
  end

  # Shared by "save" and "save_and_open": persists the canvas and re-syncs it
  # with what was written — temporary editor ids became real UUIDs, and fresh
  # subflow nodes gained their subflow_id — so Open works without a reload.
  # Returns the id_map too: "save_and_open" needs it to find out what the
  # pending node's editor-temporary id was actually saved as.
  defp persist_current(socket) do
    attrs = ReactFlow.to_graph_attrs(socket.assigns.current)

    case Graphs.update(socket.assigns.graph, attrs) do
      {:ok, graph} ->
        graph = Graphs.get(graph.id)
        data = ReactFlow.to_data(graph)

        socket =
          socket
          |> assign(graph: graph, data: data, current: data, error: nil)
          |> push_event("form_flow:set_graph", %{graph: data})

        {:ok, socket, attrs.id_map}

      {:error, %Ecto.Changeset{}} ->
        {:error, assign(socket, :error, "Could not save the flow. Please try again.")}
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
      <p :if={@notice} class="mb-2 text-xs text-green-700">{@notice}</p>

      <Editor.editor
        id={"#{@id}-editor"}
        data={@data}
        target={@myself}
        flow_label={@graph.label}
      />

      <div
        :if={@pending_node_id}
        class="fixed inset-0 z-50 flex items-center justify-center bg-black/40"
      >
        <div class="w-80 rounded-md border border-zinc-300 bg-white p-4 shadow-lg">
          <p class="mb-4 text-sm text-zinc-700">
            This flow has unsaved changes. Save before opening the subflow?
          </p>
          <div class="flex justify-end gap-2">
            <button
              type="button"
              phx-click="cancel_open"
              phx-target={@myself}
              class="rounded-md border border-zinc-300 px-2 py-1 text-xs hover:border-zinc-400"
            >
              Cancel
            </button>
            <button
              type="button"
              phx-click="save_and_open"
              phx-target={@myself}
              class="rounded-md border border-cyan-600 bg-cyan-600 px-2 py-1 text-xs text-white hover:bg-cyan-700"
            >
              Save &amp; Open
            </button>
          </div>
        </div>
      </div>
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
