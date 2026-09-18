defmodule FormFlow.Web.Instances.Components.Forms.Status do
  @moduledoc """
  `FormFlow.Web.Instances.Components.Forms.Status` says where one form
  instance stands, in the words the form pages use: the **status badge**
  after the page's title - Draft, Submitted, Reopened - and the **activity**
  button among the header's actions, an **i** the header's lines open on
  hover or focus - "Started by dog_owner", and under it "3 minutes ago
  2026-09-18 02:47 UTC" - with the labels the History page gives every
  event.

  The status is derived, not stored. A form instance's row holds two
  statuses, `in_progress` and `completed`; the third word comes from the
  event trail (`FormFlow.Data.Instances.Forms.list_events/2`): an
  `in_progress` form with a `reopened` event since its last submission is
  Reopened rather than Draft, because the person looking at it - the
  applicant sent back to it, or the reviewer who sent them - needs the
  difference more than they need the row's word.

  The event line names the newest event by what it did - Started,
  Submitted, Reopened, Moved to a new version - when, and by whom. Saving a
  draft is deliberately not among them: a draft is the user keeping their
  place, not something that happened to the form, so it writes no event and
  the card carries "Draft saved" as a line of its own under the event
  (`archive/plans/instance-form-drafts.md` §9).

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

  attr(:id, :string, required: true)
  attr(:form_instance, :map, default: nil, doc: "the `FormFlow.Data.Instances.Form`, or nil")
  attr(:events, :list, default: [], doc: "its events, oldest first")
  attr(:draft, :map, default: nil, doc: "the user's saved draft, or nil")
  attr(:components, :atom, default: nil)
  attr(:class, :any, default: nil)

  @doc """
  The status badge, and behind it where the form stands: the newest event,
  and the saved draft under it, one line each, in a card that opens on
  hover and on focus. The event comes first because it is the form's own
  history; the draft is the user's own work on top of it.

  The two are one thing on the page because they are one thing to a reader:
  "Draft" is the word, and when it became that word and who made it so is
  the same question asked further. So the badge carries an **i** after its
  word, and the whole badge is the button - tapping it focuses it, so a
  touch screen opens the same card a pointer does.

  The lines are written out only in the card. Spelled across the header
  they crowd the actions the page is for - Submit is what the header is
  there to offer - while the question they answer ("is my work safe?",
  "what happened last?") is asked once, not read continuously.

  Draws nothing for a position with no instance: an unstarted form has no
  status to show. A form with a status but no activity yet - no event, no
  draft - is the plain badge, with no **i** and nothing to open.
  """
  def badge(assigns) do
    assigns =
      assigns
      |> assign(:status, status(assigns.form_instance, assigns.events))
      |> assign(:event, List.last(assigns.events))

    ~H"""
    <%= if @status do %>
      <% {text, kind} = label(@status) %>
      <span :if={!@event && !@draft} class="inline-flex">
        <Core.badge components={@components} kind={kind} class={@class}>{text}</Core.badge>
      </span>
      <span :if={@event || @draft} class="group relative inline-flex">
        <button
          type="button"
          id={@id}
          aria-label={"#{text} - when, and by whom"}
          class="inline-flex cursor-default items-center focus:outline-none"
        >
          <Core.badge components={@components} kind={kind} class={@class}>
            {text}
            <Core.icon
              components={@components}
              name="hero-information-circle"
              class="size-3.5 opacity-60"
            />
          </Core.badge>
        </button>
        <span
          role="tooltip"
          class="pointer-events-none invisible absolute top-full left-0 z-30 mt-1 w-max rounded-xl border border-zinc-200 bg-white px-5 py-4 font-normal whitespace-nowrap opacity-0 shadow-lg transition group-hover:visible group-hover:opacity-100 group-focus-within:visible group-focus-within:opacity-100"
        >
          <.line
            :if={@event}
            what={event_label(@event)}
            at={@event.inserted_at}
            user_id={@event.user_id}
          />
          <.line
            :if={@draft}
            what="Draft saved"
            at={@draft.saved_at}
            user_id={@draft.user_id}
            class={@event && "mt-3"}
          />
        </span>
      </span>
    <% end %>
    """
  end

  attr(:what, :string, required: true, doc: ~s|what happened - "Started", "Draft saved"|)
  attr(:at, :any, default: nil, doc: "when it happened, or nil")
  attr(:user_id, :string, default: nil, doc: "who did it, or nil")
  attr(:class, :any, default: nil)

  # One entry of the card, over two lines - "Draft saved by dog_owner", and
  # under it, smaller, "11 hours ago 2026-09-17 21:04 UTC". What happened and
  # who did it is the sentence a reader scans; when it happened is the answer
  # they look up, so it sits on its own line rather than running the first one
  # long. Both times are written - the relative one answers how long ago at a
  # glance, the full one answers exactly when, and a card that opens on hover
  # has no second hover to hide the second answer behind. The full one is
  # lighter rather than bracketed: the weight does the work brackets were
  # doing, without the punctuation. The user is a name in the sentence, not a
  # code span: it reads as who, not as a value to copy.
  defp line(assigns) do
    ~H"""
    <span class={["block text-sm text-zinc-600", @class]}>
      <span class="block">{@what}<span :if={@user_id}> by {@user_id}</span></span>
      <span :if={@at} class="flex items-baseline gap-1.5 text-xs text-zinc-500">
        {FormFlow.Web.Templates.Shared.relative(@at)}
        <span class="text-zinc-400">{absolute(@at)}</span>
      </span>
    </span>
    """
  end

  @doc "A moment written out in full, as the pages write timestamps."
  def absolute(%DateTime{} = at), do: Calendar.strftime(at, "%Y-%m-%d %H:%M") <> " UTC"
end
