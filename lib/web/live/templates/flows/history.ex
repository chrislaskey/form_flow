defmodule FormFlow.Web.Templates.Flows.History do
  @moduledoc """
  `FormFlow.Web.Templates.Flows.History` LiveComponent lists what has
  happened to a root flow, newest first, at `/flows/:id/history`: its
  append-only log (`FormFlow.Data.Templates.Flow.Event`), one line per
  event — what happened, who did it, when.

  `created` reads "Created"; `status_changed` reads as the two statuses
  with an arrow between them ("Draft → Open"), in the words the status
  badge uses (`FormFlow.Web.Templates.Shared.status_label/1`);
  `health_ignored` and `health_unignored` name the health check and where
  it was ("Ignored health check: form not published at Intake"), in the
  words the health page lists it (`FormFlow.Web.Templates.Shared.check_name/1`);
  `pre_release_instances_deleted` says how many.
  The author is the host's `user_id` as it was given — an opaque identity
  FormFlow does not resolve to a name, the way the health page's "Ignored
  by" shows it — and an event with none says so. The time is relative
  ("3 hours ago") with the absolute on hover, as the health page's
  "Checked" is.

  Roots only: an owned subflow's history is its root's, as its health is,
  so an owned flow's id lands on the root's page. Nothing on the page
  decides anything — the log is audit, not state (`Flow.Event`), and this
  page only reads it. Reached from the flows index's ⋮ menu and the show
  page; a lesser page than Overview and Health, here for auditing, and the
  place other historical data about a flow would go.
  """

  use Phoenix.LiveComponent

  alias FormFlow.Data.Templates.Flow
  alias FormFlow.Data.Templates.Flows
  alias FormFlow.Web.Components.Core
  alias FormFlow.Web.Templates.Components.Header
  alias FormFlow.Web.Templates.Components.Health
  alias FormFlow.Web.Templates.Shared

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:base, fn -> "" end)
      |> assign_new(:components, fn -> nil end)

    flow = root_of(Flows.get(socket.assigns.flow_id))

    {:ok, assign(socket, flow: flow, events: (flow && Flows.list_events(flow)) || [])}
  end

  # An owned subflow's history is its root's
  defp root_of(%Flow{owner_flow_id: nil} = flow), do: flow
  defp root_of(%Flow{owner_flow_id: root_id}), do: Flows.get(root_id)
  defp root_of(nil), do: nil

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
      <Header.header
        base={@base}
        section="flows"
        root={@flow}
        name="History"
        components={@components}
      >
        <:metadata>What has happened to this flow, newest first</:metadata>
        <:crumb>History</:crumb>
        <:actions>
          <Health.health base={@base} flow={@flow} components={@components} />
          <Core.button components={@components} navigate={"#{@base}/flows/#{@flow.id}"} class="btn">
            Show
          </Core.button>
          <Core.button
            components={@components}
            navigate={"#{@base}/flows/#{@flow.id}/edit"}
            class="btn"
          >
            Edit
          </Core.button>
        </:actions>
      </Header.header>

      <Core.alert :if={@events == []} components={@components}>
        Nothing has been recorded for this flow.
      </Core.alert>

      <ol
        :if={@events != []}
        id={"#{@id}-events"}
        class="divide-y divide-zinc-200 rounded-md border border-zinc-200 bg-white"
      >
        <li :for={event <- @events} class="flex flex-wrap items-baseline gap-x-3 gap-y-1 px-4 py-3 text-sm">
          <span class="font-medium text-zinc-900">{describe(event)}</span>
          <span class="text-zinc-500">{author(event)}</span>
          <span class="ml-auto text-xs text-zinc-500" title={Calendar.strftime(event.inserted_at, "%Y-%m-%d %H:%M:%S UTC")}>
            {Shared.relative(event.inserted_at)}
          </span>
        </li>
      </ol>
    </div>
    """
  end

  # One line per kind: what happened, in the words the pages already use.
  # A kind this page does not know yet reads as its name, so a new event
  # never breaks the list.
  defp describe(%{event: "created"}), do: "Created"

  defp describe(%{event: "status_changed", snapshot: %{"from" => from, "to" => to}}),
    do: "#{Shared.status_label(from)} → #{Shared.status_label(to)}"

  defp describe(%{event: "health_ignored", snapshot: snapshot}),
    do: "Ignored health check: #{health_entry(snapshot)}"

  defp describe(%{event: "health_unignored", snapshot: snapshot}),
    do: "Stopped ignoring health check: #{health_entry(snapshot)}"

  defp describe(%{event: "pre_release_instances_deleted", snapshot: %{"count" => count}}),
    do: "Deleted #{Shared.count(count, "instance")} started during pre-release"

  defp describe(%{event: event}), do: event |> String.replace("_", " ") |> String.capitalize()

  # The check's code and where it was, the way the health page lists an entry
  defp health_entry(%{"code" => code, "subject" => subject}) when is_binary(subject),
    do: "#{Shared.check_name(code)} at #{subject}"

  defp health_entry(%{"code" => code}), do: Shared.check_name(code)
  defp health_entry(_snapshot), do: "unknown"

  defp author(%{user_id: nil}), do: "by nobody recorded"
  defp author(%{user_id: user_id}), do: "by #{user_id}"
end
