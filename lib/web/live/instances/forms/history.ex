defmodule FormFlow.Web.Instances.Forms.History do
  @moduledoc """
  `FormFlow.Web.Instances.Forms.History` LiveComponent lists what has
  happened to the form at one position of a flow instance, newest first, at
  `/:id/forms/*path/history`: started, submitted, reopened, moved to a new
  version - each with who did it and when.

  It is the third view of a form beside `FormFlow.Web.Instances.Forms.Show`
  and `FormFlow.Web.Instances.Forms.Edit`, and the header offers the three
  as tabs. It is addressed by position and resolves it the way the other
  two do (`FormFlow.Web.Instances.Forms.Shared`), asks the host's `on_mount`
  the same way, and starts nothing. Nothing on the page decides anything:
  the trail is audit, not state (`FormFlow.Data.Instances.Form.Event`), and
  this page only reads it.

  What the trail holds is what the data layer writes. A reopen records who
  and when, not why - there is no note from a reviewer to quote under it
  yet (`archive/plans/instances-refresh.md` §7).

  ## The states it draws

  Every one of `FormFlow.Web.Instances.Shared.form_page_state/1`'s, each in
  its own `render/1` clause, and nothing else:

    * `:flow_not_found` - "This flow no longer exists."
    * `:redirecting` - nothing, while the host's `on_mount` navigates away
    * `:refused` - the host's message alone
    * `:not_visible` - "This form is not part of your work here."
    * `:not_started` - nothing has happened here yet, and the way onward
    * `:broken_definition`, `:ready`, `:completed` - the trail. A
      definition that will not parse is Edit's and Show's problem; the
      events are still true and still worth reading
  """

  use Phoenix.LiveComponent

  alias FormFlow.Data.Instances
  alias FormFlow.Web.Components.Core
  alias FormFlow.Web.Instances.Components.Forms.Status
  alias FormFlow.Web.Instances.Components.Forms.Tabs
  alias FormFlow.Web.Instances.Components.Header
  alias FormFlow.Web.Instances.Forms.Shared
  alias FormFlow.Web.Instances.Paths

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:base, fn -> "" end)
      |> assign_new(:tenant_id, fn -> nil end)
      |> assign_new(:perspectives, fn -> [] end)
      |> assign_new(:flow_types, fn -> FormFlow.Config.Flows.Type.defaults() end)
      |> assign_new(:form_types, fn -> FormFlow.Config.Forms.Type.defaults() end)
      |> assign_new(:callback_data, fn -> %{} end)
      |> assign_new(:components, fn -> nil end)
      |> assign_new(:on_mount, fn -> nil end)
      |> assign_new(:instances, fn -> nil end)
      |> assign_new(:flows, fn -> nil end)
      |> assign_new(:pre_release_user_ids, fn -> [] end)
      |> assign_new(:download_path, fn -> nil end)
      |> assign_new(:uri, fn -> nil end)
      |> assign_new(:params, fn -> %{} end)

    socket = load(socket)

    {:ok,
     assign(socket, :page_state, FormFlow.Web.Instances.Shared.form_page_state(socket.assigns))}
  end

  defp load(%{assigns: %{flow_instance_id: flow_instance_id}} = socket) do
    case Instances.Flows.get(flow_instance_id) do
      nil ->
        assign(socket, :flow_instance, nil)

      flow_instance ->
        socket = socket |> assign(:flow_instance, flow_instance) |> Shared.assigns()

        Shared.on_mount(socket)
    end
  end

  @impl true
  def handle_async(:navigate, {:ok, to}, socket) do
    {:noreply, push_navigate(socket, to: to)}
  end

  @impl true
  def render(%{page_state: :flow_not_found} = assigns) do
    ~H"""
    <div>
      <Core.alert components={@components}>
        <span>This flow no longer exists.</span>
        <.link navigate={Paths.flows_path(@base)} class="link link-primary">
          Back to flows
        </.link>
      </Core.alert>
    </div>
    """
  end

  def render(%{page_state: :redirecting} = assigns) do
    ~H"""
    <div></div>
    """
  end

  def render(%{page_state: :refused} = assigns) do
    ~H"""
    <div>
      <.page_header {header_assigns(assigns)} tabs={false} />

      <Core.alert components={@components}>
        <span>{@mount_error}</span>
        <.link navigate={Paths.flow_path(@base, @flow_instance.id)} class="link link-primary">
          Back to the flow
        </.link>
      </Core.alert>
    </div>
    """
  end

  def render(%{page_state: :not_visible} = assigns) do
    ~H"""
    <div>
      <.page_header {header_assigns(assigns)} tabs={false} />

      <Core.alert components={@components}>
        <span>This form is not part of your work here.</span>
        <.link navigate={Paths.flow_path(@base, @flow_instance.id)} class="link link-primary">
          Back to the flow
        </.link>
      </Core.alert>
    </div>
    """
  end

  # No instance, so no trail: the first event is the start, which is Edit's
  def render(%{page_state: :not_started} = assigns) do
    ~H"""
    <div>
      <.page_header {header_assigns(assigns)} />

      <Core.alert components={@components}>
        <span>Nothing has happened here yet.</span>
        <.link
          :if={@editable?}
          navigate={Paths.form_edit_path(@base, @flow_instance.id, @path)}
          class="link link-primary"
        >
          Start this form
        </.link>
        <.link navigate={Paths.flow_path(@base, @flow_instance.id)} class="link link-primary">
          Back to the flow
        </.link>
      </Core.alert>
    </div>
    """
  end

  # The trail, newest first, down a hairline: what and who on the line,
  # when under it. There is no catch-all clause.
  def render(%{page_state: state} = assigns)
      when state in [:broken_definition, :ready, :completed] do
    assigns = assign(assigns, :newest_first, Enum.reverse(assigns.events))

    ~H"""
    <div>
      <.page_header {header_assigns(assigns)}>
        <Status.last_event events={@events} />
      </.page_header>

      <ol id={"#{@id}-events"} class="relative ml-2 mt-6 border-l border-zinc-200 pl-6">
        <li :for={event <- @newest_first} class="relative pb-6 last:pb-0">
          <span class={[
            "absolute -left-[31px] top-1.5 size-2.5 rounded-full ring-4 ring-white",
            dot(Status.event_kind(event))
          ]} />
          <p class="text-sm">
            <span class="font-semibold">{Status.event_label(event)}</span>
            <span :if={event.user_id} class="text-zinc-500">by</span>
            <code :if={event.user_id} class="text-xs">{event.user_id}</code>
          </p>
          <p class="text-xs text-zinc-500" title={Status.absolute(event.inserted_at)}>
            {FormFlow.Web.Templates.Shared.relative(event.inserted_at)} · {Status.absolute(
              event.inserted_at
            )}
          </p>
        </li>
      </ol>
    </div>
    """
  end

  defp dot(:success), do: "bg-success"
  defp dot(:warning), do: "bg-warning"
  defp dot(:info), do: "bg-primary"
  defp dot(_neutral), do: "bg-zinc-300"

  # The header every clause but the first two draws: pinned, the form's
  # status after its name, the three views as tabs with History chosen. A
  # refused or invisible form draws it without tabs.
  attr(:base, :string, required: true)
  attr(:flow_instance, :map, required: true)
  attr(:flow_name, :string, required: true)
  attr(:label, :string, required: true)
  attr(:title, :string, default: nil)
  attr(:path, :list, required: true)
  attr(:form_instance, :map, default: nil)
  attr(:events, :list, default: [])
  attr(:components, :atom, default: nil)
  attr(:tabs, :boolean, default: true)
  slot(:inner_block)

  defp page_header(assigns) do
    ~H"""
    <Header.header
      base={@base}
      flow_instance={@flow_instance}
      flow_name={@flow_name}
      label={@label}
      title={@title}
      sticky
    >
      <:status>
        <Status.badge form_instance={@form_instance} events={@events} components={@components} />
      </:status>
      <:actions :if={@tabs}>
        <Tabs.tabs
          base={@base}
          flow_instance_id={@flow_instance.id}
          path={@path}
          active={:history}
          class="mr-2"
        />
        {render_slot(@inner_block)}
      </:actions>
    </Header.header>
    """
  end

  defp header_assigns(assigns) do
    %{
      base: assigns.base,
      flow_instance: assigns.flow_instance,
      flow_name: assigns.flow_name,
      label: assigns.form_label,
      title: assigns[:form] && assigns.form.label,
      path: assigns.path,
      form_instance: assigns[:form_instance],
      events: assigns[:events] || [],
      components: assigns.components
    }
  end
end
