defmodule FormFlow.Web.Templates.Flows.Show do
  @moduledoc """
  `FormFlow.Web.Templates.Flows.Show` LiveComponent displays one flow.

  Loads the flow with `FormFlow.Data.Templates.Flows.get/1` and renders it
  read-only in the editor canvas (see `FormFlow.Web.Components.Editor`) — pan
  and zoom work, but changing anything means clicking through to the edit
  page. The delete button removes the flow and navigates back to the index.

  Two addressing modes, matching the router:

    * `flow_id` — a flow shown directly, `/flows/:id`
    * `root_id` + `node_id` — a subflow reached by drill-in,
      `/flows/:root_id/nodes/:node_id`; the node's `subflow_id` is the flow
      shown here, with a breadcrumb back to the root

  A subflow node's Open button pushes `form_flow:open_subflow`, which
  navigates to that node's show page under the same root — drill-in is
  navigation, so it works on this read-only page too.

  Delete means different things in the two modes. At the top level it deletes
  the flow and everything it owns. On a drill-in page it removes the parent's
  subflow step (`FormFlow.Data.Templates.Flows.delete_node/1`) — the child's
  flows go with it through garbage collection when owned, and survive when
  reusable.
  Deleting the child *flow* directly would be refused while the parent still
  references it, which is why that is not what the button does.
  """

  use Phoenix.LiveComponent

  import FormFlow.Web.Helpers.Paths

  alias FormFlow.Data.Templates.Flows
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

    flow = resolve_flow(socket.assigns)
    data = flow && ReactFlow.to_data(flow)
    root = socket.assigns.node_id && Flows.get(socket.assigns.root_id)

    {:ok, assign(socket, flow: flow, data: data, root: root)}
  end

  @impl true
  def handle_event("form_flow:editor_mounted", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("form_flow:flow_changed", _params, socket) do
    # The canvas is read-only, so this shouldn't fire — ignored if it does
    {:noreply, socket}
  end

  @impl true
  def handle_event("form_flow:open_form", %{"node_id" => node_id}, socket) do
    root_id = socket.assigns.root_id || socket.assigns.flow.id

    {:noreply,
     push_navigate(socket, to: "#{socket.assigns.base}/flows/#{root_id}/nodes/#{node_id}/form")}
  end

  @impl true
  def handle_event("form_flow:open_subflow", %{"node_id" => node_id}, socket) do
    root_id = socket.assigns.root_id || socket.assigns.flow.id

    {:noreply,
     push_navigate(socket, to: "#{socket.assigns.base}/flows/#{root_id}/nodes/#{node_id}")}
  end

  @impl true
  def handle_event("delete", _params, %{assigns: %{node_id: node_id}} = socket)
      when is_binary(node_id) do
    node = Flows.get_node(node_id)

    # Compute the destination before deleting: the *containing* flow's edit
    # page — edit mode is sticky, and deleting a step is an editing action
    to = parent_edit_path(socket.assigns, node)

    {:ok, _node} = Flows.delete_node(node)

    {:noreply, push_navigate(socket, to: to)}
  end

  def handle_event("delete", _params, socket) do
    case Flows.delete(socket.assigns.flow) do
      {:ok, _flow} ->
        {:noreply, push_navigate(socket, to: "#{socket.assigns.base}/flows")}

      {:error, %Ecto.Changeset{}} ->
        # The context refuses while other flows still reference this flow
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
  def render(%{flow: nil} = assigns) do
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
        <div class="text-sm font-semibold">
          <.link navigate={templates_path(@base)} class="hover:underline">Templates</.link>
          <span class="text-zinc-400">/</span>
          <.link navigate={"#{@base}/flows"} class="hover:underline">Flows</.link>
          <span class="text-zinc-400">/</span>
          <.link :if={@root} navigate={"#{@base}/flows/#{@root.id}"} class="hover:underline">
            {@root.name || "Untitled"}
          </.link>
          <span :if={@root} class="text-zinc-400">/</span>
          {@flow.name || "Untitled"}
          <span class="ml-1 text-xs font-normal text-zinc-500">
            {if @flow.label == "subflows", do: "Complex flow", else: "Simple flow"}
          </span>
        </div>
        <div class="flex items-center gap-2">
          <%!-- Mirrors the Edit page's Show/Edit toggle, fixed to the
                opposite position: this page is always the "off" (Show)
                side, so unlike there, nothing here needs to intercept the
                click. --%>
          <.link
            navigate={edit_path(assigns)}
            role="switch"
            aria-checked="false"
            aria-label="Switch to Edit"
            class="flex items-center gap-1.5 text-xs"
          >
            <span class="font-semibold text-zinc-900">Show</span>
            <span class="relative inline-flex h-5 w-9 shrink-0 items-center rounded-full bg-zinc-300 transition-colors">
              <span class="inline-block h-4 w-4 translate-x-0.5 rounded-full bg-white shadow transition-transform" />
            </span>
            <span class="text-zinc-500">Edit</span>
          </.link>
          <button
            type="button"
            phx-click="delete"
            phx-target={@myself}
            data-confirm={
              if @node_id,
                do:
                  "Delete this subflow? It is removed from the parent flow, and its own steps and subflows go with it.",
                else: "Delete this flow? Its steps, connections, and subflows go with it."
            }
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
        flow_label={@flow.label}
      />
    </div>
    """
  end

  defp resolve_flow(%{node_id: nil} = assigns), do: Flows.get(assigns.flow_id)

  defp resolve_flow(assigns) do
    case Flows.get_node(assigns.node_id) do
      %{subflow_id: subflow_id} when not is_nil(subflow_id) -> Flows.get(subflow_id)
      _other -> nil
    end
  end

  # The edit page of the flow containing `node`: the root's editor when the
  # node sits on the root canvas, otherwise the drill-in editor addressed by
  # the node that embeds the containing flow
  defp parent_edit_path(assigns, node) do
    cond do
      node.flow_id == assigns.root_id ->
        "#{assigns.base}/flows/#{assigns.root_id}/edit"

      parent = Flows.embedding_node(node.flow_id, assigns.root_id) ->
        "#{assigns.base}/flows/#{assigns.root_id}/nodes/#{parent.id}/edit"

      true ->
        "#{assigns.base}/flows/#{assigns.root_id}/edit"
    end
  end

  defp edit_path(%{node_id: nil} = assigns), do: "#{assigns.base}/flows/#{assigns.flow.id}/edit"

  defp edit_path(assigns) do
    "#{assigns.base}/flows/#{assigns.root_id}/nodes/#{assigns.node_id}/edit"
  end
end
