defmodule FormFlow.Web.Templates.Flows.Index do
  @moduledoc """
  `FormFlow.Web.Templates.Flows.Index` LiveComponent lists flows.

  A `Slab.table` over `FormFlow.Data.Templates.Flows.roots_query/0` — summary
  counts and timestamps, with show and edit actions per row and a link to create a
  new flow. The editor itself lives on those pages, so this one never loads
  the ReactFlow bundle. Slab runs in query mode against the host app's repo,
  so sorting and pagination come from the URL: pass the current `uri` and
  `params` from `handle_params/3` (the `FormFlow.Web.Router` component
  forwards both).

      <.live_component
        module={FormFlow.Web.Templates.Flows.Index}
        id="flows-index"
        uri={@uri}
        params={@params}
      />

  Without a `sort` param the table sorts by creation time, matching
  `Flows.list/0` — injected into the params handed to Slab so pagination
  stays deterministic instead of leaning on unspecified database order.

  The count columns aren't sortable: they are virtual fields populated by
  the query's select, not real columns Slab could compile into `ORDER BY`.

  `base` is the path prefix the flows pages are mounted under, used to build
  the links — with the default `""`, rows link to `/flows/:id`.

  ## Health

  Every row carries the flow's health
  (`FormFlow.Data.Templates.Flows.Health`): a badge at the worst level found
  — OK, or so many errors, warnings, and infos — that opens on the list of
  problems, each one sentence naming the step or subflow. The check runs
  when a row renders, over the flow's whole tree, so a listing of ten flows
  loads ten trees; the index is where an admin looks for what is left to do,
  and that is the cost of answering there. `flow_types` and `form_types` —
  the host's lists, the same the edit pages take — are what the type checks
  read; the router passes both.

  Each problem in the list has an **Ignore** button, and an ignored one
  says who ignored it and when, with **Stop ignoring** beside it
  (`Health.ignore/3`, `Health.stop_ignoring/2`). Ignored problems leave the
  badge's count, so it says what is new. `user_id` — the host's identity
  for the admin, as the router passes it — is who the record names.

  The open lists are the component's state: `health` holds a report per
  flow whose list is open, refreshed on every toggle, and the row reads it
  in place of running the check again. That is also what re-renders the
  table after an ignore: the report changed.
  """

  use Phoenix.LiveComponent

  import FormFlow.Web.Helpers.Paths

  alias FormFlow.Data.Repo
  alias FormFlow.Data.Templates.Flows
  alias FormFlow.Data.Templates.Flows.Health
  alias FormFlow.Web.Components.Core

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:base, fn -> "" end)
      |> assign_new(:tenant_id, fn -> nil end)
      |> assign_new(:components, fn -> nil end)
      |> assign_new(:user_id, fn -> nil end)
      |> assign_new(:flow_types, fn -> FormFlow.Config.Flows.Type.defaults() end)
      |> assign_new(:form_types, fn -> FormFlow.Config.Forms.Type.defaults() end)
      |> assign_new(:health, fn -> %{} end)
      |> assign_new(:uri, fn -> nil end)
      |> assign_new(:params, fn -> %{} end)

    query = Flows.roots_query(tenant_id: socket.assigns.tenant_id)

    {:ok,
     socket
     |> assign(:query, query)
     |> assign(:empty?, not Repo.exists?(query))
     |> assign(:table_params, Map.put_new(socket.assigns.params, "sort", "inserted_at"))}
  end

  @impl true
  def handle_event("show_problems", %{"flow_id" => flow_id}, socket) do
    {:noreply, refresh_health(socket, flow_id)}
  end

  def handle_event("hide_problems", %{"flow_id" => flow_id}, socket) do
    {:noreply, assign(socket, :health, Map.delete(socket.assigns.health, flow_id))}
  end

  def handle_event("ignore_problem", %{"flow_id" => flow_id} = params, socket) do
    with {health, problem} <- find_problem(socket, flow_id, params),
         {:ok, _flow} <- Health.ignore(health, problem, socket.assigns.user_id) do
      {:noreply, refresh_health(socket, flow_id)}
    else
      _gone_or_refused -> {:noreply, refresh_health(socket, flow_id)}
    end
  end

  def handle_event("stop_ignoring_problem", %{"flow_id" => flow_id} = params, socket) do
    with {health, problem} <- find_problem(socket, flow_id, params),
         {:ok, _flow} <- Health.stop_ignoring(health, problem) do
      {:noreply, refresh_health(socket, flow_id)}
    else
      _gone_or_refused -> {:noreply, refresh_health(socket, flow_id)}
    end
  end

  # The report for one flow, checked again now — or dropped, for a flow
  # that has gone since the list was opened
  defp refresh_health(socket, flow_id) do
    health =
      case check(flow_id, socket.assigns.flow_types, socket.assigns.form_types) do
        nil -> Map.delete(socket.assigns.health, flow_id)
        health -> Map.put(socket.assigns.health, flow_id, health)
      end

    assign(socket, :health, health)
  end

  defp check(flow_id, flow_types, form_types) do
    Health.check(flow_id, flow_types: flow_types, form_types: form_types)
  end

  # The problem a button named, in the open report: by code and path, the
  # pair that identifies one. `nil` when the list was not open or the check
  # no longer finds it.
  defp find_problem(socket, flow_id, %{"code" => code, "path" => path}) do
    with %Health{} = health <- socket.assigns.health[flow_id],
         %Health.Problem{} = problem <-
           Enum.find(health.problems, fn problem ->
             Atom.to_string(problem.code) == code and Enum.join(problem.path, "/") == path
           end) do
      {health, problem}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="mb-2 flex items-center justify-between gap-4">
        <div class="text-sm font-semibold">
          <.link navigate={templates_path(@base)} class="hover:underline">Templates</.link>
          <span class="text-zinc-400">/</span>
          Flows
        </div>
        <Core.button components={@components} navigate={"#{@base}/flows/new"} variant="primary">
          New flow
        </Core.button>
      </div>

      <Core.alert :if={@empty?} components={@components}>
        No flows yet — create the first one.
      </Core.alert>

      <Slab.table
        :if={!@empty?}
        id="flows-table"
        query={@query}
        repo={Repo.repo()}
        uri={@uri}
        params={@table_params}
      >
        <:column :let={flow} field={:name} sortable>
          <.link navigate={"#{@base}/flows/#{flow.id}"} class="hover:underline">
            {flow.name || "Untitled"}
          </.link>
          <span class="block font-mono text-[10px] text-zinc-400">{flow.id}</span>
        </:column>
        <:column :let={flow} field={:label} label="Kind">
          <span class="text-xs text-zinc-500">
            {if flow.label == "subflows", do: "Complex", else: "Simple"}
          </span>
        </:column>
        <:column field={:nodes_count} label="Steps" />
        <:column field={:relationships_count} label="Connections" />
        <:column :let={flow} label="Health">
          <.health
            id={"flow-health-#{flow.id}"}
            health={@health[flow.id] || check(flow.id, @flow_types, @form_types)}
            open={Map.has_key?(@health, flow.id)}
            target={@myself}
            components={@components}
          />
        </:column>
        <:column :let={flow} field={:inserted_at} label="Created" sortable>
          <span class="text-xs text-zinc-500">
            {Calendar.strftime(flow.inserted_at, "%Y-%m-%d %H:%M")}
          </span>
        </:column>
        <:column :let={flow} label="Actions">
          <.link navigate={"#{@base}/flows/#{flow.id}"} class="text-cyan-600 hover:underline">
            Show
          </.link>
          <.link
            navigate={"#{@base}/flows/#{flow.id}/edit"}
            class="ml-3 text-cyan-600 hover:underline"
          >
            Edit
          </.link>
        </:column>
        <:pagination per_page={10} />
      </Slab.table>
    </div>
    """
  end

  # The health badge; a button when there is anything to list, opening the
  # problems under it with their Ignore and Stop ignoring buttons
  attr(:id, :string, required: true)
  attr(:health, Health, required: true)
  attr(:open, :boolean, required: true)
  attr(:target, :any, required: true)
  attr(:components, :atom, default: nil)

  defp health(%{health: %Health{problems: []}} = assigns) do
    ~H"""
    <Core.badge id={@id} components={@components} kind={:success}>OK</Core.badge>
    """
  end

  defp health(assigns) do
    ~H"""
    <div id={@id} class="text-xs">
      <button
        type="button"
        class="cursor-pointer"
        phx-click={if @open, do: "hide_problems", else: "show_problems"}
        phx-value-flow_id={@health.flow_id}
        phx-target={@target}
        aria-expanded={to_string(@open)}
      >
        <Core.badge components={@components} kind={badge_kind(@health.level)}>
          {counts_summary(@health.counts)}
        </Core.badge>
      </button>
      <ul :if={@open} class="mt-1 space-y-1 text-zinc-600">
        <li
          :for={problem <- @health.problems}
          class={["flex flex-wrap items-baseline gap-x-2 gap-y-0.5", problem.ignored && "text-zinc-400"]}
        >
          <Core.badge
            components={@components}
            kind={if problem.ignored, do: :neutral, else: badge_kind(problem.level)}
            class="badge-xs"
          >
            {problem.level}
          </Core.badge>
          <span class={problem.ignored && "line-through"}>{problem.message}</span>
          <span :if={problem.ignored} class="italic">{ignored_by(problem.ignored)}</span>
          <button
            type="button"
            class="link link-primary"
            phx-click={if problem.ignored, do: "stop_ignoring_problem", else: "ignore_problem"}
            phx-value-flow_id={@health.flow_id}
            phx-value-code={problem.code}
            phx-value-path={Enum.join(problem.path, "/")}
            phx-target={@target}
          >
            {if problem.ignored, do: "Stop ignoring", else: "Ignore"}
          </button>
        </li>
      </ul>
    </div>
    """
  end

  defp badge_kind(:ok), do: :success
  defp badge_kind(:error), do: :error
  defp badge_kind(:warning), do: :warning
  defp badge_kind(:info), do: :info

  # "2 errors, 1 warning" — the levels that have any, worst first — then
  # "3 ignored" when any are; "OK, 3 ignored" when that is all there is
  defp counts_summary(counts) do
    live =
      Health.Problem.levels()
      |> Enum.map(&{&1, counts[&1]})
      |> Enum.reject(fn {_level, count} -> count == 0 end)
      |> Enum.map(fn
        {level, 1} -> "1 #{level}"
        {level, count} -> "#{count} #{level}s"
      end)

    ignored = if counts.ignored > 0, do: ["#{counts.ignored} ignored"], else: []

    Enum.join(if(live == [], do: ["OK"], else: live) ++ ignored, ", ")
  end

  # "Ignored by demo-admin on 2026-09-08" — with what the record has
  defp ignored_by(%{user_id: user_id, ignored_at: at}) do
    Enum.join(
      ["Ignored", user_id && "by #{user_id}", at && "on #{Calendar.strftime(at, "%Y-%m-%d")}"]
      |> Enum.reject(&is_nil/1),
      " "
    )
  end
end
