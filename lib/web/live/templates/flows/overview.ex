defmodule FormFlow.Web.Templates.Flows.Overview do
  @moduledoc """
  `FormFlow.Web.Templates.Flows.Overview` LiveComponent shows one root flow
  whole: every level at once, read-only, at `/flows/:id/overview`.

  `FormFlow.Web.Templates.Flows.Show` and `.Edit` work one level at a time -
  a subflow node's Open button drills into that subflow's own canvas. That
  is how a flow is built. This page is how a flow is *read*: it resolves the
  tree (`FormFlow.Data.Templates.Flows.resolve_tree/1`), keeps only the
  nodes connected to each level's Start
  (`FormFlow.Data.Templates.Flows.connected_tree/1`) - the positions a user
  filling the flow in can actually reach - and draws every subflow expanded
  in place (`FormFlow.Web.Components.Overview`). Unconnected nodes are not
  drawn here; the drill-down is where they are seen and fixed.

  Root flows only: the point of the page is the whole flow, so the Show and
  Edit pages link here from any depth with the root's id. Open on a form
  node or a group's header navigates to that node's show page under this
  root, the same destinations the Show page's Open buttons use.

  Three layouts, chosen by the `layout` query param and offered as a
  segmented control in the header, between the health check and the page
  tabs - **Balanced View** | **Vertical View** | **Horizontal View** - so
  each is a URL someone can be sent:

    * `horizontal` - every level runs left to right, Start to End, each
      subflow a box in that line holding its own left-to-right line
    * `balanced` (the default, and what any other value falls back to) - a
      level's steps still run left to right, but its Start stands above
      them at the top-left and its End below at the bottom-right, so a
      subflow is a box entered at its top and left at its bottom, and
      nesting grows the drawing downwards rather than into one long line
    * `vertical` - a level of subflows runs top to bottom, Start to End,
      every subflow's box entered at its top and left at its bottom; a
      level of forms runs left to right as it does on `horizontal`. The
      whole is a stack of wide boxes.

  The canvas is `phx-update="ignore"`, so switching layouts keys it on the
  layout: a different element mounts, and the bundle lays the tree out
  afresh.
  """

  use Phoenix.LiveComponent

  alias FormFlow.Data.Templates.Flows
  alias FormFlow.Web.Components
  alias FormFlow.Web.Components.Core
  alias FormFlow.Web.Components.Overview
  alias FormFlow.Web.Helpers.ReactFlow
  alias FormFlow.Web.Templates.Components.Flows.Tabs
  alias FormFlow.Web.Templates.Components.Header
  alias FormFlow.Web.Templates.Components.Health
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
      |> assign_new(:params, fn -> %{} end)

    tree = socket.assigns.flow_id |> Flows.resolve_tree() |> Flows.connected_tree()

    {:ok,
     assign(socket,
       flow: tree && tree.flow,
       tree: tree && ReactFlow.to_tree_data(tree),
       layout: layout(socket.assigns.params["layout"]),
       # Every type and perspective the page knows, as name lookups: a group
       # header names its stored type and perspectives, and a form node its
       # type, wherever in the tree it sits
       flow_type_options: Shared.canvas_type_options(socket.assigns.flow_types),
       form_type_options: Enum.map(socket.assigns.form_types, &{&1.name, &1.id}),
       perspective_options:
         socket.assigns.flow_types
         |> Shared.all_perspectives()
         |> Shared.perspective_options()
     )}
  end

  defp layout("horizontal"), do: :horizontal
  defp layout("vertical"), do: :vertical
  defp layout(_other), do: :balanced

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
      <%!-- The flow as the root, so the title reads "Flow  Overview" and the
            trail walks Flows / Flow (its show page) / Overview, as the health
            page's does --%>
      <Header.header
        base={@base}
        section="flows"
        root={@flow}
        name="Overview"
        components={@components}
      >
        <:crumb>Overview</:crumb>
        <:actions>
          <Health.health base={@base} flow={@flow} components={@components} />
          <Components.Tabs.tabs
            items={[
              {:balanced, "Balanced View", "#{@base}/flows/#{@flow.id}/overview"},
              {:vertical, "Vertical View", "#{@base}/flows/#{@flow.id}/overview?layout=vertical"},
              {:horizontal, "Horizontal View",
               "#{@base}/flows/#{@flow.id}/overview?layout=horizontal"}
            ]}
            active={@layout}
            label="Layout"
            class="ml-2"
          />
          <Tabs.tabs base={@base} flow={@flow} active={:overview} class="ml-2" />
        </:actions>
      </Header.header>

      <Overview.overview
        id={"#{@id}-overview-#{@layout}"}
        tree={@tree}
        layout={@layout}
        target={@myself}
        flow_type_options={@flow_type_options}
        form_type_options={@form_type_options}
        perspective_options={@perspective_options}
      />
    </div>
    """
  end
end
