defmodule FormFlow.Web.Instances.Flows.Show do
  @moduledoc """
  `FormFlow.Web.Instances.Flows.Show` LiveComponent is a journey's detail page:
  every form position in flow order with its derived state — Available /
  In progress / Done / Pending — plus any stranded answers (filled at a
  position the flow no longer has).

  Opening an Available position is what creates its form instance
  (`FormFlow.Data.Instances.Forms.update_status/4` with `:in_progress` —
  create-on-open, which is the moment the form version is pinned) before
  navigating to the fill page. Reopen is the same call on a Done form:
  `:in_progress` on a completed instance sends it back.
  """

  use Phoenix.LiveComponent

  alias FormFlow.Data.Instances
  alias FormFlow.Data.Instances.Progress
  alias FormFlow.Data.Templates

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:base, fn -> "" end)
      |> assign_new(:error, fn -> nil end)

    {:ok, load(socket)}
  end

  @impl true
  def handle_event("open", %{"path" => joined}, socket) do
    path = String.split(joined, ",")
    journey = socket.assigns.journey

    case Instances.Forms.update_status(journey, path, :in_progress,
           user_id: socket.assigns.user_id
         ) do
      {:ok, instance} ->
        to = "#{socket.assigns.base}/journeys/#{journey.id}/instances/#{instance.id}"
        {:noreply, push_navigate(socket, to: to)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, open_error(reason))}
    end
  end

  def handle_event("reopen", %{"path" => joined}, socket) do
    path = String.split(joined, ",")

    case Instances.Forms.update_status(socket.assigns.journey, path, :in_progress,
           user_id: socket.assigns.user_id
         ) do
      {:ok, _reopened} -> {:noreply, load(socket)}
      {:error, _reason} -> {:noreply, assign(socket, :error, "Could not reopen the form.")}
    end
  end

  defp load(%{assigns: %{journey_id: journey_id}} = socket) do
    case Instances.Flows.get(journey_id) do
      nil ->
        assign(socket, journey: nil, rows: [], stranded: [], flow_name: nil)

      journey ->
        tree = Templates.Flows.resolve_tree(journey.flow_id)
        instances = Instances.Flows.form_instances(journey)
        statuses = Progress.derive(tree, instances)

        by_path =
          for instance <- instances, is_nil(instance.superseded_at), into: %{} do
            {instance.path, instance}
          end

        rows =
          for {path, label} <- form_positions(tree, [], nil) do
            %{path: path, label: label, status: statuses[path], instance: by_path[path]}
          end

        stranded =
          for instance <- Instances.Flows.list_stranded(journey), do: instance

        assign(socket,
          journey: journey,
          rows: rows,
          stranded: stranded,
          flow_name: (tree && tree.flow.name) || "Untitled flow"
        )
    end
  end

  # Form positions in flow order — breadth-first from Start within each
  # flow, descending into subflows — labeled from the node's canvas label,
  # prefixed with the subflow chain ("Documents / Proof of address").
  defp form_positions(nil, _prefix, _label_prefix), do: []

  defp form_positions(tree, prefix, label_prefix) do
    outgoing = Enum.group_by(tree.relationships, & &1.source_id)
    nodes_by_id = Map.new(tree.nodes, &{&1.id, &1})
    starts = for node <- tree.nodes, "Start" in node.labels, do: node.id

    walk(starts, MapSet.new(), tree, prefix, label_prefix, outgoing, nodes_by_id)
  end

  defp walk([], _seen, _tree, _prefix, _label_prefix, _outgoing, _nodes_by_id), do: []

  defp walk([id | rest], seen, tree, prefix, label_prefix, outgoing, nodes_by_id) do
    if MapSet.member?(seen, id) do
      walk(rest, seen, tree, prefix, label_prefix, outgoing, nodes_by_id)
    else
      seen = MapSet.put(seen, id)
      node = nodes_by_id[id]
      successors = for relationship <- Map.get(outgoing, id, []), do: relationship.target_id
      label = join_label(label_prefix, node_label(node))

      found =
        cond do
          node.form_id || "Form" in node.labels ->
            [{prefix ++ [id], label}]

          node.subflow_id ->
            form_positions(tree.subflows[id], prefix ++ [id], label)

          true ->
            []
        end

      found ++ walk(rest ++ successors, seen, tree, prefix, label_prefix, outgoing, nodes_by_id)
    end
  end

  defp node_label(node) do
    get_in(node.properties, ["data", "label"]) || List.first(node.labels) || "Untitled"
  end

  defp join_label(nil, label), do: label
  defp join_label(prefix, label), do: "#{prefix} / #{label}"

  defp open_error(:no_published_version),
    do: "That form has no published version yet — ask an administrator to publish it."

  defp open_error(_reason), do: "Could not open the form. The flow may have changed — reload."

  defp badge(:completed), do: {"Done", "bg-emerald-50 text-emerald-700 border-emerald-200"}
  defp badge(:in_progress), do: {"In progress", "bg-amber-50 text-amber-700 border-amber-200"}
  defp badge(:available), do: {"Available", "bg-cyan-50 text-cyan-700 border-cyan-200"}
  defp badge(_pending), do: {"Pending", "bg-zinc-50 text-zinc-500 border-zinc-200"}

  @impl true
  def render(%{journey: nil} = assigns) do
    ~H"""
    <p class="text-sm text-zinc-500">This journey no longer exists.</p>
    """
  end

  def render(assigns) do
    ~H"""
    <div>
      <div class="mb-2 text-sm font-semibold">
        <.link navigate={"#{@base}/journeys"} class="hover:underline">Journeys</.link>
        <span class="text-zinc-400">/</span>
        {@flow_name}
        <span
          :if={@journey.status == "completed"}
          class="ml-2 rounded-full border border-emerald-200 bg-emerald-50 px-2 py-0.5 text-xs text-emerald-700"
        >
          Completed
        </span>
      </div>

      <p :if={@error} class="mb-2 text-xs text-red-600">{@error}</p>

      <ul class="space-y-1.5 text-sm">
        <li :for={row <- @rows} class="flex items-center gap-3">
          <% {text, classes} = badge(row.status) %>
          <span class={"rounded-full border px-2 py-0.5 text-xs #{classes}"}>{text}</span>
          <span>{row.label}</span>
          <span class="ml-auto flex items-center gap-2">
            <button
              :if={row.status == :available}
              phx-click="open"
              phx-value-path={Enum.join(row.path, ",")}
              phx-target={@myself}
              class="rounded-md border border-zinc-300 px-2 py-0.5 text-xs hover:border-zinc-400"
            >
              Open
            </button>
            <.link
              :if={row.status == :in_progress && row.instance}
              navigate={"#{@base}/journeys/#{@journey.id}/instances/#{row.instance.id}"}
              class="text-cyan-600 hover:underline"
            >
              Continue →
            </.link>
            <.link
              :if={row.status == :completed && row.instance}
              navigate={"#{@base}/journeys/#{@journey.id}/instances/#{row.instance.id}"}
              class="text-cyan-600 hover:underline"
            >
              View →
            </.link>
            <button
              :if={row.status == :completed && row.instance}
              phx-click="reopen"
              phx-value-path={Enum.join(row.path, ",")}
              phx-target={@myself}
              class="rounded-md border border-zinc-300 px-2 py-0.5 text-xs hover:border-zinc-400"
            >
              Reopen
            </button>
          </span>
        </li>
      </ul>

      <div
        :if={@stranded != []}
        class="mt-4 rounded-md border border-amber-300 bg-amber-50 px-3 py-2 text-xs text-amber-800"
      >
        {length(@stranded)} answer set(s) were filled at positions this flow no longer has.
        An administrator can resolve them.
      </div>
    </div>
    """
  end
end
