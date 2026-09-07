defmodule FormFlow.Web.Templates.Flows.Overview do
  @moduledoc """
  `FormFlow.Web.Templates.Flows.Overview` LiveComponent shows one root flow
  whole: every level at once, read-only, at `/flows/:id/overview`.

  `FormFlow.Web.Templates.Flows.Show` and `.Edit` work one level at a time —
  a subflow node's Open button drills into that subflow's own canvas. That
  is how a flow is built. This page is how a flow is *read*: it resolves the
  tree (`FormFlow.Data.Templates.Flows.resolve_tree/1`), keeps only the
  nodes connected to each level's Start
  (`FormFlow.Data.Templates.Flows.connected_tree/1`) — the positions a user
  filling the flow in can actually reach — and draws every subflow expanded
  in place (`FormFlow.Web.Components.Overview`). Unconnected nodes are not
  drawn here; the drill-down is where they are seen and fixed.

  Root flows only: the point of the page is the whole flow, so the Show and
  Edit pages link here from any depth with the root's id. Open on a form
  node or a group's header navigates to that node's show page under this
  root, the same destinations the Show page's Open buttons use.
  """

  use Phoenix.LiveComponent

  alias FormFlow.Data.Templates.Flows
  alias FormFlow.Web.Components.Core
  alias FormFlow.Web.Components.Overview
  alias FormFlow.Web.Helpers.ReactFlow
  alias FormFlow.Web.Templates.Components.Breadcrumb
  alias FormFlow.Web.Templates.Shared

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:base, fn -> "" end)
      |> assign_new(:flow_types, fn -> FormFlow.Config.Flows.Type.defaults() end)
      |> assign_new(:form_types, fn -> FormFlow.Config.Forms.Type.defaults() end)
      |> assign_new(:components, fn -> nil end)

    tree = socket.assigns.flow_id |> Flows.resolve_tree() |> Flows.connected_tree()

    {:ok,
     assign(socket,
       flow: tree && tree.flow,
       tree: tree && ReactFlow.to_tree_data(tree),
       # Every type and perspective the page knows, as name lookups: a group
       # header names its stored type and perspectives, and a form node its
       # type, wherever in the tree it sits
       form_flow_type_options: Enum.map(socket.assigns.flow_types, &{&1.name, &1.id}),
       form_type_options: Enum.map(socket.assigns.form_types, &{&1.name, &1.id}),
       perspective_options:
         socket.assigns.flow_types
         |> Shared.all_perspectives()
         |> Shared.perspective_options()
     )}
  end

  @impl true
  def handle_event("form_flow:overview_mounted", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("form_flow:open_form", %{"node_id" => node_id}, socket) do
    {:noreply,
     push_navigate(socket,
       to: "#{socket.assigns.base}/flows/#{socket.assigns.flow.id}/nodes/#{node_id}/form"
     )}
  end

  @impl true
  def handle_event("form_flow:open_subflow", %{"node_id" => node_id}, socket) do
    {:noreply,
     push_navigate(socket,
       to: "#{socket.assigns.base}/flows/#{socket.assigns.flow.id}/nodes/#{node_id}"
     )}
  end

  @impl true
  def render(%{flow: nil} = assigns) do
    ~H"""
    <div>
      <Core.alert components={@components}>
        <span>Flow not found.</span>
        <.link navigate={"#{@base}/flows"} class="link link-primary">Back to flows</.link>
      </Core.alert>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div>
      <div class="mb-2 h-14 flex items-center justify-between gap-4">
        <Breadcrumb.breadcrumb base={@base} section="flows" components={@components}>
          {@flow.name || "Untitled"}
          <span class="ml-1 text-xs font-normal text-zinc-500">Overview</span>
        </Breadcrumb.breadcrumb>
        <div class="flex items-center gap-4 text-xs">
          <span class="text-zinc-500">Connected steps only, every level at once.</span>
          <.link navigate={"#{@base}/flows/#{@flow.id}"} class="link link-primary">
            Show
          </.link>
          <.link navigate={"#{@base}/flows/#{@flow.id}/edit"} class="link link-primary">
            Edit
          </.link>
        </div>
      </div>

      <Overview.overview
        id={"#{@id}-overview"}
        tree={@tree}
        target={@myself}
        form_flow_type_options={@form_flow_type_options}
        form_type_options={@form_type_options}
        perspective_options={@perspective_options}
      />
    </div>
    """
  end
end
