defmodule FormFlow.Web.Templates.Flows.Health do
  @moduledoc """
  `FormFlow.Web.Templates.Flows.Health` LiveComponent is one root flow's
  health check, laid out at `/flows/:id/health`: the report
  `FormFlow.Data.Templates.Flows.Health.check/2` makes of the flow's whole
  tree, every entry with its explanation, and the switch to ignore one.

  The page **runs the check** — `Health.refresh/2`, which also writes the
  status the badges read (`FormFlow.Web.Templates.Components.Health`) — so
  a visit is what brings a lagging badge up to date, and a flow never
  checked gets its badge here. The header names the flow — the trail leads
  back to its show page — with Overview beside it; under it, what the report
  is of (the flow's kind, steps, subflows, forms, perspectives, and types —
  the report's `summary`), how it stands, and when it was checked.

  Then two panes. On the left, every entry as a row — a dot in its level's
  colour, grey once ignored, and where it is: the step named by the way
  down, or the flow itself — with how many checks passed under the list.
  On the right, the selected entry: its level, its message, why it matters,
  where it is and which check found it, what to do, an **Open** button that
  goes to the step (a form step's form page, a subflow's canvas, or the
  containing flow's editor for a Start or End node and for an entry with
  the flow itself), and the **Ignore** switch — the same control as the
  Show/Edit switch on the flow pages. Turning it on records the entry as
  ignored on the flow (`Health.ignore/3`) by `user_id`, the host's identity
  for the admin; off removes the record. An ignored entry stays listed,
  greyed, with who ignored it and when, and leaves the badge's count.

  The selection rides in the URL as `?entry=<code>@<path ids joined by />`,
  so a toggle keeps it and another page can link straight to one entry;
  without it, the first open entry is selected.

      <.live_component
        module={FormFlow.Web.Templates.Flows.Health}
        id="flows-health"
        flow_id={id}
        base={@base}
        user_id={@user_id}
        flow_types={@flow_types}
        form_types={@form_types}
        components={@components}
        params={@params}
      />

  Root flows only, as the overview is: `flow_id` naming an owned subflow
  reports its root.
  """

  use Phoenix.LiveComponent

  alias FormFlow.Data.Templates.Flows
  alias FormFlow.Data.Templates.Flows.Health
  alias FormFlow.Data.Templates.Flows.Health.Entry
  alias FormFlow.Web.Components.Core
  alias FormFlow.Web.Templates.Components.Header
  alias FormFlow.Web.Templates.Shared

  @impl true
  def mount(socket) do
    {:ok, assign(socket, error: nil)}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:base, fn -> "" end)
      |> assign_new(:user_id, fn -> nil end)
      |> assign_new(:flow_types, fn -> FormFlow.Config.Flows.Type.defaults() end)
      |> assign_new(:form_types, fn -> FormFlow.Config.Forms.Type.defaults() end)
      |> assign_new(:components, fn -> nil end)
      |> assign_new(:params, fn -> %{} end)

    # Once per visit: a patch that changes the selection re-renders the
    # component with the report it already has; a patch to another flow's
    # page does not
    socket =
      if socket.assigns[:checked_for] == socket.assigns.flow_id,
        do: socket,
        else: refresh(socket)

    {:ok, select(socket, socket.assigns.params["entry"])}
  end

  # The check, written back as the cached status, and the root it was of
  defp refresh(socket) do
    health = Health.refresh(socket.assigns.flow_id, check_options(socket.assigns))

    assign(socket,
      health: health,
      flow: health && Flows.get(health.flow_id),
      checked_for: socket.assigns.flow_id
    )
  end

  defp check_options(assigns) do
    [flow_types: assigns.flow_types, form_types: assigns.form_types]
  end

  @impl true
  def handle_event("select", %{"entry" => key}, socket) do
    {:noreply,
     push_patch(socket,
       to: "#{socket.assigns.base}/flows/#{socket.assigns.flow.id}/health?entry=#{key}"
     )}
  end

  def handle_event("toggle_ignore", %{"entry" => key}, socket) do
    health = socket.assigns.health

    written =
      case find_entry(health, key) do
        %Entry{ignored: nil} = entry -> Health.ignore(health, entry, socket.assigns.user_id)
        %Entry{} = entry -> Health.stop_ignoring(health, entry)
        nil -> {:error, :not_found}
      end

    error =
      case written do
        {:ok, _root} ->
          nil

        {:error, :not_found} ->
          "That entry could not be saved — the flow may have changed. The report below is current."
      end

    # The toggle wrote the status from the report it held; reading the flow
    # again picks up the marks, and the report as it stands now — or that
    # the flow is gone
    health = Health.check(socket.assigns.flow.id, check_options(socket.assigns))

    {:noreply,
     socket
     |> assign(health: health, flow: health && Flows.get(health.flow_id), error: error)
     |> select(key)}
  end

  # The entry the URL names, else the first open one, else the first
  defp select(%{assigns: %{health: nil}} = socket, _key), do: socket

  defp select(socket, key) do
    health = socket.assigns.health

    selected =
      (key && find_entry(health, key)) ||
        List.first(Health.open(health)) ||
        List.first(health.entries)

    assign(socket,
      selected: selected,
      open_target: selected && open_target(selected, socket.assigns)
    )
  end

  # `code@id/id` — the pair that identifies an entry, as one URL-safe word
  defp key(%Entry{code: code, path: path}), do: "#{code}@#{Enum.join(path, "/")}"

  defp find_entry(%Health{entries: entries}, key), do: Enum.find(entries, &(key(&1) == key))

  # Where Open goes, and what it is called: the step the entry is about —
  # a form step's form page, a subflow step's canvas — or, for a Start or
  # End node, a step whose entity is missing, and an entry with a flow
  # itself, the editor of the flow the entry sits in, where it is wired.
  defp open_target(%Entry{} = entry, assigns) do
    base = "#{assigns.base}/flows/#{assigns.flow.id}"
    node_id = entry.node_id || List.last(entry.path)
    node = node_id && Flows.get_node(node_id)

    %{
      to: open_path(entry, node, base),
      label: (node && node_label(node)) || assigns.flow.name || "Untitled"
    }
  end

  # An entry with a flow itself: that flow's editor
  defp open_path(%Entry{node_id: nil, path: path}, _node, base), do: edit_path(base, path)

  # A step whose entity is missing has no page of its own: the editor it sits on
  defp open_path(%Entry{code: code, path: path}, _node, base)
       when code in [:form_missing, :subflow_missing],
       do: edit_path(base, Enum.drop(path, -1))

  defp open_path(_entry, %{subflow_id: id} = node, base) when is_binary(id),
    do: "#{base}/nodes/#{node.id}"

  defp open_path(_entry, %{form_id: id} = node, base) when is_binary(id),
    do: "#{base}/nodes/#{node.id}/form"

  # Start, End, or a node since deleted: the editor it sits on
  defp open_path(%Entry{path: path}, _node, base), do: edit_path(base, Enum.drop(path, -1))

  # The editor of the flow at `path` — the root's, or the drill-in editor
  # addressed by the node embedding it
  defp edit_path(base, []), do: "#{base}/edit"
  defp edit_path(base, path), do: "#{base}/nodes/#{List.last(path)}/edit"

  defp node_label(node), do: get_in(node.properties, ["data", "label"]) || List.first(node.labels)

  @impl true
  def render(%{health: nil} = assigns) do
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
      <%!-- The flow as the root, so the title reads "Flow · Health check"
            and the trail walks Flows / Flow (its show page) / Health --%>
      <Header.header
        base={@base}
        section="flows"
        root={@flow}
        name="Health check"
        components={@components}
      >
        <:crumb>Health</:crumb>
        <:actions>
          <Core.button
            components={@components}
            navigate={"#{@base}/flows/#{@flow.id}/overview"}
            class="btn"
          >
            Flow Overview
          </Core.button>
        </:actions>
      </Header.header>

      <Core.error :if={@error} components={@components}>{@error}</Core.error>

      <%!-- When, and what the report is of --%>
      <dl class="mb-4 grid grid-cols-2 gap-x-8 gap-y-4 text-sm sm:grid-cols-4 lg:grid-cols-7">
        <.fact :if={checked_at(@flow)} label="Checked">
          <span id={"#{@id}-checked"}>
            {relative(checked_at(@flow))}
            <span class="block text-xs font-normal text-zinc-500">
              {Calendar.strftime(checked_at(@flow), "%Y-%m-%d %H:%M UTC")}
            </span>
          </span>
        </.fact>
        <.fact label="Kind">
          {if @health.summary.label == "subflows", do: "Complex flow", else: "Simple flow"}
        </.fact>
        <.fact label="Steps">{@health.summary.steps}</.fact>
        <.fact label="Subflows">{@health.summary.subflows}</.fact>
        <.fact label="Forms">{@health.summary.forms}</.fact>
        <.fact label="Perspectives">{perspective_names(@health, @flow_types)}</.fact>
        <.fact label="Flow types">{flow_type_names(@health, @flow_types)}</.fact>
      </dl>

      <%!-- How it stands: the open entries by level, the ignored ones, and
            how many checks found nothing — each a dot in the list's colours,
            grey when there are none --%>
      <p id={"#{@id}-standing"} class="mb-6 flex flex-wrap items-center gap-x-4 gap-y-1 text-sm">
        <.count dot={dot(:error)} count={@health.counts.error} noun="error" />
        <.count dot={dot(:warning)} count={@health.counts.warning} noun="warning" />
        <.count dot={dot(:info)} count={@health.counts.info} noun="info" />
        <.count dot="bg-zinc-400" count={@health.counts.ignored} noun="ignored" />
        <.count dot="bg-success" count={Health.passing(@health)} noun="check" verb="passing" />
      </p>

      <Core.alert :if={@health.entries == []} components={@components} kind={:success}>
        Nothing to report — every check passed.
      </Core.alert>

      <div
        :if={@health.entries != []}
        class="grid overflow-hidden rounded-lg border border-zinc-200 bg-white md:grid-cols-[1fr_2fr]"
      >
        <%!-- Every entry, in the report's order, the selected one marked --%>
        <ul id={"#{@id}-entries"} class="divide-y divide-zinc-100 border-zinc-200 md:border-r">
          <li :for={entry <- @health.entries}>
            <button
              type="button"
              phx-click="select"
              phx-value-entry={key(entry)}
              phx-target={@myself}
              aria-current={to_string(entry == @selected)}
              class={[
                "flex w-full items-center gap-3 px-5 py-3 text-left text-sm hover:bg-zinc-50",
                entry == @selected && "bg-zinc-100",
                entry.ignored && "text-zinc-400"
              ]}
            >
              <span class={[
                "size-2.5 shrink-0 rounded-full",
                if(entry.ignored, do: "bg-zinc-300", else: dot(entry.level))
              ]} />
              <span class="min-w-0 flex-1">
                <span class="block truncate">{where(entry, @flow)}</span>
                <span class="block truncate text-xs text-zinc-400">{check_name(entry.code)}</span>
              </span>
              <span :if={entry == @selected} class="text-zinc-500" aria-hidden="true">›</span>
            </button>
          </li>
          <li class="px-5 py-3 text-xs text-zinc-400">
            {plural(Health.passing(@health), "check")} passing
          </li>
        </ul>

        <%!-- The selected entry --%>
        <div :if={@selected} id={"#{@id}-detail"} class="space-y-5 p-6">
          <div>
            <%!-- Solid, not Core.badge's badge-soft: the level is the one
                  thing on the pane that must read at a glance --%>
            <div class="flex flex-wrap items-center gap-2">
              <span class={["badge badge-sm", level_badge(@selected.level)]}>{@selected.level}</span>
              <span :if={@selected.ignored} class="badge badge-sm badge-neutral">ignored</span>
            </div>
            <h3 class={["mt-2 text-base font-semibold text-zinc-900", @selected.ignored && "line-through text-zinc-500"]}>
              {@selected.message}
            </h3>
            <p class="mt-1 text-sm text-zinc-600">{@selected.explanation}</p>
          </div>

          <dl class="grid grid-cols-2 gap-3 text-sm">
            <.fact label="Where">{where(@selected, @flow)}</.fact>
            <.fact label="Check"><code class="text-xs">{@selected.code}</code></.fact>
          </dl>

          <div class="rounded-lg bg-zinc-50 p-3 text-sm text-zinc-700">
            <span class="font-medium">To fix:</span> {@selected.fix}
          </div>

          <div class="flex flex-wrap items-center justify-between gap-4">
            <Core.button
              components={@components}
              navigate={@open_target.to}
              class="btn btn-sm btn-neutral"
            >
              Open {@open_target.label}
            </Core.button>
            <%!-- The Show/Edit switch, as a switch for ignoring: a styled
                  button rather than a checkbox, so its state is always the
                  server's --%>
            <div class="text-right">
              <button
                id={"#{@id}-ignore"}
                type="button"
                role="switch"
                aria-checked={to_string(@selected.ignored != nil)}
                aria-label={if @selected.ignored, do: "Stop ignoring", else: "Ignore"}
                phx-click="toggle_ignore"
                phx-value-entry={key(@selected)}
                phx-target={@myself}
                class="inline-flex shrink-0 items-center gap-2 text-sm"
              >
                <span class={[
                  "relative inline-flex h-6 w-11 shrink-0 items-center rounded-full transition-colors",
                  if(@selected.ignored, do: "bg-cyan-600", else: "bg-zinc-300")
                ]}>
                  <span class={[
                    "inline-block h-5 w-5 rounded-full bg-white shadow transition-transform",
                    if(@selected.ignored, do: "translate-x-5", else: "translate-x-0.5")
                  ]} />
                </span>
                <span class={
                  if(@selected.ignored, do: "font-semibold text-zinc-900", else: "text-zinc-500")
                }>
                  {if @selected.ignored, do: "Ignored", else: "Ignore"}
                </span>
              </button>
              <p :if={@selected.ignored} class="mt-1 text-xs italic text-zinc-500">
                {ignored_by(@selected.ignored)}
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr(:label, :string, required: true)
  slot(:inner_block, required: true)

  defp fact(assigns) do
    ~H"""
    <div>
      <dt class="text-xs text-zinc-500">{@label}</dt>
      <dd class="mt-0.5 font-medium text-zinc-900">{render_slot(@inner_block)}</dd>
    </div>
    """
  end

  attr(:dot, :string, required: true, doc: "the dot's colour class, when there are any")
  attr(:count, :integer, required: true)
  attr(:noun, :string, required: true)
  attr(:verb, :string, default: nil, doc: ~s(follows the noun — "3 checks passing"))

  # "2 errors" beside a dot in the level's colour; grey and muted when none.
  # "info" and "ignored" do not take an s.
  defp count(assigns) do
    ~H"""
    <span class={["inline-flex items-center gap-1.5", @count == 0 && "text-zinc-400"]}>
      <span class={["size-2 shrink-0 rounded-full", if(@count > 0, do: @dot, else: "bg-zinc-200")]} />
      <span><span class="font-semibold tabular-nums">{@count}</span> {noun(@count, @noun)}{@verb && " #{@verb}"}</span>
    </span>
    """
  end

  defp noun(_count, noun) when noun in ["info", "ignored"], do: noun
  defp noun(1, noun), do: noun
  defp noun(_count, noun), do: "#{noun}s"

  # Where the entry is: the step by the way down, or the flow itself
  defp where(%Entry{subject: nil}, flow), do: flow.name || "Untitled"
  defp where(%Entry{subject: subject}, _flow), do: subject

  # The code as words, for the list's second line
  defp check_name(code), do: code |> Atom.to_string() |> String.replace("_", " ")

  defp checked_at(flow) do
    case Health.status(flow) do
      %{checked_at: %DateTime{} = at} -> at
      _none -> nil
    end
  end

  # "just now", "3 minutes ago", "2 hours ago", "5 days ago" — as of the
  # render; the page does not tick
  defp relative(%DateTime{} = at) do
    seconds = DateTime.diff(DateTime.utc_now(), at)

    cond do
      seconds < 60 -> "just now"
      seconds < 3_600 -> "#{plural(div(seconds, 60), "minute")} ago"
      seconds < 86_400 -> "#{plural(div(seconds, 3_600), "hour")} ago"
      true -> "#{plural(div(seconds, 86_400), "day")} ago"
    end
  end

  defp plural(1, noun), do: "1 #{noun}"
  defp plural(count, noun), do: "#{count} #{noun}s"

  # Solid badges, one colour per level
  defp level_badge(:error), do: "badge-error"
  defp level_badge(:warning), do: "badge-warning"
  defp level_badge(:info), do: "badge-info"

  defp dot(:error), do: "bg-error"
  defp dot(:warning), do: "bg-warning"
  defp dot(:info), do: "bg-info"

  # Names for the ids the summary holds, through the host's types; an id no
  # type declares is shown as it is
  defp perspective_names(%Health{summary: %{perspectives: []}}, _flow_types), do: "Everyone"

  defp perspective_names(%Health{summary: %{perspectives: ids}}, flow_types) do
    declared = Shared.all_perspectives(flow_types)

    Enum.map_join(ids, ", ", fn id ->
      case Enum.find(declared, &(&1.id == id)) do
        nil -> id
        perspective -> perspective.name
      end
    end)
  end

  defp flow_type_names(%Health{summary: %{form_flow_types: []}}, _flow_types), do: "—"

  defp flow_type_names(%Health{summary: %{form_flow_types: ids}}, flow_types) do
    ids
    |> Enum.map(&Shared.effective_type(flow_types, &1))
    |> Enum.uniq()
    |> Enum.map_join(", ", fn id ->
      case Shared.type(flow_types, id) do
        nil -> id || "Default"
        type -> type.name
      end
    end)
  end

  # "Ignored by demo-admin on 2026-09-08" — with what the record has
  defp ignored_by(%{user_id: user_id, ignored_at: at}) do
    ["Ignored", user_id && "by #{user_id}", at && "on #{Calendar.strftime(at, "%Y-%m-%d")}"]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end
end
