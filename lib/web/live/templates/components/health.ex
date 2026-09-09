defmodule FormFlow.Web.Templates.Components.Health do
  @moduledoc """
  `FormFlow.Web.Templates.Components.Health` LiveComponent shows one root
  flow's health (`FormFlow.Data.Templates.Flows.Health`): an icon button
  with a count on its shoulder — a green check when nothing is open,
  otherwise the count of open entries in the colour of the worst — and,
  when clicked, a modal with the whole report. The heart is drawn inline,
  so a host needs no icon set for it.

  The modal reads top to bottom: what the report is of (the flow's kind,
  its steps, subflows, forms, perspectives, and types — the report's
  `summary`), how it stands (open entries by level, and how many are
  ignored), then every entry with a switch beside it. The switch is
  **Ignore** — the same control as the Show/Edit switch on the flow pages —
  and turning it on records the entry as ignored on the flow
  (`Health.ignore/3`) by `user_id`, the host's identity for the admin;
  turning it off removes the record. An ignored entry stays listed, greyed,
  with who ignored it and when, and leaves the badge's count.

      <.live_component
        module={FormFlow.Web.Templates.Components.Health}
        id={"flow-health-\#{flow.id}"}
        flow_id={flow.id}
        user_id={@user_id}
        flow_types={@flow_types}
        form_types={@form_types}
        components={@components}
      />

  The check runs when the component updates — every time its parent
  renders it — over the flow's whole tree. The flows index renders one per
  row, so a page of ten flows loads ten trees; that is the cost of
  answering on the index, where an admin looks for what is left to do. A
  toggle in the modal runs the check again, so the list and the badge are
  always what the flow holds now.
  """

  use Phoenix.LiveComponent

  alias FormFlow.Data.Templates.Flows.Health
  alias FormFlow.Web.Components.Core
  alias FormFlow.Web.Templates.Shared

  @impl true
  def mount(socket) do
    {:ok, assign(socket, open?: false)}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:user_id, fn -> nil end)
      |> assign_new(:flow_types, fn -> FormFlow.Config.Flows.Type.defaults() end)
      |> assign_new(:form_types, fn -> FormFlow.Config.Forms.Type.defaults() end)
      |> assign_new(:components, fn -> nil end)

    {:ok, check(socket)}
  end

  @impl true
  def handle_event("open", _params, socket), do: {:noreply, assign(socket, :open?, true)}
  def handle_event("close", _params, socket), do: {:noreply, assign(socket, :open?, false)}

  def handle_event("toggle_ignore", %{"code" => code, "path" => path}, socket) do
    health = socket.assigns.health

    case find_entry(health, code, path) do
      %Health.Entry{ignored: nil} = entry -> Health.ignore(health, entry, socket.assigns.user_id)
      %Health.Entry{} = entry -> Health.stop_ignoring(health, entry)
      nil -> :gone
    end

    {:noreply, check(socket)}
  end

  defp check(socket) do
    assign(
      socket,
      :health,
      Health.check(socket.assigns.flow_id,
        flow_types: socket.assigns.flow_types,
        form_types: socket.assigns.form_types
      )
    )
  end

  # The entry a switch named: by code and path, the pair that identifies
  # one. nil when the check no longer finds it.
  defp find_entry(%Health{entries: entries}, code, path) do
    Enum.find(entries, fn entry ->
      Atom.to_string(entry.code) == code and Enum.join(entry.path, "/") == path
    end)
  end

  defp find_entry(nil, _code, _path), do: nil

  @impl true
  def render(%{health: nil} = assigns) do
    ~H"""
    <div id={@id}></div>
    """
  end

  def render(assigns) do
    ~H"""
    <div id={@id} class="inline-block">
      <button
        type="button"
        class="relative inline-flex size-10 items-center justify-center rounded-lg border border-zinc-200 bg-white text-zinc-700 hover:bg-zinc-50"
        phx-click="open"
        phx-target={@myself}
        aria-haspopup="dialog"
        aria-expanded={to_string(@open?)}
        aria-label={"Health: #{health_words(@health)}"}
        title={"Health: #{health_words(@health)}"}
      >
        <svg
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="1.75"
          stroke-linecap="round"
          stroke-linejoin="round"
          class="size-5"
          aria-hidden="true"
        >
          <path d="M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4.05 3 5.5l7 7Z" />
        </svg>
        <span class={[
          "absolute -right-1.5 -top-1.5 inline-flex h-5 min-w-5 items-center justify-center rounded-full px-1 text-[11px] font-semibold ring-2 ring-white",
          level_colors(@health.level)
        ]}>
          {if Health.ok?(@health), do: "✓", else: open_count(@health)}
        </span>
      </button>

      <div
        :if={@open?}
        id={"#{@id}-modal"}
        class="fixed inset-0 z-50 flex items-center justify-center bg-black/40"
        role="dialog"
        aria-modal="true"
        aria-labelledby={"#{@id}-modal-title"}
        phx-window-keydown="close"
        phx-key="Escape"
        phx-target={@myself}
      >
        <div
          class="max-h-[90vh] w-[44rem] max-w-[calc(100vw-2rem)] overflow-y-auto rounded-lg border border-zinc-300 bg-white p-8 text-base shadow-lg"
          phx-click-away="close"
          phx-target={@myself}
        >
          <div class="mb-6 flex items-start justify-between gap-4">
            <h3 id={"#{@id}-modal-title"} class="text-xl font-semibold text-zinc-900">
              Health check
            </h3>
            <button
              type="button"
              class="btn btn-sm btn-ghost"
              phx-click="close"
              phx-target={@myself}
              aria-label="Close"
            >
              ✕
            </button>
          </div>

          <%!-- What the report is of --%>
          <dl class="mb-6 grid grid-cols-2 gap-x-8 gap-y-4 text-sm sm:grid-cols-3">
            <.fact label="Kind">
              {if @health.summary.label == "subflows", do: "Complex flow", else: "Simple flow"}
            </.fact>
            <.fact label="Steps">{@health.summary.steps}</.fact>
            <.fact label="Subflows">{@health.summary.subflows}</.fact>
            <.fact label="Forms">{@health.summary.forms}</.fact>
            <.fact label="Perspectives">{perspective_names(@health, @flow_types)}</.fact>
            <.fact label="Flow types">{flow_type_names(@health, @flow_types)}</.fact>
          </dl>

          <%!-- How it stands --%>
          <div class="mb-6 grid grid-cols-2 gap-3 sm:grid-cols-4">
            <.count kind={:error} label="Errors" count={@health.counts.error} />
            <.count kind={:warning} label="Warnings" count={@health.counts.warning} />
            <.count kind={:info} label="Info" count={@health.counts.info} />
            <.count kind={:ignored} label="Ignored" count={@health.counts.ignored} />
          </div>

          <Core.alert :if={@health.entries == []} components={@components} kind={:success}>
            Nothing to report — every check passed.
          </Core.alert>

          <ul :if={@health.entries != []} class="divide-y divide-zinc-200 text-base">
            <li
              :for={entry <- @health.entries}
              class={["flex items-start justify-between gap-6 py-4", entry.ignored && "text-zinc-400"]}
            >
              <div class="min-w-0">
                <div class="flex flex-wrap items-baseline gap-x-2">
                  <span class={["badge badge-sm", level_badge(if(entry.ignored, do: :ignored, else: entry.level))]}>
                    {entry.level}
                  </span>
                  <span class={entry.ignored && "line-through"}>{entry.message}</span>
                </div>
                <p :if={entry.ignored} class="mt-1 text-sm italic">{ignored_by(entry.ignored)}</p>
              </div>
              <%!-- The Show/Edit switch, as a switch for ignoring: a styled
                    button rather than a checkbox, so its state is always the
                    server's --%>
              <button
                type="button"
                role="switch"
                aria-checked={to_string(entry.ignored != nil)}
                aria-label={if entry.ignored, do: "Stop ignoring", else: "Ignore"}
                phx-click="toggle_ignore"
                phx-value-code={entry.code}
                phx-value-path={Enum.join(entry.path, "/")}
                phx-target={@myself}
                class="flex shrink-0 items-center gap-2 text-sm"
              >
                <span class={[
                  "relative inline-flex h-6 w-11 shrink-0 items-center rounded-full transition-colors",
                  if(entry.ignored, do: "bg-cyan-600", else: "bg-zinc-300")
                ]}>
                  <span class={[
                    "inline-block h-5 w-5 rounded-full bg-white shadow transition-transform",
                    if(entry.ignored, do: "translate-x-5", else: "translate-x-0.5")
                  ]} />
                </span>
                <span class={if(entry.ignored, do: "font-semibold text-zinc-900", else: "text-zinc-500")}>
                  {if entry.ignored, do: "Ignored", else: "Ignore"}
                </span>
              </button>
            </li>
          </ul>
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
      <dt class="text-sm text-zinc-500">{@label}</dt>
      <dd class="mt-0.5 text-base font-medium text-zinc-900">{render_slot(@inner_block)}</dd>
    </div>
    """
  end

  attr(:kind, :atom, required: true)
  attr(:label, :string, required: true)
  attr(:count, :integer, required: true)

  defp count(assigns) do
    ~H"""
    <div class="rounded-lg border border-zinc-200 px-4 py-3">
      <div class="text-sm text-zinc-500">{@label}</div>
      <div class="mt-1 flex items-baseline gap-2">
        <span class="text-2xl font-semibold text-zinc-900">{@count}</span>
        <span :if={@count > 0} class={["badge badge-xs", level_badge(@kind)]}>{@label}</span>
      </div>
    </div>
    """
  end

  # The badges' colours, as the button's pill: solid, in the level's colour
  defp level_colors(:ok), do: "bg-success text-success-content"
  defp level_colors(:error), do: "bg-error text-error-content"
  defp level_colors(:warning), do: "bg-warning text-warning-content"
  defp level_colors(:info), do: "bg-info text-info-content"

  # Solid badges in the modal, one colour per level; ignored is neutral
  defp level_badge(:error), do: "badge-error"
  defp level_badge(:warning), do: "badge-warning"
  defp level_badge(:info), do: "badge-info"
  defp level_badge(:ignored), do: "badge-neutral"

  defp open_count(health), do: length(Health.open(health))

  # For the button's label, since the icon says nothing on its own
  defp health_words(%Health{} = health) do
    if Health.ok?(health), do: "healthy", else: "#{open_count(health)} to look at"
  end

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
