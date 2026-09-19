defmodule FormFlow.Web.Components.TextTree do
  @moduledoc """
  `FormFlow.Web.Components.TextTree` function component renders the overview
  as text: the whole flow as a nested list of plain HTML, no canvas. The
  Text layout of `FormFlow.Web.Templates.Flows.Overview`.

  It reads the same nested tree the canvas does
  (`FormFlow.Web.Helpers.ReactFlow.to_tree_data/1`, already narrowed to the
  steps connected to Start) and walks each level from its Start, following
  the edges: one list item per step, in order, a subflow's item holding its
  own list. Start and End are not listed - in a list they say nothing.
  Every step's name links where the canvas's Open button goes: a form to its
  form page, a subflow to its show page, both under the root.

  Nearly every flow is one line from Start to End, which is what a list
  reads best. Where a flow is not:

    * a step with several next steps lists them under **Then one of:**,
      each choice its own list, walked to its own end
    * a step already listed - a loop back, or two choices meeting again -
      is not listed twice: the walk stops there with **back to** it, when it
      is an earlier step of this same line, or **continues at** it otherwise

  Used by `FormFlow.Web.Templates.Flows.Overview`:

      <TextTree.text_tree tree={@tree} base={@base} root_id={@flow.id} ... />
  """

  use Phoenix.Component

  attr(:tree, :map,
    required: true,
    doc:
      "nested tree data, see ReactFlow.to_tree_data/1 - atom keys at each level " <>
        "(flow, nodes, edges, subflows), the nodes and edges themselves string-keyed"
  )

  attr(:base, :string, required: true)
  attr(:root_id, :string, required: true, doc: "the root flow every link is under")

  attr(:flow_type_options, :list,
    default: [],
    doc: "flow_type choices as {label, value, kind} tuples, to name a subflow's type"
  )

  attr(:form_type_options, :list,
    default: [],
    doc: "form_type choices as {label, value} tuples, to name a form's type"
  )

  attr(:perspective_options, :list,
    default: [],
    doc: "perspective names as {label, value} tuples, to name who a form subflow is for"
  )

  def text_tree(assigns) do
    # What every step's entry needs: where its link goes, and the names of
    # its type and perspectives
    ctx =
      Map.take(assigns, [
        :base,
        :root_id,
        :flow_type_options,
        :form_type_options,
        :perspective_options
      ])

    assigns = assign(assigns, entries: walk(assigns.tree), ctx: ctx)

    ~H"""
    <div class="rounded-lg border border-zinc-300 bg-white px-6 py-5 text-sm">
      <p :if={@entries == []} class="italic text-zinc-500">Nothing is connected to Start yet.</p>
      <.entries :if={@entries != []} entries={@entries} tree={@tree} ctx={@ctx} />
    </div>
    """
  end

  attr(:entries, :list, required: true)
  attr(:tree, :map, required: true)
  attr(:ctx, :map, required: true)

  defp entries(assigns) do
    ~H"""
    <ul class="space-y-1">
      <%= for entry <- @entries do %>
        <%= case entry do %>
          <% {:step, node} -> %>
            <li class="border-l-2 border-zinc-200 pl-4">
              <.step node={node} tree={@tree} ctx={@ctx} />
            </li>
          <% {:branch, branches} -> %>
            <li class="border-l-2 border-zinc-200 pl-4">
              <span class="text-zinc-500">Then one of:</span>
              <ul class="mt-1 space-y-1">
                <li :for={branch <- branches} class="border-l-2 border-dashed border-zinc-300 pl-4">
                  <.entries entries={branch} tree={@tree} ctx={@ctx} />
                </li>
              </ul>
            </li>
          <% {:back, node} -> %>
            <li class="border-l-2 border-zinc-200 pl-4 text-zinc-500">
              <span aria-hidden="true">↩</span> back to {label(node)}
            </li>
          <% {:continue, node} -> %>
            <li class="border-l-2 border-zinc-200 pl-4 text-zinc-500">
              <span aria-hidden="true">→</span> continues at {label(node)}
            </li>
        <% end %>
      <% end %>
    </ul>
    """
  end

  attr(:node, :map, required: true)
  attr(:tree, :map, required: true)
  attr(:ctx, :map, required: true)

  defp step(%{node: node, tree: tree, ctx: ctx} = assigns) do
    if subflow?(node, tree) do
      subtree = tree.subflows[node["id"]]

      assigns =
        assign(assigns,
          subtree: subtree,
          entries: walk(subtree),
          meta: subflow_meta(node, subtree, ctx)
        )

      ~H"""
      <div class="py-0.5">
        <.link
          navigate={"#{@ctx.base}/flows/#{@ctx.root_id}/nodes/#{@node["id"]}"}
          class="font-semibold text-zinc-900 hover:underline"
        >
          <span aria-hidden="true">⧉</span> {label(@node)}
        </.link>
        <span class="ml-2 text-xs text-zinc-500">{@meta}</span>
      </div>
      <p :if={@entries == []} class="ml-4 italic text-zinc-400">No connected steps</p>
      <.entries :if={@entries != []} entries={@entries} tree={@subtree} ctx={@ctx} />
      """
    else
      assigns = assign(assigns, :meta, form_meta(node, ctx))

      ~H"""
      <div class="py-0.5">
        <.link
          navigate={"#{@ctx.base}/flows/#{@ctx.root_id}/nodes/#{@node["id"]}/form"}
          class="text-zinc-900 hover:underline"
        >
          {label(@node)}
        </.link>
        <span class="ml-2 text-xs text-zinc-500">{@meta}</span>
      </div>
      """
    end
  end

  # The level's steps in order from its Start, as entries: {:step, node},
  # {:branch, [entries]}, {:back, node}, or {:continue, node}. `listed` is
  # every node already given an entry anywhere in the level, `line` the
  # ones on the way to the current step.
  defp walk(nil), do: []

  defp walk(tree) do
    nodes = Map.new(tree.nodes || [], &{&1["id"], &1})

    next =
      Enum.group_by(tree.edges || [], & &1["source"], & &1["target"])
      |> Map.new(fn {source, targets} ->
        {source, Enum.filter(targets, &Map.has_key?(nodes, &1))}
      end)

    case Enum.find(tree.nodes || [], &(kind(&1) == "start")) do
      nil ->
        []

      start ->
        start["id"] |> follow(nodes, next, MapSet.new([start["id"]]), [start["id"]]) |> elem(0)
    end
  end

  # From `id`, the entries that follow it; returns them with the listed set
  defp follow(id, nodes, next, listed, line) do
    case Map.get(next, id, []) do
      [] ->
        {[], listed}

      [target] ->
        visit(target, nodes, next, listed, line)

      targets ->
        {branches, listed} =
          Enum.map_reduce(targets, listed, fn target, listed ->
            visit(target, nodes, next, listed, line)
          end)

        {[{:branch, branches}], listed}
    end
  end

  defp visit(id, nodes, next, listed, line) do
    node = nodes[id]

    cond do
      kind(node) == "end" ->
        {[], listed}

      id in line ->
        {[{:back, node}], listed}

      MapSet.member?(listed, id) ->
        {[{:continue, node}], listed}

      true ->
        {rest, listed} = follow(id, nodes, next, MapSet.put(listed, id), [id | line])
        {[{:step, node} | rest], listed}
    end
  end

  defp kind(node), do: get_in(node, ["data", "kind"])
  defp label(node), do: get_in(node, ["data", "label"]) || "Untitled"

  defp subflow?(node, tree),
    do: node["type"] == "subflow" or Map.has_key?(tree.subflows || %{}, node["id"])

  # "Complex subflow · Any order", or "Form subflow · Wizard (in order) ·
  # Perspectives: Applicant"
  defp subflow_meta(node, subtree, ctx) do
    data = node["data"] || %{}
    flow_label = (subtree && subtree.flow.label) || data["subflow_label"] || "forms"
    form? = flow_label != "subflows"
    kind = if form?, do: :forms, else: :subflows

    type =
      Enum.find_value(ctx.flow_type_options, fn
        {label, value, ^kind} -> value == data["flow_type"] && label
        {label, value, nil} -> value == data["flow_type"] && label
        _other -> nil
      end) || data["flow_type"]

    perspectives =
      case data["perspectives"] do
        ids when form? and is_list(ids) and ids != [] ->
          names =
            Enum.map(ids, fn id ->
              Enum.find_value(ctx.perspective_options, fn {label, value} ->
                value == id && label
              end) || id
            end)

          "Perspectives: " <> Enum.join(names, ", ")

        _other ->
          nil
      end

    [if(form?, do: "Form subflow", else: "Complex subflow"), type, perspectives]
    |> Enum.reject(&(&1 in [nil, false, ""]))
    |> Enum.join(" · ")
  end

  defp form_meta(node, ctx) do
    type = get_in(node, ["data", "form_type"])

    Enum.find_value(ctx.form_type_options, fn {label, value} -> value == type && label end) ||
      type || ""
  end
end
