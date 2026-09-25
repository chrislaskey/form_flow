defmodule FormFlow.Web.Templates.Flows.Edit do
  @moduledoc """
  `FormFlow.Web.Templates.Flows.Edit` LiveComponent edits an existing flow.

  Loads the flow with `FormFlow.Data.Templates.Flows.get/1`, renders it in the
  editor (see `FormFlow.Web.Components.Editor`), tracks edits as the editor
  reports them, and on save replaces the flow's contents with
  `FormFlow.Data.Templates.Flows.update/2`. Saving a subflows flow also
  creates the children of any freshly added subflow nodes - see
  `FormFlow.Data.Templates.Flows`.

  Edit mode is sticky: saving stays here rather than bouncing to the show
  page - flow editing is a workspace loop, often across several levels. After
  a save the persisted flow is pushed back into the canvas
  (`form_flow:set_flow`), so editor-temporary node ids become the real UUIDs
  - which is what makes Open work on a just-saved subflow node.

  Stickiness ends at a form node's Open, on purpose: it lands on the form's
  *show* page, same as it does from the read-only canvas
  (`FormFlow.Web.Templates.Flows.Show`). A canvas and a form are different
  workspaces with different save models - the canvas edits in place with its
  own Save, a form's answer is a new draft version with its own publish
  lifecycle - so crossing into one from the other is the ordinary boundary,
  not a continuation of it. Reaching a form's *edit* page from here is a
  second, deliberate click, same as it would be from anywhere else - except
  for a form nobody has ever published, which has nothing on Show worth
  seeing yet; Open lands straight on its draft's editor (`form_node_path/2`).

  Two addressing modes, matching the router:

    * `flow_id` - a flow edited directly, `/flows/:id/edit`
    * `root_id` + `node_id` - a subflow reached by drill-in,
      `/flows/:root_id/nodes/:node_id/edit`; the node's `subflow_id` is the
      flow edited here

  Navigating within the canvas is guarded against losing unsaved changes
  (`current` differs from the last-persisted `data`): the header's View,
  Overview, and History tabs, a subflow's Open button, and the breadcrumbs
  all push a generic
  `"navigate"` event with their destination rather than a bare `<.link
  navigate>`, precisely so that event can check first - if the canvas is
  dirty, navigation pauses for a prompt to save first or keep editing instead
  of silently discarding the edit. Open additionally treats a node
  `FormFlow.Data.Templates.Flows.get_node/1` can't find yet (just added,
  never saved) as unsaved, since there's nothing to navigate to until it
  exists. Either way declining leaves the canvas exactly as it was - nothing
  is discarded - and confirming resolves a pending node's editor-temporary id
  to whatever it was actually saved as (see
  `FormFlow.Web.Helpers.ReactFlow.to_flow_attrs/1`'s `id_map`), so Open still
  lands on the right subflow even when it was never saved before this click.

  The same `unsaved_changes?/1` flag also guards two kinds of navigation the
  `"navigate"` event above can't reach, because neither one goes through a
  click this page controls:

    * Closing the tab, refreshing, or typing a new URL - a `beforeunload`
      prompt, reading the flag at the moment it fires.
    * The browser's Back/Forward buttons - LiveView intercepts these itself
      and performs a live navigation over the existing socket, the same way
      `push_navigate/2` does, so the document never unloads and
      `beforeunload` never sees it. LiveView 1.2.8 added exactly the escape
      hatch this needs: it dispatches a cancelable `phx:before-navigate`
      before acting on *any* live navigation, click or popstate alike. The
      hook cancels it and reports the attempted destination through the very
      same `"navigate"` event as everything else, producing the same
      save-first prompt - cancelling this way is native to LiveView, so
      unlike a hand-rolled history trap it doesn't touch `history` itself or
      disturb the forward/back stack. `phx:before-navigate` doesn't exist
      before LiveView 1.2.8, but form_flow's own dependency floor stays at
      1.1.0 rather than forcing every consumer onto it: an app on an older
      LiveView simply never receives the event, so the listener never fires
      - the Back/Forward guard is silently absent there, while `beforeunload`
      above still works regardless of version.

  This needs its own tiny hook rather than piggybacking on
  `FormFlow.Web.Components.Editor`'s: that hook's container is
  `phx-update="ignore"`, so a data attribute on it would never see a new
  value. This hook's div renders normally, so `data-unsaved` is simply read
  at the moment each browser event fires - nothing is mirrored into JS
  state.

  Discard changes is the deliberate opposite: shown only while the canvas is
  dirty, it throws the edit away rather than protecting it, so it asks for
  confirmation first rather than checking for one. Confirming reloads this
  same edit page via `push_navigate/2` - a full remount, refetching the flow
  from scratch - rather than trying to reset in-memory state by hand. That's
  deliberately the blunt option: as the canvas grows more state (open panels,
  selections, whatever comes later), reproducing "as freshly loaded" by
  resetting each field by hand only gets more places to miss one, where a
  reload can't drift from what a fresh page load already does correctly. The
  cost is a full round trip and a brief re-render, which is cheap next to
  that.
  """

  use Phoenix.LiveComponent

  alias FormFlow.Config.Flows.Perspective
  alias FormFlow.Context
  alias FormFlow.Data.Templates.Flow
  alias FormFlow.Data.Templates.Flows
  alias FormFlow.Data.Templates.Forms
  alias FormFlow.Web.Components.Core
  alias FormFlow.Web.Components.Dialog
  alias FormFlow.Web.CoreComponents
  alias FormFlow.Web.Components.Editor
  alias FormFlow.Web.Helpers.ReactFlow
  alias FormFlow.Web.Templates.Components.Flows.Tabs
  alias FormFlow.Web.Templates.Components.Header
  alias FormFlow.Web.Components.SectionHeading
  alias FormFlow.Web.Templates.Components.Health
  alias FormFlow.Web.Templates.Shared

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       error: nil,
       notice: nil,
       pending_navigation: nil,
       confirming_discard?: false,
       confirming_save?: false
     )}
  end

  # DynamicForm's on_change routed back through send_update: the flow form's
  # values are tracked like canvas edits - nothing persists until Save, and
  # they count as unsaved changes for the navigation guard.
  @impl true
  def update(%{event: "change", payload: payload}, socket) do
    pending_type = pending_type(payload, socket.assigns.pending_type)
    types = socket.assigns.flow_types
    properties = Shared.properties(types, Shared.effective_type(types, pending_type))

    {:ok,
     socket
     |> assign(:pending_name, Map.get(payload.data, :name, socket.assigns.pending_name))
     |> assign(:pending_slug, Map.get(payload.data, :slug, socket.assigns.pending_slug))
     |> assign(
       :pending_flow_group,
       Map.get(payload.data, :flow_group, socket.assigns.pending_flow_group)
     )
     |> assign(:pending_perspectives, pending_perspectives(payload, pending_type, socket.assigns))
     |> assign(:pending_type, pending_type)
     |> assign(:pending_property_values, Shared.payload_property_values(payload.data, properties))
     |> assign(:pending_status, pending_status(payload, socket.assigns.pending_status))
     |> reset_form_data_on_switch(pending_type)
     |> assign(:notice, nil)}
  end

  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:base, fn -> "" end)
      |> assign_new(:root_id, fn -> nil end)
      |> assign_new(:node_id, fn -> nil end)
      |> assign_new(:flow_types, fn -> FormFlow.Config.Flows.Type.defaults() end)
      |> assign_new(:form_types, fn -> FormFlow.Config.Forms.Type.defaults() end)
      |> assign_new(:callback_data, fn -> %{} end)
      |> assign_new(:components, fn -> nil end)
      |> assign_new(:user_id, fn -> nil end)

    subflow_node = socket.assigns.node_id && Flows.get_node(socket.assigns.node_id)
    flow = resolve_flow(socket.assigns, subflow_node)
    root = socket.assigns.node_id && Flows.get(socket.assigns.root_id)
    context = %Context{flow: root || flow, subflow: flow, subflow_node: subflow_node}
    types = flow_types(socket.assigns, context)

    {:ok,
     socket
     |> assign(
       flow: flow,
       root: root,
       ancestors: ancestors(root, subflow_node),
       subflow_node: subflow_node,
       # The host's lists as given, before the page narrows its own to the
       # flow's kind: the health check reads every level of the tree
       host_types: [flow_types: socket.assigns.flow_types, form_types: socket.assigns.form_types],
       flow_types: types,
       form_data: form_data(flow, subflow_node, types),
       instance_counts: flow && Shared.instance_counts(flow)
     )
     |> assign(pending(flow, subflow_node))
     |> assign(page(socket.assigns, flow, root))}
  end

  # The form values the last save wrote, which the identity form edits
  # against - nil across the board for a flow that does not exist
  defp pending(flow, node) do
    %{
      pending_name: flow && step_name(flow, node),
      pending_slug: flow && step_slug(flow, node),
      pending_flow_group: flow && flow.flow_group,
      pending_perspectives: Perspective.ids(flow),
      pending_type: flow && flow.properties["flow_type"],
      pending_property_values: FormFlow.Config.Flows.Type.property_values(flow),
      pending_status: flow && flow.status
    }
  end

  # The perspectives the admin has checked, among those the pending type -
  # or, unset, the type it amounts to - declares: a type that declares none
  # has no field and its flows are for everyone, and switching types keeps
  # only the ids both types share.
  defp pending_perspectives(payload, pending_type, assigns) do
    types = assigns.flow_types
    shown = Shared.effective_type(types, pending_type)
    offered = for %{id: id} <- Shared.perspectives(types, shown), do: id

    payload.data[:perspectives]
    |> List.wrap()
    |> Enum.filter(&(&1 in offered))
  end

  # The canvas and the dropdown options it offers its nodes
  defp page(_assigns, nil, _root) do
    %{
      data: nil,
      current: nil,
      embedded_flow_type_options: nil,
      embedded_form_type_options: nil,
      embedded_perspective_options: nil
    }
  end

  defp page(assigns, flow, root) do
    data = ReactFlow.to_data(flow)
    embedded = embedded_flow_context(flow, root)

    %{
      data: data,
      current: data,
      embedded_flow_type_options: Shared.canvas_type_options(assigns.flow_types),
      embedded_form_type_options: embedded_form_type_options(assigns),
      embedded_perspective_options:
        Shared.perspective_options(Shared.all_perspectives(flow_types(assigns, embedded)))
    }
  end

  # The identity form's data: the saved values, with the saved type's property
  # values under their field names. Switching the type dropdown re-renders
  # the property fields, and DynamicForm rebuilds a form whose fields changed
  # from its data - so at that moment the data becomes the pending values
  # (reset_form_data_on_switch/2), and the name the admin was typing survives.
  # Otherwise it holds still, which is what keeps in-progress input alive.
  # The type shown is the one the flow amounts to: a flow that never chose
  # shows the first type, which is what it behaves as everywhere else, while
  # its stored value stays unset - "the default" - until the admin picks.
  defp form_data(nil, _node, _types), do: nil

  defp form_data(flow, node, types) do
    type_id = Shared.effective_type(types, flow.properties["flow_type"])
    values = FormFlow.Config.Flows.Type.property_values(flow)

    form_data(
      step_name(flow, node),
      step_slug(flow, node),
      Perspective.ids(flow),
      type_id,
      Shared.properties(types, type_id),
      values
    )
    |> Map.merge(form_data_status(%{flow: flow}))
    |> Map.merge(form_data_group(node, flow.flow_group))
  end

  defp form_data(name, slug, perspectives, type_id, properties, values) do
    Map.merge(
      %{name: name, slug: slug, perspectives: perspectives, flow_type: type_id},
      Shared.field_data(properties, values)
    )
  end

  # The status a root flow's fields form shows; an owned flow has no field
  defp form_data_status(%{flow: %{owner_flow_id: nil, status: status}}), do: %{status: status}
  defp form_data_status(_assigns), do: %{}

  # The group a root flow's fields form shows; an owned subflow has no field
  defp form_data_group(nil, group), do: %{flow_group: group}
  defp form_data_group(_node, _group), do: %{}

  # The page's flow types for a flow in this context. Empty means the flow
  # has no type of its own, and no dropdown.
  defp flow_types(assigns, %Context{flow: root, subflow_node: node} = context) do
    context
    |> Shared.flow_types_for(assigns)
    |> Shared.fill_related_forms(
      root_id: root && root.id,
      node_id: node && node.id,
      tenant_id: context.tenant_id,
      property_values: FormFlow.Config.Flows.Type.property_values(context.subflow)
    )
  end

  defp reset_form_data_on_switch(socket, pending_type) do
    types = socket.assigns.flow_types
    shown_type = Shared.effective_type(types, pending_type)

    if shown_type == socket.assigns.form_data[:flow_type] do
      socket
    else
      %{
        flow: flow,
        subflow_node: node,
        pending_name: name,
        pending_slug: slug,
        pending_flow_group: group,
        pending_perspectives: perspectives,
        pending_status: status
      } = socket.assigns

      saved_type = Shared.effective_type(types, flow.properties["flow_type"])

      values =
        if shown_type == saved_type,
          do: FormFlow.Config.Flows.Type.property_values(flow),
          else: %{}

      assign(
        socket,
        :form_data,
        form_data(
          name,
          slug,
          perspectives,
          shown_type,
          Shared.properties(types, shown_type),
          values
        )
        |> Map.merge(form_data_status(%{flow: %{flow | status: status}}))
        |> Map.merge(form_data_group(node, group))
      )
    end
  end

  # The canvas asks once for every form subflow node it draws, saved or not,
  # so the context is the flow such a node embeds: a "forms" flow owned by
  # this one, which is what saving a new node creates.
  defp embedded_flow_context(flow, root) do
    %Context{flow: root || flow, subflow: %Flow{label: "forms", owner_flow_id: flow.id}}
  end

  defp type_select_options(types), do: Enum.map(types, &{&1.name, &1.id})

  # The canvas's form nodes each collect a form; their type dropdowns share
  # the page's one list
  defp embedded_form_type_options(assigns), do: type_select_options(assigns.form_types)

  # The type the identity form shows and keys its fields on: the pending
  # choice, or the type an unset one amounts to
  defp shown_type(assigns), do: Shared.effective_type(assigns.flow_types, assigns.pending_type)

  # The raw param, not the applied changeset data: picking the prompt again
  # ("") must clear the pending type, and Ecto's cast treats "" as a missing
  # param rather than a change to nil - payload.data would keep the old value
  defp pending_type(%{changeset: %{params: %{"flow_type" => value}}}, _current) do
    presence(value)
  end

  defp pending_type(_payload, current), do: current

  # The raw param, like the type's: the dropdown's value as chosen
  defp pending_status(%{changeset: %{params: %{"status" => value}}}, current) do
    if value in Flow.statuses(), do: value, else: current
  end

  defp pending_status(_payload, current), do: current

  defp presence(""), do: nil
  defp presence(value), do: value

  @impl true
  def handle_event("form_flow:editor_mounted", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("form_flow:flow_changed", %{"nodes" => nodes, "edges" => edges}, socket) do
    {:noreply,
     socket
     |> assign(:current, %{"nodes" => nodes, "edges" => edges})
     |> assign(:notice, nil)}
  end

  @impl true
  def handle_event("form_flow:open_subflow", %{"node_id" => node_id}, socket) do
    if Flows.get_node(node_id) && not unsaved_changes?(socket.assigns) do
      {:noreply, navigate_to_node(socket, node_id)}
    else
      {:noreply, assign(socket, :pending_navigation, {:node, node_id})}
    end
  end

  # A form node's Open: same save-first guard as subflows - and a node saved
  # for the first time only *gets* its form at save, so the pending path
  # resolves after "Save & Continue" through the id_map like subflow opens do
  @impl true
  def handle_event("form_flow:open_form", %{"node_id" => node_id}, socket) do
    node = Flows.get_node(node_id)

    if node && node.form_id && not unsaved_changes?(socket.assigns) do
      {:noreply, push_navigate(socket, to: form_node_path(socket.assigns, node_id))}
    else
      {:noreply, assign(socket, :pending_navigation, {:form_node, node_id})}
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

  # A structural save of a flow with journeys in flight asks first: it moves
  # where those journeys stand, it sweeps them synchronously (the page
  # waits), and copying the flow is usually the better move. Only this
  # button asks. "Save & Continue" is already a prompt - a second modal on
  # top of the first would be two questions for one decision - and the
  # navigation it answers is the admin leaving, where the flow's own state
  # is the thing being rescued.
  @impl true
  def handle_event("save", _params, socket) do
    if confirm_save?(socket.assigns) do
      {:noreply, assign(socket, :confirming_save?, true)}
    else
      {:noreply, save_now(socket)}
    end
  end

  @impl true
  def handle_event("cancel_save", _params, socket) do
    {:noreply, assign(socket, :confirming_save?, false)}
  end

  @impl true
  def handle_event("confirm_save", _params, socket) do
    {:noreply, socket |> assign(:confirming_save?, false) |> save_now()}
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

  # Whether the page has edits the last save doesn't reflect yet - `current`
  # tracks every reported `flow_changed` against what `Flows.update/2` last
  # persisted, and the pending form values against the flow's saved ones.
  defp unsaved_changes?(assigns) do
    assigns.current != assigns.data or
      assigns.pending_name != step_name(assigns.flow, assigns.subflow_node) or
      assigns.pending_slug != step_slug(assigns.flow, assigns.subflow_node) or
      assigns.pending_flow_group != assigns.flow.flow_group or
      assigns.pending_perspectives != Perspective.ids(assigns.flow) or
      assigns.pending_type != assigns.flow.properties["flow_type"] or
      assigns.pending_property_values != FormFlow.Config.Flows.Type.property_values(assigns.flow) or
      assigns.pending_status != assigns.flow.status
  end

  defp navigate_to_node(socket, node_id) do
    push_navigate(socket, to: node_path(socket.assigns, node_id))
  end

  defp node_path(assigns, node_id) do
    root_id = assigns.root_id || assigns.flow.id
    "#{assigns.base}/flows/#{root_id}/nodes/#{node_id}/edit"
  end

  # Unlike a subflow's Open, this is not sticky: a form node's answer is
  # someone else's workspace, with its own edit page reached by its own
  # click - landing here is the same as landing here from the read-only
  # canvas (`FormFlow.Web.Templates.Flows.Show`). `mode=edit` is the one
  # thing that does cross the boundary: it tells the form pages' own
  # header (`FormFlow.Web.Templates.Components.Header`) that Root
  # and Parent should route back to their editors, not their show pages,
  # since that's where this click came from.
  #
  # One exception: a form nobody has ever published has nothing for Show to
  # show - no history, no content a draft might overwrite - so Open lands
  # straight on its (sole) draft's editor, same as it always has for a form
  # node fresh off "Save & Continue". `ever_published?/1` is what already
  # answers this same question for Show's own publish dialog
  # (`FormFlow.Web.Templates.Forms.Show`), for the same reason: nothing is
  # at stake yet.
  defp form_node_path(assigns, node_id) do
    root_id = assigns.root_id || assigns.flow.id
    base_path = "#{assigns.base}/flows/#{root_id}/nodes/#{node_id}/form"

    path =
      with %{form_id: form_id} when is_binary(form_id) <- Flows.get_node(node_id),
           false <- Forms.ever_published?(form_id),
           %{id: draft_id} <- Enum.find(Forms.list_versions(form_id), &(&1.status == "draft")) do
        "#{base_path}/versions/#{draft_id}/edit"
      else
        _other -> base_path
      end

    "#{path}?mode=edit"
  end

  # A plain path was already the destination; a pending node needs its
  # editor-temporary id resolved through what the save just assigned it.
  defp resolve_pending_navigation({:path, to}, _assigns, _id_map), do: to

  defp resolve_pending_navigation({:node, node_id}, assigns, id_map) do
    node_path(assigns, Map.get(id_map, node_id, node_id))
  end

  defp resolve_pending_navigation({:form_node, node_id}, assigns, id_map) do
    form_node_path(assigns, Map.get(id_map, node_id, node_id))
  end

  # Shared by "save" and "save_and_continue": persists the canvas and re-syncs
  # it with what was written - temporary editor ids became real UUIDs, and
  # fresh subflow nodes gained their subflow_id - so Open works without a
  # reload. Returns the id_map too: "save_and_continue" needs it to resolve a
  # pending node's editor-temporary id to what it was actually saved as.
  defp persist_current(socket) do
    attrs =
      socket.assigns.current
      |> ReactFlow.to_flow_attrs()
      |> Map.put(
        :name,
        flow_name(socket.assigns.flow, socket.assigns.subflow_node, socket.assigns.pending_name)
      )
      |> put_flow_slug(socket.assigns.subflow_node, socket.assigns.pending_slug)
      |> put_flow_group(socket.assigns.subflow_node, socket.assigns.pending_flow_group)
      |> Map.put(
        :properties,
        socket.assigns
        |> pending_template_properties()
        |> Perspective.put_ids(socket.assigns.pending_perspectives)
      )

    with {:ok, flow} <- Flows.update(socket.assigns.flow, attrs),
         {:ok, flow} <- update_status(flow, socket.assigns),
         {:ok, node} <-
           update_step(
             socket.assigns.subflow_node,
             socket.assigns.pending_name,
             socket.assigns.pending_slug
           ) do
      # One save, one recomputation - after everything the save wrote; the
      # root is read again for the status it now carries
      FormFlow.Data.Templates.Flows.Health.refresh(flow, socket.assigns.host_types)
      flow = Flows.get(flow.id)
      sweep_error = sweep_next_positions(socket.assigns.flow, flow, socket.assigns)
      root = socket.assigns.root && Flows.get(socket.assigns.root.id)
      data = ReactFlow.to_data(flow)

      socket =
        socket
        |> assign(
          flow: flow,
          root: root,
          subflow_node: node,
          data: data,
          current: data,
          pending_name: step_name(flow, node),
          pending_slug: step_slug(flow, node),
          pending_flow_group: flow.flow_group,
          pending_perspectives: Perspective.ids(flow),
          pending_type: flow.properties["flow_type"],
          pending_property_values: FormFlow.Config.Flows.Type.property_values(flow),
          pending_status: flow.status,
          form_data: form_data(flow, node, socket.assigns.flow_types),
          instance_counts: Shared.instance_counts(flow),
          error: sweep_error
        )
        |> push_event("form_flow:set_flow", %{flow: data})

      {:ok, socket, attrs.id_map}
    else
      {:error, :unknown_status} ->
        {:error, assign(socket, :error, "That is not a status a flow can have.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error,
         assign(
           socket,
           :error,
           Shared.save_error(changeset, "Could not save the flow. Please try again.")
         )}
    end
  end

  # A save that changed the structure of the flow - its steps, its edges,
  # or its type - can move where every open journey of the root is open,
  # so the cache of that is recomputed for all of them, here, and the page
  # waits (`FormFlow.Data.Instances.Flows.update_next_positions/2`). A save
  # that changed only a name, a slug, a description, a status, or the
  # flow's perspectives moves no position and sweeps nothing: the
  # perspective mapping is read live. Structure is compared as what the
  # derivation reads of it: each step's id and what it points at, each
  # edge's ends, and the flow's type.
  #
  # The save is already committed when this runs, so a sweep that does not
  # finish is reported beside "Saved." rather than raised: the page keeps
  # the admin's work, and the message says how the cache catches up - the
  # journey's page repairs a stale row on open, and a second save sweeps
  # again. Returns the message, or nil.
  defp sweep_next_positions(%Flow{} = before, %Flow{} = after_save, assigns) do
    if structure(before, assigns.flow_types) != structure(after_save, assigns.flow_types) do
      case FormFlow.Data.Instances.Flows.update_next_positions(after_save,
             flow_types: assigns.flow_types,
             callback_data: assigns.callback_data
           ) do
        {:ok, _count} ->
          nil

        {:error, _reason} ->
          "The flow was saved, but recomputing where its open flow instances stand did not " <>
            "finish. Opening a flow instance brings it up to date, and saving again retries."
      end
    end
  end

  defp save_now(socket) do
    case persist_current(socket) do
      {:ok, socket, _id_map} -> assign(socket, :notice, "Saved.")
      {:error, socket} -> socket
    end
  end

  # Whether this save has to ask first: it changes the structure, and the
  # root has journeys in flight for that change to move. Both halves have
  # to be true. A rename, a slug, a description, a status, a perspective, or
  # a node dragged to a new place asks nothing, however many journeys are
  # open; and a flow nobody has started is the admin's to reshape freely,
  # which is the whole point of building one before it opens.
  defp confirm_save?(assigns) do
    open_journeys(assigns) > 0 and structural_save?(assigns)
  end

  # The pending canvas read as `structure/2` reads a saved flow - the same
  # three facts, from the node and edge maps the canvas holds rather than
  # from rows. `ReactFlow.to_flow_attrs/1` is what the save itself would
  # pass to `Flows.update/2`, so this asks of the pending state exactly what
  # the post-save comparison asks of the result, and the two cannot drift.
  defp structural_save?(assigns) do
    canvas_structure(assigns.current, assigns) != canvas_structure(assigns.data, assigns) or
      pending_type_module(assigns) != structure(assigns.flow, assigns.flow_types).flow_type
  end

  defp canvas_structure(data, assigns) do
    attrs = ReactFlow.to_flow_attrs(data)

    %{
      nodes:
        attrs.nodes
        |> Enum.map(&{&1.id, &1.properties["form_id"], &1.properties["subflow_id"]})
        |> Enum.sort(),
      relationships:
        attrs.relationships |> Enum.map(&{&1.source_id, &1.target_id}) |> Enum.sort(),
      flow_types: assigns.flow_types
    }
  end

  # The module the type picker's pending value resolves to, compared with the
  # saved flow's the same way `structure/2` compares them: an unset value
  # resolving to the same module as the stored one is no change
  defp pending_type_module(%{flow: %Flow{} = flow} = assigns) do
    pending = %{
      flow
      | properties: Map.put(flow.properties || %{}, "flow_type", assigns.pending_type)
    }

    FormFlow.Config.Flows.Type.for_flow(assigns.flow_types, pending).module
  end

  # The journeys a structural save would move: the **root's**, since every
  # journey is a traversal of the whole tree and a subflow's save reshapes
  # part of it. Editing a subflow, the counts on the page are the root's
  # too.
  defp open_journeys(assigns) do
    case assigns.root || assigns.flow do
      %Flow{owner_flow_id: nil} = root ->
        Map.get(Flows.instance_counts(root), "in_progress", 0)

      _owned ->
        0
    end
  end

  # The type as the module that answers for it, not the stored id: a save
  # that writes the default's id where none was stored changes no rule
  defp structure(%Flow{} = flow, flow_types) do
    %{
      nodes: flow.nodes |> Enum.map(&{&1.id, &1.form_id, &1.subflow_id}) |> Enum.sort(),
      relationships: flow.relationships |> Enum.map(&{&1.source_id, &1.target_id}) |> Enum.sort(),
      flow_type: FormFlow.Config.Flows.Type.for_flow(flow_types, flow).module
    }
  end

  # The flow's stored `properties` map with the form's pending values applied
  # - an unset type removes the key and the property values with it, so "no
  # choice" stays "use the configured default" rather than storing whatever
  # the default happened to be at save time. A type's property values are
  # replaced whole, so switching types leaves nothing of the old one behind -
  # and a type with nothing entered stores no values key at all.
  defp pending_template_properties(assigns) do
    case {assigns.pending_type, assigns.pending_property_values} do
      {nil, _values} ->
        assigns.flow.properties
        |> Map.delete("flow_type")
        |> Map.delete("flow_type_property_values")

      {type, values} when values == %{} ->
        assigns.flow.properties
        |> Map.put("flow_type", type)
        |> Map.delete("flow_type_property_values")

      {type, values} ->
        assigns.flow.properties
        |> Map.put("flow_type", type)
        |> Map.put("flow_type_property_values", values)
    end
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
      <div
        id={"#{@id}-unsaved-guard"}
        phx-hook=".UnsavedGuard"
        phx-target={@myself}
        data-unsaved={to_string(unsaved_changes?(assigns))}
        style="display: none;"
      >
      </div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".UnsavedGuard">
        export default {
          mounted() {
            this.beforeNavigateHandler = (e) => {
              if (this.el.dataset.unsaved !== "true") return

              e.preventDefault()
              const {pathname, search, hash} = new URL(e.detail.href)
              this.pushEventTo(this.el, "navigate", {to: pathname + search + hash})
            }
            window.addEventListener("phx:before-navigate", this.beforeNavigateHandler)

            this.beforeUnloadHandler = (e) => {
              if (this.el.dataset.unsaved === "true") {
                e.preventDefault()
                e.returnValue = ""
              }
            }
            window.addEventListener("beforeunload", this.beforeUnloadHandler)
          },
          destroyed() {
            window.removeEventListener("phx:before-navigate", this.beforeNavigateHandler)
            window.removeEventListener("beforeunload", this.beforeUnloadHandler)
          }
        }
      </script>
      <%!-- Breadcrumbs stay in edit mode: backing out of a subflow lands
            on the parent's editor, not its show page (`mode="edit"`).
            They navigate through the "navigate" event rather than a bare
            <.link> (`target={@myself}`), so unsaved changes get the same
            save-first prompt as Open. --%>
      <Header.header
        base={@base}
        section="flows"
        root={@root}
        name={@flow.name || "Untitled"}
        ancestors={@ancestors}
        mode="edit"
        target={@myself}
        components={@components}
      >
        <:actions>
          <%!-- The root's health, cached, from any depth - through the
                "navigate" event, as above --%>
          <Health.health base={@base} flow={@root || @flow} target={@myself} components={@components} />
          <Core.button
            :if={unsaved_changes?(assigns)}
            components={@components}
            phx-click="request_discard"
            phx-target={@myself}
            class="btn btn-error btn-ghost"
          >
            Discard changes
          </Core.button>
          <Core.button
            components={@components}
            phx-click="save"
            phx-target={@myself}
            variant={if(unsaved_changes?(assigns), do: "primary")}
          >
            Save
          </Core.button>
          <%!-- The four views of the flow, this one chosen - through the
                "navigate" event like every other way off this page, so
                unsaved changes prompt first. Not links: a link would leave
                before the prompt --%>
          <Tabs.tabs
            base={@base}
            flow={@flow}
            root_id={@root_id}
            node_id={@node_id}
            active={:edit}
            target={@myself}
            class="mx-2"
          />
        </:actions>
      </Header.header>

      <Core.error :if={@error} components={@components}>{@error}</Core.error>
      <p :if={@notice} class="bg-green-50 p-6 rounded-lg w-full my-3 text-sm">{@notice}</p>
      <Editor.editor
        id={"#{@id}-editor"}
        data={@data}
        target={@myself}
        flow_label={@flow.label}
        flow_type_options={@embedded_flow_type_options}
        form_type_options={@embedded_form_type_options}
        perspective_options={@embedded_perspective_options}
      />

      <%!-- The flow's own fields, below the canvas. Edits here are pending
            like canvas edits: nothing persists until the header's Save, which
            writes both - on_change reports values back through send_update,
            so there is no submit of its own (hide_submit). `data` carries the
            *saved* values; pending ones live in this component's assigns.
            The type dropdown offers the page's flow_types of this flow's
            kind - how its forms are presented for a "forms" flow, the order
            its subflows are worked in for a "subflows" flow.

            Under the show page's heading and inside its border, so the
            two pages read as one sheet. Three columns, in two groups: who
            the flow is (name, slug, group, status), then what it is (kind, read
            only - it is fixed at creation - then type, perspectives, and
            the type's properties, wrapping three to a row). The groups are laid out
            from here, by the attribute DynamicForm puts on each - a grid
            in place of the library's content-sized flex row, so every
            member takes exactly a column - and stack to one column below
            md. The status summary sits between them at the page's width;
            it is what splits them, so an owned subflow, which has no
            status, has one group and its fields fill each row in turn
            (kind_group/1). --%>
      <SectionHeading.section_heading
        title="Flow details"
        description={details_description(assigns)}
        class="mt-6 mb-3"
      />
      <div class={[
        "p-6 border border-zinc-300 rounded-lg",
        "[&_[data-dynamic-form-group]>div]:grid [&_[data-dynamic-form-group]>div]:grid-cols-1",
        "md:[&_[data-dynamic-form-group]>div]:grid-cols-3",
        "[&_[data-dynamic-form-group]>div]:items-start [&_[data-dynamic-form-group]>div>*]:min-w-0"
      ]}>
        <DynamicForm.form
          id={"#{@id}-flow-form"}
          data={@form_data}
          hide_submit
          on_change={&changed(&1, @id)}
          components={@components || CoreComponents}
        >
          <:group name="identity" type="horizontal" title={false} />
          <:field
            group="identity"
            type="text"
            name="name"
            label={name_label(assigns)}
          />
          <:field
            group="identity"
            type="text"
            name="slug"
            label={slug_label(assigns)}
            description={slug_description(assigns)}
          />
          <%!-- Which page lists the flow, on a root flow only: a host page
                builds its `flows` from the group, so the admin's choice here
                is what puts the flow on it (FormFlow.Data.Templates.Flow,
                "Group"). --%>
          <:field
            :if={is_nil(@flow.owner_flow_id)}
            group="identity"
            type="text"
            name="flow_group"
            label="Group"
            description={flow_group_description()}
          />
          <%!-- What users may do with the flow (FormFlow.Data.Templates.Flow's
                status table), on a root flow only - an owned subflow's is
                its root's. The summary under the row redraws for the
                pending choice, the way the form edit page explains its type,
                and says how many instances the choice reaches. --%>
          <:field
            :if={is_nil(@flow.owner_flow_id)}
            group="identity"
            type="dropdown"
            name="status"
            label="Status"
            options={Shared.status_options()}
            required
          />
          <:field :if={is_nil(@flow.owner_flow_id)} type="html" name="status_summary">
            <.status_callout status={@pending_status} counts={@instance_counts} />
          </:field>
          <:group :if={is_nil(@flow.owner_flow_id)} name="kind" type="horizontal" title={false} />
          <:field group={kind_group(assigns)} type="html" name="flow_kind">
            <div class="min-w-0">
              <p class="text-sm font-medium text-zinc-500">Flow kind</p>
              <p class="mt-0.5 text-sm">{Shared.kind_label(@flow)}</p>
            </div>
          </:field>
          <:field
            :if={@flow_types != []}
            group={kind_group(assigns)}
            type="dropdown"
            name="flow_type"
            label="Flow type"
            options={type_select_options(@flow_types)}
          />
          <%!-- Who this flow's forms are for (FormFlow.Config.Flows.Perspective):
                the shown type's, like its properties below - a type that
                declares none has no field --%>
          <:field
            :if={Shared.perspectives(@flow_types, shown_type(assigns)) != []}
            group={kind_group(assigns)}
            type="checkbox"
            name="perspectives"
            label="Perspectives"
            description={
              Shared.perspectives_description(
                @flow,
                Shared.perspectives(@flow_types, shown_type(assigns))
              )
            }
            options={
              Shared.perspective_options(Shared.perspectives(@flow_types, shown_type(assigns)))
            }
          />
          <%!-- The shown type's properties (FormFlow.Config.Property), one
                field each; picking another type swaps them --%>
          <:field
            :for={property <- Shared.properties(@flow_types, shown_type(assigns))}
            group={kind_group(assigns)}
            type={Shared.field_type(property)}
            input_type={Shared.input_type(property)}
            name={Shared.field_name(property)}
            label={property.name}
            description={property.description}
            options={Shared.field_options(property)}
            required={property.required}
            read_only={Shared.read_only?(property)}
            default={property.default_value}
          />
        </DynamicForm.form>
      </div>

      <Dialog.dialog :if={@pending_navigation} width={:small}>
        <p class="mb-4 text-sm text-zinc-700">
          This flow has unsaved changes. Save before continuing?
        </p>
        <div class="flex justify-end gap-2">
          <Core.button
            components={@components}
            phx-click="cancel_navigation"
            phx-target={@myself}
            class="btn"
          >
            Keep editing
          </Core.button>
          <Core.button
            components={@components}
            phx-click="save_and_continue"
            phx-target={@myself}
            variant="primary"
          >
            Save &amp; Continue
          </Core.button>
        </div>
      </Dialog.dialog>

      <%!-- A structural save with journeys in flight: what it will do to
            them, how long the page will wait, and the way round it --%>
      <Dialog.dialog :if={@confirming_save?} width={:medium}>
        <p class="mb-2 text-sm font-medium text-zinc-900">
          {Shared.count(open_journeys(assigns), "flow instance")} still in progress.
        </p>
        <p class="mb-2 text-sm text-zinc-700">
          This save changes the shape of the flow - its steps, how they connect, or
          how it is worked. Those flow instances are part-way through the old shape.
          Answers already given are kept, but where each one stands is recomputed, and
          a step somebody was about to reach can move or disappear.
        </p>
        <p :if={Shared.sweep_estimate(open_journeys(assigns))} class="mb-2 text-sm text-zinc-700">
          Recomputing them takes {Shared.sweep_estimate(open_journeys(assigns))}, and this page
          waits for it.
        </p>
        <p class="mb-4 text-sm text-zinc-700">
          Consider copying the flow instead: change the copy, and set this one to
          <em>Winding down</em>
          so the flow instances already started finish against the shape they started on.
        </p>
        <div class="flex justify-end gap-2">
          <Core.button
            components={@components}
            phx-click="cancel_save"
            phx-target={@myself}
            class="btn"
          >
            Keep editing
          </Core.button>
          <Core.button
            components={@components}
            phx-click="confirm_save"
            phx-target={@myself}
            class="btn btn-error"
          >
            Save anyway
          </Core.button>
        </div>
      </Dialog.dialog>

      <Dialog.dialog :if={@confirming_discard?} width={:small}>
        <p class="mb-4 text-sm text-zinc-700">
          Discard changes? This can't be undone.
        </p>
        <div class="flex justify-end gap-2">
          <Core.button
            components={@components}
            phx-click="cancel_discard"
            phx-target={@myself}
            class="btn"
          >
            Keep editing
          </Core.button>
          <Core.button
            components={@components}
            phx-click="confirm_discard"
            phx-target={@myself}
            class="btn btn-error btn-ghost"
          >
            Discard changes
          </Core.button>
        </div>
      </Dialog.dialog>
    </div>
    """
  end

  # The breadcrumb's way down from the root to the flow the subflow node sits
  # in - one crumb per level, empty on the root canvas
  defp ancestors(nil, _subflow_node), do: []
  defp ancestors(root, subflow_node), do: Flows.embedding_nodes(subflow_node.flow_id, root.id)

  defp resolve_flow(%{node_id: nil} = assigns, _node), do: Flows.get(assigns.flow_id)

  defp resolve_flow(_assigns, %{subflow_id: subflow_id}) when not is_nil(subflow_id) do
    Flows.get(subflow_id)
  end

  defp resolve_flow(_assigns, _node), do: nil

  # What the Name field edits. Reached through a node, it is the step: the
  # node's label, which is what the instance pages show users, and the
  # subflow's name is the same value, written alongside. The root flow, with
  # no node, edits its own name.
  defp step_name(flow, nil), do: flow.name
  defp step_name(flow, node), do: get_in(node.properties, ["data", "label"]) || flow.name

  defp flow_name(flow, nil, pending_name), do: pending_name || flow.name
  defp flow_name(_flow, _node, pending_name), do: pending_name

  # What the Slug field edits: through a node, the step's slug - an owned
  # subflow has none of its own; at the root, the flow's
  defp step_slug(flow, nil), do: flow.slug
  defp step_slug(_flow, node), do: node.slug

  defp put_flow_slug(attrs, nil, slug), do: Map.put(attrs, :slug, slug)
  defp put_flow_slug(attrs, _node, _slug), do: attrs

  # The group is the root flow's alone; through a node the form has no field
  defp put_flow_group(attrs, nil, group), do: Map.put(attrs, :flow_group, group)
  defp put_flow_group(attrs, _node, _group), do: attrs

  defp update_step(nil, _name, _slug), do: {:ok, nil}
  defp update_step(node, name, slug), do: Flows.update_node(node, %{label: name, slug: slug})

  # The status is saved with everything else but written by its own function,
  # so the change has its event - with the admin at this page as its author -
  # and an unchanged status writes none (`update_status/3` is a no-op then).
  # Only a root flow has one to move.
  defp update_status(%{owner_flow_id: nil} = flow, %{pending_status: status, user_id: user_id})
       when is_binary(status) do
    Flows.update_status(flow, status, user_id: user_id)
  end

  defp update_status(flow, _assigns), do: {:ok, flow}

  # The group the type, perspectives, and properties sit in: their own on a
  # root flow, after the status summary; the identity group on an owned
  # subflow, which has no status to split the fields around
  defp kind_group(%{flow: %{owner_flow_id: nil}}), do: "kind"
  defp kind_group(_assigns), do: "identity"

  # What the sheet holds, said once above it - the show page's words, so
  # the two pages read as one
  defp details_description(%{flow: %{owner_flow_id: nil}}),
    do: "What every step of this flow shares: its name, slug, group, status, and kind."

  defp details_description(_assigns),
    do: "What every step of this subflow shares: its name, slug, and kind."

  defp name_label(%{node_id: nil}), do: "Name"
  defp name_label(_assigns), do: "Step name"

  defp slug_label(%{node_id: nil}), do: "Slug"
  defp slug_label(_assigns), do: "Step slug"

  defp slug_description(%{node_id: nil}),
    do:
      "A stable name for looking this flow up in code - lowercase letters, numbers, _ and -. " <>
        "It does not follow a rename."

  defp slug_description(_assigns),
    do:
      "A stable name for looking this step up in code - lowercase letters, numbers, _ and -. " <>
        "It does not follow a rename."

  defp flow_group_description,
    do:
      "Which page lists this flow - a name the host's pages ask for in code, " <>
        "lowercase letters, numbers, _ and -. Leave it blank for a flow no page claims."

  defp status_callout(%{status: nil} = assigns), do: ~H""

  defp status_callout(assigns) do
    ~H"""
    <div class="rounded-md border border-zinc-200 bg-zinc-50 px-3 py-2 text-sm">
      <div class="font-medium text-zinc-800">{Shared.status_label(@status)}</div>
      <p class="mt-0.5 text-xs text-zinc-600">{Shared.status_summary(@status)}</p>
      <p :if={Shared.instance_counts_sentence(@counts)} class="mt-0.5 text-xs text-zinc-600">
        {Shared.instance_counts_sentence(@counts)}
      </p>
    </div>
    """
  end

  defp changed(payload, component_id) do
    Phoenix.LiveView.send_update(__MODULE__, %{
      id: component_id,
      event: "change",
      payload: payload
    })

    payload
  end

  # This edit page's own URL, for Discard's full reload
  defp current_path(%{node_id: nil} = assigns),
    do: "#{assigns.base}/flows/#{assigns.flow.id}/edit"

  defp current_path(assigns) do
    "#{assigns.base}/flows/#{assigns.root_id}/nodes/#{assigns.node_id}/edit"
  end
end
