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

  Navigating within the canvas is guarded against losing unsaved changes
  (`current` differs from the last-persisted `data`): the header's Show
  button, a subflow's Open button, and the breadcrumbs all push a generic
  `"navigate"` event with their destination rather than a bare `<.link
  navigate>`, precisely so that event can check first — if the canvas is
  dirty, navigation pauses for a prompt to save first or keep editing instead
  of silently discarding the edit. Open additionally treats a node
  `FormFlow.Data.Graphs.get_node/1` can't find yet (just added, never saved)
  as unsaved, since there's nothing to navigate to until it exists. Either way
  declining leaves the canvas exactly as it was — nothing is discarded — and
  confirming resolves a pending node's editor-temporary id to whatever it was
  actually saved as (see `FormFlow.Web.Helpers.ReactFlow.to_graph_attrs/1`'s
  `id_map`), so Open still lands on the right subflow even when it was never
  saved before this click.

  Discard changes is the deliberate opposite: shown only while the canvas is
  dirty, it throws the edit away rather than protecting it, so it asks for
  confirmation first rather than checking for one. Confirming reloads this
  same edit page via `push_navigate/2` — a full remount, refetching the graph
  from scratch — rather than trying to reset in-memory state by hand. That's
  deliberately the blunt option: as the canvas grows more state (open panels,
  selections, whatever comes later), reproducing "as freshly loaded" by
  resetting each field by hand only gets more places to miss one, where a
  reload can't drift from what a fresh page load already does correctly. The
  cost is a full round trip and a brief re-render, which is cheap next to
  that.
  """

  use Phoenix.LiveComponent

  alias FormFlow.Data.Graphs
  alias FormFlow.Web.Components.Editor
  alias FormFlow.Web.Helpers.ReactFlow

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket, error: nil, notice: nil, pending_navigation: nil, confirming_discard?: false)}
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
      {:noreply, assign(socket, :pending_navigation, {:node, node_id})}
    end
  end

  # The generic guard: Show and the breadcrumbs route through here instead of
  # a bare `<.link navigate>`, so they get the same prompt as Open when the
  # canvas has unsaved changes.
  @impl true
  def handle_event("navigate", %{"to" => to}, socket) do
    if unsaved_changes?(socket.assigns) do
      {:noreply, assign(socket, :pending_navigation, {:path, to})}
    else
      {:noreply, push_navigate(socket, to: to)}
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
  def handle_event("save_and_continue", _params, socket) do
    pending = socket.assigns.pending_navigation

    case persist_current(socket) do
      {:ok, socket, id_map} ->
        to = resolve_pending_navigation(pending, socket.assigns, id_map)

        {:noreply, socket |> assign(:pending_navigation, nil) |> push_navigate(to: to)}

      {:error, socket} ->
        {:noreply, assign(socket, :pending_navigation, nil)}
    end
  end

  @impl true
  def handle_event("cancel_navigation", _params, socket) do
    {:noreply, assign(socket, :pending_navigation, nil)}
  end

  @impl true
  def handle_event("request_discard", _params, socket) do
    {:noreply, assign(socket, :confirming_discard?, true)}
  end

  @impl true
  def handle_event("cancel_discard", _params, socket) do
    {:noreply, assign(socket, :confirming_discard?, false)}
  end

  @impl true
  def handle_event("confirm_discard", _params, socket) do
    {:noreply, push_navigate(socket, to: current_path(socket.assigns))}
  end

  # Whether the canvas has edits the last save doesn't reflect yet —
  # `current` tracks every reported `graph_changed`, `data` only what
  # `Graphs.update/2` last persisted.
  defp unsaved_changes?(assigns), do: assigns.current != assigns.data

  defp navigate_to_node(socket, node_id) do
    push_navigate(socket, to: node_path(socket.assigns, node_id))
  end

  defp node_path(assigns, node_id) do
    root_id = assigns.root_id || assigns.graph.id
    "#{assigns.base}/flows/#{root_id}/nodes/#{node_id}/edit"
  end

  # A plain path was already the destination; a pending node needs its
  # editor-temporary id resolved through what the save just assigned it.
  defp resolve_pending_navigation({:path, to}, _assigns, _id_map), do: to

  defp resolve_pending_navigation({:node, node_id}, assigns, id_map) do
    node_path(assigns, Map.get(id_map, node_id, node_id))
  end

  # Shared by "save" and "save_and_continue": persists the canvas and re-syncs
  # it with what was written — temporary editor ids became real UUIDs, and
  # fresh subflow nodes gained their subflow_id — so Open works without a
  # reload. Returns the id_map too: "save_and_continue" needs it to resolve a
  # pending node's editor-temporary id to what it was actually saved as.
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
      <div class="mb-2 h-14 flex items-center justify-between gap-4">
        <div class="flex items-center gap-2 text-sm font-semibold">
          <%!-- Breadcrumbs stay in edit mode: backing out of a subflow lands
                on the parent's editor, not its show page. They navigate
                through the "navigate" event rather than a bare <.link>, so
                unsaved changes get the same save-first prompt as Open. --%>
          <button
            type="button"
            phx-click="navigate"
            phx-value-to={"#{@base}/flows"}
            phx-target={@myself}
            class="hover:underline"
          >
            Flows
          </button>
          <span class="text-zinc-400">/</span>
          <button
            :if={@root}
            type="button"
            phx-click="navigate"
            phx-value-to={"#{@base}/flows/#{@root.id}/edit"}
            phx-target={@myself}
            class="hover:underline"
          >
            {@root.name || "Untitled"}
          </button>
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
          <button
            :if={unsaved_changes?(assigns)}
            type="button"
            phx-click="request_discard"
            phx-target={@myself}
            class="rounded-md border border-zinc-300 px-2 py-1 text-xs text-red-600 hover:border-red-400"
          >
            Discard changes
          </button>
          <%!-- A styled toggle, not a real checkbox: a checkbox flips its own
                visual state on click regardless of the server, which would
                desync from reality when unsaved changes turn this click into
                a prompt instead of an immediate mode switch. --%>
          <button
            type="button"
            phx-click="navigate"
            phx-value-to={show_path(assigns)}
            phx-target={@myself}
            role="switch"
            aria-checked="true"
            aria-label="Switch to Show"
            class="flex items-center gap-1.5 text-xs"
          >
            <span class="text-zinc-500">Show</span>
            <span class="relative inline-flex h-5 w-9 shrink-0 items-center rounded-full bg-cyan-600 transition-colors">
              <span class="inline-block h-4 w-4 translate-x-4 rounded-full bg-white shadow transition-transform" />
            </span>
            <span class="font-semibold text-zinc-900">Edit</span>
          </button>
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
        :if={@pending_navigation}
        class="fixed inset-0 z-50 flex items-center justify-center bg-black/40"
      >
        <div class="w-80 rounded-md border border-zinc-300 bg-white p-4 shadow-lg">
          <p class="mb-4 text-sm text-zinc-700">
            This flow has unsaved changes. Save before continuing?
          </p>
          <div class="flex justify-end gap-2">
            <button
              type="button"
              phx-click="cancel_navigation"
              phx-target={@myself}
              class="rounded-md border border-zinc-300 px-2 py-1 text-xs hover:border-zinc-400"
            >
              Keep editing
            </button>
            <button
              type="button"
              phx-click="save_and_continue"
              phx-target={@myself}
              class="rounded-md border border-cyan-600 bg-cyan-600 px-2 py-1 text-xs text-white hover:bg-cyan-700"
            >
              Save &amp; Continue
            </button>
          </div>
        </div>
      </div>

      <div
        :if={@confirming_discard?}
        class="fixed inset-0 z-50 flex items-center justify-center bg-black/40"
      >
        <div class="w-80 rounded-md border border-zinc-300 bg-white p-4 shadow-lg">
          <p class="mb-4 text-sm text-zinc-700">
            Discard changes? This can't be undone.
          </p>
          <div class="flex justify-end gap-2">
            <button
              type="button"
              phx-click="cancel_discard"
              phx-target={@myself}
              class="rounded-md border border-zinc-300 px-2 py-1 text-xs hover:border-zinc-400"
            >
              Keep editing
            </button>
            <button
              type="button"
              phx-click="confirm_discard"
              phx-target={@myself}
              class="rounded-md border border-red-600 bg-red-600 px-2 py-1 text-xs text-white hover:bg-red-700"
            >
              Discard changes
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

  # This edit page's own URL, for Discard's full reload
  defp current_path(%{node_id: nil} = assigns), do: "#{assigns.base}/flows/#{assigns.graph.id}/edit"

  defp current_path(assigns) do
    "#{assigns.base}/flows/#{assigns.root_id}/nodes/#{assigns.node_id}/edit"
  end
end
