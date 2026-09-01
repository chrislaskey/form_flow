defmodule FormFlow.Data.Instances.Flows.Progress do
  @moduledoc """
  Derives the traversal state of a whole root flow instance — a journey (see
  `FormFlow.Data.Instances` for the term) — as a pure function of the live
  flow tree and the form instances filled inside it.
  Nothing here is persisted, which is the point: derived state cannot desync
  from the template (instances plan, D2). Statuses fold upward through the
  tree; a form instance whose `path` matches no position in the current tree
  surfaces as `:stranded` rather than being silently dropped or reconciled.

  The committed minimal join rule (revisable here, and only here): **a
  position is available when every source of its incoming edges is
  completed (AND-join); End is reached when every predecessor is
  completed.** Single-edge chains degenerate to plain ordering; richer
  parallel-branch semantics (OR-joins, N-of-M) stay deferred (subflows
  plan, R1) and land in this module when decided.

  Two views of that one derivation:

    * `derive/2` — every position's status, keyed by path. The primitive the
      join rule is expressed in.
    * `forms/2` — the journey's *form* positions only, as an ordered list of
      `FormFlow.Data.Instances.FormProgress` structs carrying the label,
      live instance, and owning flow alongside the status. This is what the
      user-facing pages render.

  Order, for `forms/2`, is the order a filler works them: breadth-first from
  Start, descending into subflows the moment one is reached — the same scan
  `next_path_position/2` performs. `forms_in_flow/2` narrows the list to one
  "forms" flow's own — the sequence a filler works through, front to back:
  `actionable?/1` is where the flow allows work, and the pages open only
  there.

  Form instances with `superseded_at` set are skipped everywhere — they are
  attestation records left behind by strand reconciliation, not live
  traversal state.

  The tree comes from `FormFlow.Data.Templates.Flows.resolve_tree/1`. The
  journey's stamped `status` and this module answer different questions and
  may legitimately diverge after a template edit — `complete?/2` is the
  derivation-side answer.
  """

  alias FormFlow.Data.Instances.FormProgress

  @type status :: :pending | :available | :in_progress | :completed | :stranded
  @type path :: [binary()]

  @doc """
  Per-position statuses for a journey: `%{path => status()}` with an entry
  for every position in the resolved tree, plus a `:stranded` entry for
  each active form instance whose `path` matches no position.
  """
  @spec derive(tree :: map() | nil, form_instances :: [struct()]) :: %{path() => status()}
  def derive(tree, form_instances) do
    instances = active_by_path(form_instances)
    statuses = walk(tree, [], instances, %{})

    stranded =
      for {path, _instance} <- instances,
          not Map.has_key?(statuses, path),
          into: %{} do
        {path, :stranded}
      end

    Map.merge(statuses, stranded)
  end

  @doc """
  Whether the root flow's End is reached — every predecessor completed,
  recursively through subflows. Requires at least one End node: a malformed
  flow without one is never derivably complete.
  """
  @spec complete?(tree :: map(), form_instances :: [struct()]) :: boolean()
  def complete?(tree, form_instances) do
    instances = active_by_path(form_instances)
    ctx = context(tree, [], instances)
    ends = Enum.filter(tree.nodes, &(kind(&1) == :end))

    ends != [] and Enum.all?(ends, &completed?(&1, ctx, MapSet.new()))
  end

  @doc """
  The next actionable position: the first form position in flow order —
  breadth-first from Start, descending into subflows the moment they are
  reachable — whose status is `:available` or `:in_progress`. Returns its
  path, or nil when nothing is actionable (journey done, or blocked).
  """
  @spec next_path_position(tree :: map() | nil, form_instances :: [struct()]) :: path() | nil
  def next_path_position(tree, form_instances) do
    statuses = derive(tree, form_instances)
    search_flow(tree, [], statuses)
  end

  @doc """
  The journey's form positions in the order they are worked, each as a
  `FormFlow.Data.Instances.FormProgress`.

  Positions the tree no longer has are absent — a stranded instance is not a
  form of the flow any more (`FormFlow.Data.Instances.Flows.list_stranded/2`
  is where those surface).
  """
  @spec forms(tree :: map() | nil, form_instances :: [struct()]) :: [FormProgress.t()]
  def forms(tree, form_instances) do
    ctx = %{statuses: derive(tree, form_instances), instances: active_by_path(form_instances)}

    flow_forms(tree, [], [], ctx)
  end

  @doc """
  The forms sharing a position's "forms" flow, in order — the sequence the
  filler works through.

  Positions are compared by their parent path rather than by flow id: a
  reusable subflow used twice in one journey is two traversals, tracked
  separately, and they share a flow.
  """
  @spec forms_in_flow([FormProgress.t()], path()) :: [FormProgress.t()]
  def forms_in_flow(forms, path) do
    flow = Enum.drop(path, -1)

    Enum.filter(forms, &(Enum.drop(&1.path, -1) == flow))
  end

  @doc "The form at a position, or nil when the tree no longer has it."
  @spec find_form([FormProgress.t()], path()) :: FormProgress.t() | nil
  def find_form(forms, path), do: Enum.find(forms, &(&1.path == path))

  @doc """
  Whether the flow allows work on a form: its predecessors are done, or it is
  already started. Anything else is gated — including, after a submit, the
  form just completed. The same test `next_path_position/2` scans for.
  """
  @spec actionable?(FormProgress.t()) :: boolean()
  def actionable?(%FormProgress{status: status}), do: status in [:available, :in_progress]

  @doc """
  A form's label prefixed with the subflows drilled through to reach it —
  "Documents / Proof of address". Unqualified for a form in the root flow,
  where there is nothing to prefix.
  """
  @spec qualified_label(FormProgress.t()) :: String.t()
  def qualified_label(%FormProgress{} = form) do
    Enum.join(Enum.map(form.ancestors, &node_label/1) ++ [form.label], " / ")
  end

  # One flow scope: build its edge/node lookups and scan it in flow order,
  # starting the queue at its Start nodes.
  defp search_flow(nil, _prefix, _statuses), do: nil

  defp search_flow(tree, prefix, statuses) do
    outgoing = Enum.group_by(tree.relationships, & &1.source_id)
    nodes_by_id = Map.new(tree.nodes, &{&1.id, &1})
    starts = for node <- tree.nodes, kind(node) == :start, do: node.id

    first_actionable(starts, MapSet.new(), tree, prefix, statuses, outgoing, nodes_by_id)
  end

  # Scans a queue of node ids in flow order — breadth-first along the edges,
  # so nearer positions win — returning the first actionable position: an
  # available or in-progress form, or the first such position *inside* an
  # actionable subflow (descend the moment one is reachable).
  defp first_actionable([], _seen, _tree, _prefix, _statuses, _outgoing, _nodes_by_id), do: nil

  defp first_actionable([id | rest], seen, tree, prefix, statuses, outgoing, nodes_by_id) do
    if MapSet.member?(seen, id) do
      first_actionable(rest, seen, tree, prefix, statuses, outgoing, nodes_by_id)
    else
      seen = MapSet.put(seen, id)
      node = nodes_by_id[id]
      position = prefix ++ [id]
      status = statuses[position]

      hit =
        case kind(node) do
          :form when status in [:available, :in_progress] ->
            position

          :subflow when status in [:available, :in_progress] ->
            search_flow(tree.subflows[id], position, statuses)

          _other ->
            nil
        end

      successors = for relationship <- Map.get(outgoing, id, []), do: relationship.target_id

      hit ||
        first_actionable(rest ++ successors, seen, tree, prefix, statuses, outgoing, nodes_by_id)
    end
  end

  # The same per-flow scan as search_flow, collecting every form position
  # instead of stopping at the first actionable one.
  defp flow_forms(nil, _prefix, _ancestors, _ctx), do: []

  defp flow_forms(tree, prefix, ancestors, ctx) do
    scope = %{
      tree: tree,
      prefix: prefix,
      ancestors: ancestors,
      outgoing: Enum.group_by(tree.relationships, & &1.source_id),
      nodes_by_id: Map.new(tree.nodes, &{&1.id, &1})
    }

    starts = for node <- tree.nodes, kind(node) == :start, do: node.id

    collect(starts, MapSet.new(), scope, ctx)
  end

  defp collect([], _seen, _scope, _ctx), do: []

  defp collect([id | rest], seen, scope, ctx) do
    if MapSet.member?(seen, id) do
      collect(rest, seen, scope, ctx)
    else
      seen = MapSet.put(seen, id)
      node = scope.nodes_by_id[id]
      successors = for relationship <- Map.get(scope.outgoing, id, []), do: relationship.target_id
      path = scope.prefix ++ [id]

      found =
        case kind(node) do
          :form ->
            [form_progress(node, path, scope, ctx)]

          :subflow ->
            flow_forms(scope.tree.subflows[id], path, scope.ancestors ++ [node], ctx)

          _other ->
            []
        end

      found ++ collect(rest ++ successors, seen, scope, ctx)
    end
  end

  defp form_progress(node, path, scope, ctx) do
    %FormProgress{
      path: path,
      label: node_label(node),
      ancestors: scope.ancestors,
      status: ctx.statuses[path],
      instance: ctx.instances[path],
      flow: scope.tree.flow
    }
  end

  defp active_by_path(form_instances) do
    for instance <- form_instances,
        is_nil(instance.superseded_at),
        (instance.path || []) != [],
        into: %{} do
      {instance.path, instance}
    end
  end

  defp walk(nil, _prefix, _instances, acc), do: acc

  defp walk(tree, prefix, instances, acc) do
    ctx = context(tree, prefix, instances)

    acc =
      Enum.reduce(tree.nodes, acc, fn node, acc ->
        Map.put(acc, prefix ++ [node.id], status(node, ctx))
      end)

    Enum.reduce(tree.subflows, acc, fn {node_id, subtree}, acc ->
      walk(subtree, prefix ++ [node_id], instances, acc)
    end)
  end

  defp context(tree, prefix, instances) do
    %{
      prefix: prefix,
      instances: instances,
      subflows: tree.subflows,
      nodes_by_id: Map.new(tree.nodes, &{&1.id, &1}),
      incoming: Enum.group_by(tree.relationships, & &1.target_id)
    }
  end

  defp status(node, ctx) do
    cond do
      completed?(node, ctx, MapSet.new()) -> :completed
      in_progress?(node, ctx) -> :in_progress
      preds_completed?(node, ctx, MapSet.new([node.id])) -> :available
      true -> :pending
    end
  end

  # Completion is intrinsic for Start (trivially complete), form nodes
  # (their instance's stamped status), and subflow nodes (their interior
  # End); End and unknown kinds complete when every predecessor does — the
  # committed AND-join. The visiting set breaks edge cycles: a node on a
  # cycle is never derivably complete.
  defp completed?(node, ctx, visiting) do
    if MapSet.member?(visiting, node.id) do
      false
    else
      visiting = MapSet.put(visiting, node.id)

      case kind(node) do
        :start -> true
        :form -> match?(%{status: "completed"}, ctx.instances[ctx.prefix ++ [node.id]])
        :subflow -> subflow_complete?(node, ctx)
        _end_or_other -> preds_completed?(node, ctx, visiting)
      end
    end
  end

  defp preds_completed?(node, ctx, visiting) do
    ctx.incoming
    |> Map.get(node.id, [])
    |> Enum.all?(fn relationship ->
      case ctx.nodes_by_id[relationship.source_id] do
        nil -> true
        source -> completed?(source, ctx, visiting)
      end
    end)
  end

  defp subflow_complete?(node, ctx) do
    case ctx.subflows[node.id] do
      nil ->
        false

      subtree ->
        subctx = context(subtree, ctx.prefix ++ [node.id], ctx.instances)
        ends = Enum.filter(subtree.nodes, &(kind(&1) == :end))

        ends != [] and Enum.all?(ends, &completed?(&1, subctx, MapSet.new()))
    end
  end

  # Reached only when not completed: a form position with any instance is
  # being worked on; a subflow position with any instance anywhere under it
  # has been entered.
  defp in_progress?(node, ctx) do
    position = ctx.prefix ++ [node.id]

    case kind(node) do
      :form -> Map.has_key?(ctx.instances, position)
      :subflow -> Enum.any?(Map.keys(ctx.instances), &List.starts_with?(&1, position))
      _other -> false
    end
  end

  # Structural references first (a saved node always carries them), labels
  # as the fallback for nodes not yet pointed at their form/subflow.
  defp kind(node) do
    cond do
      node.subflow_id -> :subflow
      node.form_id -> :form
      "Subflow" in node.labels -> :subflow
      "Form" in node.labels -> :form
      "Start" in node.labels -> :start
      "End" in node.labels -> :end
      true -> :other
    end
  end

  defp node_label(node) do
    get_in(node.properties, ["data", "label"]) || List.first(node.labels) || "Untitled"
  end
end
