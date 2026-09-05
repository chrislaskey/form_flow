defmodule FormFlow.Web.Templates.Flows.Edit do
  @moduledoc """
  `FormFlow.Web.Templates.Flows.Edit` LiveComponent edits an existing flow.

  Loads the flow with `FormFlow.Data.Templates.Flows.get/1`, renders it in the
  editor (see `FormFlow.Web.Components.Editor`), tracks edits as the editor
  reports them, and on save replaces the flow's contents with
  `FormFlow.Data.Templates.Flows.update/2`. Saving a subflows flow also
  creates the children of any freshly added subflow nodes — see
  `FormFlow.Data.Templates.Flows`.

  Edit mode is sticky: saving stays here rather than bouncing to the show
  page — flow editing is a workspace loop, often across several levels. After
  a save the persisted flow is pushed back into the canvas
  (`form_flow:set_flow`), so editor-temporary node ids become the real UUIDs
  — which is what makes Open work on a just-saved subflow node.

  Stickiness ends at a form node's Open, on purpose: it lands on the form's
  *show* page, same as it does from the read-only canvas
  (`FormFlow.Web.Templates.Flows.Show`). A canvas and a form are different
  workspaces with different save models — the canvas edits in place with its
  own Save, a form's answer is a new draft version with its own publish
  lifecycle — so crossing into one from the other is the ordinary boundary,
  not a continuation of it. Reaching a form's *edit* page from here is a
  second, deliberate click, same as it would be from anywhere else.

  Two addressing modes, matching the router:

    * `flow_id` — a flow edited directly, `/flows/:id/edit`
    * `root_id` + `node_id` — a subflow reached by drill-in,
      `/flows/:root_id/nodes/:node_id/edit`; the node's `subflow_id` is the
      flow edited here

  Navigating within the canvas is guarded against losing unsaved changes
  (`current` differs from the last-persisted `data`): the header's Show
  button, a subflow's Open button, and the breadcrumbs all push a generic
  `"navigate"` event with their destination rather than a bare `<.link
  navigate>`, precisely so that event can check first — if the canvas is
  dirty, navigation pauses for a prompt to save first or keep editing instead
  of silently discarding the edit. Open additionally treats a node
  `FormFlow.Data.Templates.Flows.get_node/1` can't find yet (just added,
  never saved) as unsaved, since there's nothing to navigate to until it
  exists. Either way declining leaves the canvas exactly as it was — nothing
  is discarded — and confirming resolves a pending node's editor-temporary id
  to whatever it was actually saved as (see
  `FormFlow.Web.Helpers.ReactFlow.to_flow_attrs/1`'s `id_map`), so Open still
  lands on the right subflow even when it was never saved before this click.

  The same `unsaved_changes?/1` flag also guards two kinds of navigation the
  `"navigate"` event above can't reach, because neither one goes through a
  click this page controls:

    * Closing the tab, refreshing, or typing a new URL — a `beforeunload`
      prompt, reading the flag at the moment it fires.
    * The browser's Back/Forward buttons — LiveView intercepts these itself
      and performs a live navigation over the existing socket, the same way
      `push_navigate/2` does, so the document never unloads and
      `beforeunload` never sees it. LiveView 1.2.8 added exactly the escape
      hatch this needs: it dispatches a cancelable `phx:before-navigate`
      before acting on *any* live navigation, click or popstate alike. The
      hook cancels it and reports the attempted destination through the very
      same `"navigate"` event as everything else, producing the same
      save-first prompt — cancelling this way is native to LiveView, so
      unlike a hand-rolled history trap it doesn't touch `history` itself or
      disturb the forward/back stack. `phx:before-navigate` doesn't exist
      before LiveView 1.2.8, but form_flow's own dependency floor stays at
      1.1.0 rather than forcing every consumer onto it: an app on an older
      LiveView simply never receives the event, so the listener never fires
      — the Back/Forward guard is silently absent there, while `beforeunload`
      above still works regardless of version.

  This needs its own tiny hook rather than piggybacking on
  `FormFlow.Web.Components.Editor`'s: that hook's container is
  `phx-update="ignore"`, so a data attribute on it would never see a new
  value. This hook's div renders normally, so `data-unsaved` is simply read
  at the moment each browser event fires — nothing is mirrored into JS
  state.

  Discard changes is the deliberate opposite: shown only while the canvas is
  dirty, it throws the edit away rather than protecting it, so it asks for
  confirmation first rather than checking for one. Confirming reloads this
  same edit page via `push_navigate/2` — a full remount, refetching the flow
  from scratch — rather than trying to reset in-memory state by hand. That's
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
  alias FormFlow.Web.Components.Core
  alias FormFlow.Web.Components.Editor
  alias FormFlow.Web.Helpers.ReactFlow
  alias FormFlow.Web.Templates.Components.Breadcrumb
  alias FormFlow.Web.Templates.Shared

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket, error: nil, notice: nil, pending_navigation: nil, confirming_discard?: false)}
  end

  # DynamicForm's on_change routed back through send_update: the flow form's
  # values are tracked like canvas edits — nothing persists until Save, and
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
     |> assign(:pending_perspectives, pending_perspectives(payload, pending_type, socket.assigns))
     |> assign(:pending_type, pending_type)
     |> assign(:pending_property_values, Shared.payload_property_values(payload.data, properties))
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

    subflow_node = socket.assigns.node_id && Flows.get_node(socket.assigns.node_id)
    flow = resolve_flow(socket.assigns, subflow_node)
    root = socket.assigns.node_id && Flows.get(socket.assigns.root_id)
    context = %Context{flow: root || flow, subflow: flow, subflow_node: subflow_node}
    types = flow_types(socket.assigns, context)

    {:ok,
     socket
     |> assign(flow: flow, root: root, flow_types: types, form_data: form_data(flow, types))
     |> assign(pending(flow))
     |> assign(page(socket.assigns, flow, root))}
  end

  # The form values the last save wrote, which the identity form edits
  # against — nil across the board for a flow that does not exist
  defp pending(flow) do
    %{
      pending_name: flow && flow.name,
      pending_slug: flow && flow.slug,
      pending_perspectives: Perspective.ids(flow),
      pending_type: flow && flow.properties["form_flow_type"],
      pending_property_values: FormFlow.Config.Flows.Type.property_values(flow)
    }
  end

  # The perspectives the admin has checked, among those the pending type —
  # or, unset, the type it amounts to — declares: a type that declares none
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
      embedded_flow_type_options: type_select_options(flow_types(assigns, embedded)),
      embedded_form_type_options: embedded_form_type_options(assigns),
      embedded_perspective_options:
        Shared.perspective_options(Shared.all_perspectives(flow_types(assigns, embedded)))
    }
  end

  # The identity form's data: the saved values, with the saved type's property
  # values under their field names. Switching the type dropdown re-renders
  # the property fields, and DynamicForm rebuilds a form whose fields changed
  # from its data — so at that moment the data becomes the pending values
  # (reset_form_data_on_switch/2), and the name the admin was typing survives.
  # Otherwise it holds still, which is what keeps in-progress input alive.
  # The type shown is the one the flow amounts to: a flow that never chose
  # shows the first type, which is what it behaves as everywhere else, while
  # its stored value stays unset — "the default" — until the admin picks.
  defp form_data(nil, _types), do: nil

  defp form_data(flow, types) do
    type_id = Shared.effective_type(types, flow.properties["form_flow_type"])
    values = FormFlow.Config.Flows.Type.property_values(flow)

    form_data(
      flow.name,
      flow.slug,
      Perspective.ids(flow),
      type_id,
      Shared.properties(types, type_id),
      values
    )
  end

  defp form_data(name, slug, perspectives, type_id, properties, values) do
    Map.merge(
      %{name: name, slug: slug, perspectives: perspectives, form_flow_type: type_id},
      Shared.field_data(properties, values)
    )
  end

  # The page's flow types for a flow in this context. Empty means the flow
  # has no type of its own, and no dropdown.
  defp flow_types(assigns, %Context{flow: root, subflow_node: node} = context) do
    context
    |> Shared.flow_types_for(assigns)
    |> Shared.fill_related_forms(
      root && root.id,
      node && node.id,
      FormFlow.Config.Flows.Type.property_values(context.subflow)
    )
  end

  defp reset_form_data_on_switch(socket, pending_type) do
    types = socket.assigns.flow_types
    shown_type = Shared.effective_type(types, pending_type)

    if shown_type == socket.assigns.form_data[:form_flow_type] do
      socket
    else
      %{
        flow: flow,
        pending_name: name,
        pending_slug: slug,
        pending_perspectives: perspectives
      } = socket.assigns

      saved_type = Shared.effective_type(types, flow.properties["form_flow_type"])

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
  # param rather than a change to nil — payload.data would keep the old value
  defp pending_type(%{changeset: %{params: %{"form_flow_type" => value}}}, _current) do
    presence(value)
  end

  defp pending_type(_payload, current), do: current

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

  # A form node's Open: same save-first guard as subflows — and a node saved
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

  # Whether the page has edits the last save doesn't reflect yet — `current`
  # tracks every reported `flow_changed` against what `Flows.update/2` last
  # persisted, and the pending form values against the flow's saved ones.
  defp unsaved_changes?(assigns) do
    assigns.current != assigns.data or
      assigns.pending_name != assigns.flow.name or
      assigns.pending_slug != assigns.flow.slug or
      assigns.pending_perspectives != Perspective.ids(assigns.flow) or
      assigns.pending_type != assigns.flow.properties["form_flow_type"] or
      assigns.pending_property_values != FormFlow.Config.Flows.Type.property_values(assigns.flow)
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
  # click — landing here is the same as landing here from the read-only
  # canvas (`FormFlow.Web.Templates.Flows.Show`). `mode=edit` is the one
  # thing that does cross the boundary: it tells the form pages' own
  # breadcrumb (`FormFlow.Web.Templates.Components.Breadcrumb`) that Root
  # and Parent should route back to their editors, not their show pages,
  # since that's where this click came from.
  defp form_node_path(assigns, node_id) do
    root_id = assigns.root_id || assigns.flow.id
    "#{assigns.base}/flows/#{root_id}/nodes/#{node_id}/form?mode=edit"
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
  # it with what was written — temporary editor ids became real UUIDs, and
  # fresh subflow nodes gained their subflow_id — so Open works without a
  # reload. Returns the id_map too: "save_and_continue" needs it to resolve a
  # pending node's editor-temporary id to what it was actually saved as.
  defp persist_current(socket) do
    attrs =
      socket.assigns.current
      |> ReactFlow.to_flow_attrs()
      |> Map.put(:name, socket.assigns.pending_name)
      |> Map.put(:slug, socket.assigns.pending_slug)
      |> Map.put(
        :properties,
        socket.assigns
        |> pending_template_properties()
        |> Perspective.put_ids(socket.assigns.pending_perspectives)
      )

    case Flows.update(socket.assigns.flow, attrs) do
      {:ok, flow} ->
        flow = Flows.get(flow.id)
        data = ReactFlow.to_data(flow)

        socket =
          socket
          |> assign(
            flow: flow,
            data: data,
            current: data,
            pending_name: flow.name,
            pending_slug: flow.slug,
            pending_perspectives: Perspective.ids(flow),
            pending_type: flow.properties["form_flow_type"],
            pending_property_values: FormFlow.Config.Flows.Type.property_values(flow),
            form_data: form_data(flow, socket.assigns.flow_types),
            error: nil
          )
          |> push_event("form_flow:set_flow", %{flow: data})

        {:ok, socket, attrs.id_map}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error,
         assign(
           socket,
           :error,
           Shared.save_error(changeset, "Could not save the flow. Please try again.")
         )}
    end
  end

  # The flow's stored `properties` map with the form's pending values applied
  # — an unset type removes the key and the property values with it, so "no
  # choice" stays "use the configured default" rather than pinning whatever
  # the default happened to be at save time. A type's property values are
  # replaced whole, so switching types leaves nothing of the old one behind —
  # and a type with nothing entered stores no values key at all.
  defp pending_template_properties(assigns) do
    case {assigns.pending_type, assigns.pending_property_values} do
      {nil, _values} ->
        assigns.flow.properties
        |> Map.delete("form_flow_type")
        |> Map.delete("form_flow_type_property_values")

      {type, values} when values == %{} ->
        assigns.flow.properties
        |> Map.put("form_flow_type", type)
        |> Map.delete("form_flow_type_property_values")

      {type, values} ->
        assigns.flow.properties
        |> Map.put("form_flow_type", type)
        |> Map.put("form_flow_type_property_values", values)
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
      <div class="mb-2 h-14 flex items-center justify-between gap-4">
        <%!-- Breadcrumbs stay in edit mode: backing out of a subflow lands
              on the parent's editor, not its show page (`mode="edit"`).
              They navigate through the "navigate" event rather than a bare
              <.link> (`target={@myself}`), so unsaved changes get the same
              save-first prompt as Open. --%>
        <Breadcrumb.breadcrumb
          base={@base}
          section="flows"
          root={@root}
          mode="edit"
          target={@myself}
          components={@components}
        >
          <span>{@flow.name || "Untitled"}</span>
          <span class="text-xs font-normal text-zinc-500">
            {if @flow.label == "subflows", do: "Complex flow", else: "Simple flow"}
          </span>
        </Breadcrumb.breadcrumb>
        <div class="flex items-center gap-2">
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
            <span class="relative inline-flex h-6 w-11 shrink-0 items-center rounded-full bg-cyan-600 transition-colors">
              <span class="inline-block h-5 w-5 translate-x-5 rounded-full bg-white shadow transition-transform" />
            </span>
            <span class="font-semibold text-zinc-900">Edit</span>
          </button>
          <Core.button
            :if={unsaved_changes?(assigns)}
            components={@components}
            phx-click="request_discard"
            phx-target={@myself}
            class="btn btn-error btn-soft"
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
        </div>
      </div>

      <Core.error :if={@error} components={@components}>{@error}</Core.error>
      <p :if={@notice} class="bg-green-50 p-6 rounded-lg w-full my-3 text-sm">{@notice}</p>

      <Editor.editor
        id={"#{@id}-editor"}
        data={@data}
        target={@myself}
        flow_label={@flow.label}
        form_flow_type_options={@embedded_flow_type_options}
        form_type_options={@embedded_form_type_options}
        perspective_options={@embedded_perspective_options}
      />

      <%!-- The flow's own fields, below the canvas. Edits here are pending
            like canvas edits: nothing persists until the header's Save, which
            writes both — on_change reports values back through send_update,
            so there is no submit of its own (hide_submit). `data` carries the
            *saved* values; pending ones live in this component's assigns.
            The type dropdown exists only when the page's flow_types apply
            to this flow — how the forms are presented belongs to the flow
            of forms itself, so that is "forms" flows only. --%>
      <div class="mt-3 max-w-md">
        <DynamicForm.form
          id={"#{@id}-flow-form"}
          data={@form_data}
          hide_submit
          on_change={&changed(&1, @id)}
        >
          <:field type="text" name="name" label="Name" />
          <:field
            type="text"
            name="slug"
            label="Slug"
            description="A stable name for looking this flow up in code — lowercase letters, numbers, _ and -. It does not follow a rename."
          />
          <:field
            :if={@flow_types != []}
            type="dropdown"
            name="form_flow_type"
            label="Form flow type"
            options={type_select_options(@flow_types)}
          />
          <%!-- Who this flow's forms are for (FormFlow.Config.Flows.Perspective):
                the shown type's, like its properties below — a type that
                declares none has no field --%>
          <:field
            :if={Shared.perspectives(@flow_types, shown_type(assigns)) != []}
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

      <div
        :if={@pending_navigation}
        class="fixed inset-0 z-50 flex items-center justify-center bg-black/40"
      >
        <div class="w-80 rounded-md border border-zinc-300 bg-white p-4 shadow-lg">
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
              class="btn btn-error"
            >
              Discard changes
            </Core.button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp resolve_flow(%{node_id: nil} = assigns, _node), do: Flows.get(assigns.flow_id)

  defp resolve_flow(_assigns, %{subflow_id: subflow_id}) when not is_nil(subflow_id) do
    Flows.get(subflow_id)
  end

  defp resolve_flow(_assigns, _node), do: nil

  defp changed(payload, component_id) do
    Phoenix.LiveView.send_update(__MODULE__, %{
      id: component_id,
      event: "change",
      payload: payload
    })

    payload
  end

  defp show_path(%{node_id: nil} = assigns), do: "#{assigns.base}/flows/#{assigns.flow.id}"

  defp show_path(assigns) do
    "#{assigns.base}/flows/#{assigns.root_id}/nodes/#{assigns.node_id}"
  end

  # This edit page's own URL, for Discard's full reload
  defp current_path(%{node_id: nil} = assigns),
    do: "#{assigns.base}/flows/#{assigns.flow.id}/edit"

  defp current_path(assigns) do
    "#{assigns.base}/flows/#{assigns.root_id}/nodes/#{assigns.node_id}/edit"
  end
end
