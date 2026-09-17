defmodule FormFlow.Web.Instances.Flows.History do
  @moduledoc """
  `FormFlow.Web.Instances.Flows.History` LiveComponent lists what has
  happened in one flow instance, newest first, at `/:id/history`: the
  instance started and completed, and every form in it started, submitted,
  reopened, moved to a new version - each line naming the form it happened
  to, who did it, and when.

  It is the second view of the flow instance beside
  `FormFlow.Web.Instances.Flows.Show`, and the header offers the two as
  tabs, Overview | History (`FormFlow.Web.Instances.Components.Flows.Tabs`),
  with the viewer's standing after the flow's name as the Overview has it.
  It loads what the Overview loads (`FormFlow.Web.Instances.Flows.Shared`),
  asks the host's `on_mount` the same way, and changes nothing: the trail
  is audit, not state, and this page only reads it.

  The trail is every form instance's events and the instance's own, merged
  (`FormFlow.Data.Instances.Flows.list_events/1`). A form's line names the
  form as the flow names it now; an event on a form instance at a position
  the flow no longer has says so instead. A reopen records who and when,
  not why - there is no note from a reviewer to quote under it yet
  (`archive/plans/instances-refresh.md` §7).

  ## The states it draws

  `FormFlow.Web.Instances.Shared.page_state/1`'s four, each in its own
  `render/1` clause and with no catch-all:

    * `:flow_not_found` - "This flow no longer exists."
    * `:redirecting` - nothing, while the host's `on_mount` navigates away
    * `:refused` - the host's message alone
    * `:ready` - the trail
  """

  use Phoenix.LiveComponent

  alias FormFlow.Data.Instances
  alias FormFlow.Data.Instances.FlowProgress
  alias FormFlow.Web.Components.Core
  alias FormFlow.Web.Instances.Components.Flows.Status
  alias FormFlow.Web.Instances.Components.Flows.Tabs
  alias FormFlow.Web.Instances.Components.Forms.Status, as: FormStatus
  alias FormFlow.Web.Instances.Components.Header
  alias FormFlow.Web.Instances.Flows.Shared
  alias FormFlow.Web.Instances.Paths

  @impl true
  def update(assigns, socket) do
    socket = socket |> assign(assigns) |> Shared.defaults() |> Shared.load()

    {:ok, assign(socket, :page_state, FormFlow.Web.Instances.Shared.page_state(socket.assigns))}
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
      <Header.header base={@base} flow_instance={@flow_instance} flow_name={@flow_name} />

      <Core.alert components={@components}>
        <span>{@mount_error}</span>
        <.link navigate={Paths.flows_path(@base)} class="link link-primary">
          Back to flows
        </.link>
      </Core.alert>
    </div>
    """
  end

  # The trail, newest first, down a hairline: what and to which form on the
  # line, who after it, when under it. There is no catch-all clause.
  def render(%{page_state: :ready} = assigns) do
    assigns = assign(assigns, :newest_first, Enum.reverse(assigns.trail))

    ~H"""
    <div>
      <Header.header base={@base} flow_instance={@flow_instance} flow_name={@flow_name}>
        <:status>
          <Status.badge standing={@standing} components={@components} />
        </:status>
        <:actions>
          <Tabs.tabs base={@base} flow_instance_id={@flow_instance.id} active={:history} />
        </:actions>
      </Header.header>

      <ol id={"#{@id}-events"} class="relative ml-2 mt-6 border-l border-zinc-200 pl-6">
        <li :for={entry <- @newest_first} class="relative pb-6 last:pb-0">
          <span class={[
            "absolute -left-[31px] top-1.5 size-2.5 rounded-full ring-4 ring-white",
            dot(kind(entry))
          ]} />
          <p class="text-sm">
            <span class="font-semibold">{label(entry)}</span>
            <span class="text-zinc-700">· {subject(entry, @forms, @flow_name)}</span>
            <span :if={entry.event.user_id} class="text-zinc-500">by</span>
            <code :if={entry.event.user_id} class="text-xs">{entry.event.user_id}</code>
          </p>
          <p class="text-xs text-zinc-500" title={FormStatus.absolute(entry.event.inserted_at)}>
            {FormFlow.Web.Templates.Shared.relative(entry.event.inserted_at)} · {FormStatus.absolute(
              entry.event.inserted_at
            )}
          </p>
        </li>
      </ol>
    </div>
    """
  end

  # A form's event is labelled as its own History page labels it; the
  # instance's own events in the same voice
  defp label(%{form_instance: nil, event: %Instances.Flow.Event{event: "created"}}), do: "Started"

  defp label(%{form_instance: nil, event: %Instances.Flow.Event{event: "status_changed"}}),
    do: "Completed"

  defp label(%{form_instance: nil, event: %Instances.Flow.Event{event: "reconciled"}}),
    do: "Reconciled"

  defp label(%{event: %Instances.Form.Event{} = event}), do: FormStatus.event_label(event)

  defp kind(%{form_instance: nil, event: %Instances.Flow.Event{event: "status_changed"}}),
    do: :success

  defp kind(%{form_instance: nil, event: %Instances.Flow.Event{event: "created"}}), do: :info
  defp kind(%{form_instance: nil}), do: :neutral
  defp kind(%{event: %Instances.Form.Event{} = event}), do: FormStatus.event_kind(event)

  # What the event happened to: the flow itself, or the form at the
  # instance's position as the flow names it now - or, at a position the
  # flow no longer has, said so
  defp subject(%{form_instance: nil}, _forms, flow_name), do: flow_name

  defp subject(%{form_instance: %{path: path}}, forms, _flow_name) do
    case Enum.find(forms, &(&1.path == path)) do
      nil -> "a form this flow no longer has"
      form -> FlowProgress.qualified_label(form)
    end
  end

  defp dot(:success), do: "bg-success"
  defp dot(:warning), do: "bg-warning"
  defp dot(:info), do: "bg-primary"
  defp dot(_neutral), do: "bg-zinc-300"
end
