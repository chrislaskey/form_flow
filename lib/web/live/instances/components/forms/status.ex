defmodule FormFlow.Web.Instances.Components.Forms.Status do
  @moduledoc """
  `FormFlow.Web.Instances.Components.Forms.Status` says where one form
  instance stands, in the words the form pages use: the **status badge**
  after the page's title - Draft, Submitted, Reopened - and the **last
  event** line among the header's actions - "Started 3 minutes ago ·
  dog_owner" - with the labels the History page gives every event.

  The status is derived, not stored. A form instance's row holds two
  statuses, `in_progress` and `completed`; the third word comes from the
  event trail (`FormFlow.Data.Instances.Forms.list_events/2`): an
  `in_progress` form with a `reopened` event since its last submission is
  Reopened rather than Draft, because the person looking at it - the
  applicant sent back to it, or the reviewer who sent them - needs the
  difference more than they need the row's word.

  The last event line names the newest event by what it did - Started,
  Submitted, Reopened, Moved to a new version - when, and by whom. There is
  no "Saved" here yet: the pages write answers only on submit, so the
  newest thing that happened is always one of those four. When saving a
  draft exists it will be a fifth (`archive/plans/instances-refresh.md` §7).

  Pure functions first (`status/2`, `event_label/1`) so the rules are
  tested without a socket; then the two components that draw them.
  """

  use Phoenix.Component

  alias FormFlow.Data.Instances
  alias FormFlow.Data.Instances.Form.Event
  alias FormFlow.Web.Components.Core

  @type status :: :draft | :submitted | :reopened

  @doc """
  The form instance's status as one of three words, from its row and its
  events oldest first: `:submitted` for a completed form; `:reopened` for
  one in progress whose trail has a `reopened` event after its last
  `status_changed`; `:draft` otherwise. `nil` for a position with no
  instance yet.
  """
  @spec status(Instances.Form.t() | nil, [Event.t()]) :: status() | nil
  def status(nil, _events), do: nil
  def status(%Instances.Form{status: "completed"}, _events), do: :submitted

  def status(%Instances.Form{}, events) do
    since_submission =
      events
      |> Enum.reverse()
      |> Enum.take_while(&(&1.event != "status_changed"))

    if Enum.any?(since_submission, &(&1.event == "reopened")), do: :reopened, else: :draft
  end

  @doc "A status as `{text, kind}` - the word and the `Core.badge/1` palette."
  @spec label(status()) :: {String.t(), atom()}
  def label(:draft), do: {"Draft", :info}
  def label(:submitted), do: {"Submitted", :success}
  def label(:reopened), do: {"Reopened", :warning}

  @doc """
  What an event did, as the pages say it: the verb for the person reading
  the trail rather than the row's `event` value.
  """
  @spec event_label(Event.t()) :: String.t()
  def event_label(%Event{event: "created"}), do: "Started"
  def event_label(%Event{event: "status_changed"}), do: "Submitted"
  def event_label(%Event{event: "reopened"}), do: "Reopened"
  def event_label(%Event{event: "migrated"}), do: "Moved to a new version"

  @doc "The `Core.badge/1` palette of an event, as the History page's dots."
  @spec event_kind(Event.t()) :: atom()
  def event_kind(%Event{event: "status_changed"}), do: :success
  def event_kind(%Event{event: "reopened"}), do: :warning
  def event_kind(%Event{event: "created"}), do: :info
  def event_kind(%Event{event: "migrated"}), do: :neutral

  attr(:form_instance, :map, default: nil, doc: "the `FormFlow.Data.Instances.Form`, or nil")
  attr(:events, :list, default: [], doc: "its events, oldest first")
  attr(:components, :atom, default: nil)
  attr(:class, :any, default: nil)

  @doc """
  The status badge. Draws nothing for a position with no instance: an
  unstarted form has no status to show.
  """
  def badge(assigns) do
    assigns = assign(assigns, :status, status(assigns.form_instance, assigns.events))

    ~H"""
    <%= if @status do %>
      <% {text, kind} = label(@status) %>
      <Core.badge components={@components} kind={kind} class={@class}>{text}</Core.badge>
    <% end %>
    """
  end

  attr(:events, :list, required: true, doc: "the form instance's events, oldest first")
  attr(:class, :any, default: nil)

  @doc """
  The newest event as one line - "Started 3 minutes ago · dog_owner" - the
  absolute time on hover. Nothing for an empty trail.
  """
  def last_event(assigns) do
    assigns = assign(assigns, :event, List.last(assigns.events))

    ~H"""
    <span :if={@event} class={["flex items-center gap-2 text-sm text-zinc-600", @class]}>
      <span class="size-2 shrink-0 rounded-full bg-zinc-400" />
      <span>
        {event_label(@event)}
        <span class="text-zinc-500" title={absolute(@event.inserted_at)}>
          {FormFlow.Web.Templates.Shared.relative(@event.inserted_at)}
        </span>
        <span :if={@event.user_id} class="text-zinc-500">
          · <code class="text-xs">{@event.user_id}</code>
        </span>
      </span>
    </span>
    """
  end

  @doc "A moment written out in full, as the pages write timestamps."
  def absolute(%DateTime{} = at), do: Calendar.strftime(at, "%Y-%m-%d %H:%M") <> " UTC"
end
