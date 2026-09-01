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

  import FormFlow.Web.Helpers.Paths

  alias FormFlow.Context
  alias FormFlow.Data.Templates.Flows
  alias FormFlow.Data.Templates.Forms
  alias FormFlow.Web.Components.Editor
  alias FormFlow.Web.Helpers.ReactFlow

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
    {:ok,
     socket
     |> assign(:pending_name, Map.get(payload.data, :name, socket.assigns.pending_name))
     |> assign(:pending_type, pending_type(payload, socket.assigns.pending_type))
     |> assign(:notice, nil)}
  end

  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:base, fn -> "" end)
      |> assign_new(:root_id, fn -> nil end)
      |> assign_new(:node_id, fn -> nil end)
      |> assign_new(:config, fn -> nil end)
      |> assign_new(:config_data, fn -> %{} end)

    subflow_node = socket.assigns.node_id && Flows.get_node(socket.assigns.node_id)
    flow = resolve_flow(socket.assigns, subflow_node)
    data = flow && ReactFlow.to_data(flow)
    root = socket.assigns.node_id && Flows.get(socket.assigns.root_id)

    {:ok,
     assign(socket,
       flow: flow,
       data: data,
       current: data,
       root: root,
       pending_name: flow && flow.name,
       pending_type: flow && flow.properties["form_flow_type"],
       form_flow_type_options: form_flow_type_options(socket.assigns, flow, root, subflow_node)
     )}
  end

  # The enabled flow types as dropdown options — see FormFlow.Config
  defp form_flow_type_options(assigns, flow, root, subflow_node) do
    context = %Context{flow: root || flow, subflow: flow, subflow_node: subflow_node}

    config = FormFlow.Config.config_module(assigns.config)
    config_data = assigns.config_data

    context
    |> config.enabled_flow_types(config_data)
    |> type_select_options()
  end

  defp type_select_options(types), do: Enum.map(types, &{&1.name, &1.id})

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
      assigns.pending_type != assigns.flow.properties["form_flow_type"]
  end

  defp navigate_to_node(socket, node_id) do
    push_navigate(socket, to: node_path(socket.assigns, node_id))
  end

  defp node_path(assigns, node_id) do
    root_id = assigns.root_id || assigns.flow.id
    "#{assigns.base}/flows/#{root_id}/nodes/#{node_id}/edit"
  end

  # Edit mode is sticky, like opening a subflow from this canvas: opening a
  # form node lands on a draft's *editor* — the newest existing draft, or a
  # fresh one forked from the latest published version. The show page is
  # where mode isn't sticky: its Open lands on the form's show page.
  defp form_node_path(assigns, node_id) do
    root_id = assigns.root_id || assigns.flow.id
    show_path = "#{assigns.base}/flows/#{root_id}/nodes/#{node_id}/form"

    with %{form_id: form_id} when is_binary(form_id) <- Flows.get_node(node_id),
         %{id: draft_id} <- find_or_create_draft(form_id) do
      "#{show_path}/versions/#{draft_id}/edit"
    else
      _other -> show_path
    end
  end

  defp find_or_create_draft(form_id) do
    newest_draft =
      form_id
      |> Forms.list_versions()
      |> Enum.find(&(&1.status == "draft"))

    case newest_draft do
      %{} = draft ->
        draft

      nil ->
        opts =
          case Forms.get_latest_version(form_id) do
            nil -> []
            published -> [based_on: published.id]
          end

        case Forms.create_draft(form_id, opts) do
          {:ok, draft} -> draft
          {:error, _reason} -> nil
        end
    end
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
      |> Map.put(:properties, pending_properties(socket.assigns))

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
            pending_type: flow.properties["form_flow_type"],
            error: nil
          )
          |> push_event("form_flow:set_flow", %{flow: data})

        {:ok, socket, attrs.id_map}

      {:error, %Ecto.Changeset{}} ->
        {:error, assign(socket, :error, "Could not save the flow. Please try again.")}
    end
  end

  # The saved properties with the form's pending values applied — an unset
  # type removes the key, so "no choice" stays "use the configured default"
  # rather than pinning whatever the default happened to be at save time
  defp pending_properties(assigns) do
    case assigns.pending_type do
      nil -> Map.delete(assigns.flow.properties, "form_flow_type")
      type -> Map.put(assigns.flow.properties, "form_flow_type", type)
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
        <div class="flex items-center gap-2 text-sm font-semibold">
          <%!-- Breadcrumbs stay in edit mode: backing out of a subflow lands
                on the parent's editor, not its show page. They navigate
                through the "navigate" event rather than a bare <.link>, so
                unsaved changes get the same save-first prompt as Open. --%>
          <button
            type="button"
            phx-click="navigate"
            phx-value-to={templates_path(@base)}
            phx-target={@myself}
            class="hover:underline"
          >
            Templates
          </button>
          <span class="text-zinc-400">/</span>
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
          <span>{@flow.name || "Untitled"}</span>
          <span class="text-xs font-normal text-zinc-500">
            {if @flow.label == "subflows", do: "Complex flow", else: "Simple flow"}
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
            class={[
              "rounded-md border px-2 py-1 text-xs",
              if(unsaved_changes?(assigns),
                do: "border-cyan-600 bg-cyan-600 text-white hover:bg-cyan-700",
                else: "border-zinc-300 text-zinc-700 hover:border-zinc-400"
              )
            ]}
          >
            Save
          </button>
        </div>
      </div>

      <p :if={@error} class="mb-2 text-xs text-red-600">{@error}</p>
      <p :if={@notice} class="mb-2 text-xs text-green-700">{@notice}</p>

      <%!-- The flow's own fields, beside the canvas. Edits here are pending
            like canvas edits: nothing persists until the header's Save, which
            writes both — on_change reports values back through send_update,
            so there is no submit of its own (hide_submit). `data` carries the
            *saved* values; pending ones live in this component's assigns.
            The type dropdown only exists on "forms" flows — how the forms
            are presented belongs to the flow of forms itself — with choices
            from the `FormFlow.Config` behaviour (enabled_flow_types). --%>
      <div class="mb-3 max-w-md">
        <DynamicForm.form
          id={"#{@id}-flow-form"}
          data={%{name: @flow.name, form_flow_type: @flow.properties["form_flow_type"]}}
          hide_submit
          on_change={&changed(&1, @id)}
        >
          <:field type="text" name="name" label="Name" />
          <:field
            :if={@flow.label == "forms"}
            type="dropdown"
            name="form_flow_type"
            label="Form flow type"
            options={@form_flow_type_options}
          />
        </DynamicForm.form>
      </div>

      <Editor.editor
        id={"#{@id}-editor"}
        data={@data}
        target={@myself}
        flow_label={@flow.label}
        form_flow_type_options={@form_flow_type_options}
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
