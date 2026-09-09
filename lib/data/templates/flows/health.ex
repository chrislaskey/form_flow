defmodule FormFlow.Data.Templates.Flows.Health do
  @moduledoc """
  `FormFlow.Data.Templates.Flows.Health` checks a root flow — the whole
  tree, subflows included — and reports what it finds as a list of
  `FormFlow.Data.Templates.Flows.Health.Entry` structs sorted worst first,
  with the worst level as the one-word answer. A health check, in prose;
  what it lists are **entries**, not entries, because a check reads the
  flow's shape and can be wrong about what is fine on purpose — see
  "Ignoring an entry" below.

  The pages draw it: the flows index shows a badge per root flow with the
  entries under it. Nothing here writes anything but an ignore, and nothing
  refuses a save on it — the checks describe a flow as it stands, so an
  admin building one sees what is left to do, and a finished flow shows
  none.

  ## Two ways in

    * `check/2` with a root flow's **id** loads the tree
      (`FormFlow.Data.Templates.Flows.resolve_tree/1`), preloads each form's
      versions — the one thing the tree does not carry that the checks need
      — and runs the checks. `nil` for an unknown id.
    * `check/2` with a **tree** — the map `resolve_tree/1` returns — runs
      the checks and touches no database. That is what makes the checks
      testable on hand-built trees, and what a later caller checking
      unsaved canvas contents would build one for.

  Both take `flow_types:` and `form_types:`, the host's lists (the same the
  pages are given), defaulting to the library's. The type checks read them:
  a type a template names that the list no longer has, a property a type
  requires that was never set.

  ## The checks

  At every level of the tree, root and each connected subflow:

  | Code | Level | When |
  |---|---|---|
  | `:no_start` | error | the flow has no Start node |
  | `:no_end` | error | the flow has no End node |
  | `:end_unreachable` | error | following relationships forward from Start never arrives at an End |
  | `:form_missing` | error | a connected form step points at no form, or at one that no longer exists |
  | `:form_not_published` | error | a connected form step's form has no published version — users cannot start it (`FormFlow.Data.Instances.Forms` pins the latest published version) |
  | `:subflow_missing` | error | a connected subflow step points at no flow, or at one that could not be resolved |
  | `:property_missing` | error | a flow's or a form's type requires a property (`FormFlow.Config.Property`'s `:required`) that has no value — the Review type's "Form to review", say |
  | `:related_form_missing` | error | a `:related_form` property names a position the tree no longer has |
  | `:unconnected` | warning | a node no Start reaches; users can never get there |
  | `:dead_end` | warning | a node Start reaches that nothing follows, so End never waits for it |
  | `:no_steps` | warning | Start reaches End with no form or subflow step between them |
  | `:unknown_type` | warning | a flow or form names a type the host's list does not have |
  | `:stale_perspectives` | warning | a flow stores a perspective id its type no longer declares |
  | `:unpublished_changes` | info | a form has a draft whose definition differs from its latest published version |

  "Connected" is the reading `FormFlow.Data.Templates.Flows.connected_tree/1`
  and `FormFlow.Data.Instances.FlowProgress` share: reachable from a Start
  node following relationships forward. Checks on what a step points at —
  its form, its subflow, their types — run for connected steps only. An
  unconnected step is reported once, as unconnected; whatever is behind it
  is not a user's concern until it is wired in, and reporting it too would
  bury the one thing to do.

  ## Levels

  `:error` — a user cannot work the flow as it stands. `:warning` — the
  flow works, but part of it does not take part. `:info` — nothing changes
  for users, but an admin may want to know. See
  `FormFlow.Data.Templates.Flows.Health.Entry`.

  ## Ignoring an entry

  A check cannot know what is fine on purpose — a step left unwired for a
  later phase, a draft kept beside the published version. An admin who
  keeps seeing "5 warnings" stops reading them, and misses the sixth. So an
  entry can be **ignored**: `ignore/3` records it on the root flow, under
  `properties["_health_ignored_entries"]`, with who ignored it and when;
  from then on `check/2` still lists it — marked, in `Entry`'s `:ignored` —
  but it no longer counts toward `level` and `counts`, so the badge says
  what is new. `stop_ignoring/2` removes the record. An entry is matched by
  its `code` and `path`, both stable across saves (the canvas keeps node
  ids), and a record whose entry has gone — the step was wired, or deleted
  — is dropped the next time either function writes.

  The record lives in the flow's `properties`, beside its type and
  perspectives, because that is the flow's own open map and it travels with
  the flow: a `duplicate/2` copies the ignores along with the shape they
  describe — with the source's node ids, which the copy does not have, so
  they match nothing there and are pruned on the copy's first toggle.
  """

  alias FormFlow.Config.Flows.Perspective
  alias FormFlow.Config.Property
  alias FormFlow.Data.Repo
  alias FormFlow.Data.Templates.Flows
  alias FormFlow.Data.Templates.Flows.Health.Entry

  @ignored_key "_health_ignored_entries"
  @empty_counts %{error: 0, warning: 0, info: 0, ignored: 0}

  defstruct [:flow_id, level: :ok, entries: [], counts: @empty_counts, summary: %{}]

  @typedoc """
  `level` is the worst level among the entries not ignored, `:ok` when
  none; `counts` counts those by level, and the ignored ones under
  `:ignored`; `entries` has every entry, worst first, an ignored one in
  its place — ignoring changes what counts, not where it is listed, so
  a list an admin is working down does not reorder under them. `summary` describes the flow
  that was checked, whole tree, for a page to say what the report is of:
  its `label`, how many `steps` (form and subflow nodes), `subflows`, and
  distinct `forms` it has, and the `perspectives` and `form_flow_types`
  (ids; `nil` for a "forms" flow that never chose) its flows name.
  """
  @type t :: %__MODULE__{
          flow_id: Ecto.UUID.t() | nil,
          level: Entry.level() | :ok,
          entries: [Entry.t()],
          counts: %{
            error: non_neg_integer(),
            warning: non_neg_integer(),
            info: non_neg_integer(),
            ignored: non_neg_integer()
          },
          summary: %{
            label: String.t() | nil,
            steps: non_neg_integer(),
            subflows: non_neg_integer(),
            forms: non_neg_integer(),
            perspectives: [String.t()],
            form_flow_types: [String.t() | nil]
          }
        }

  @doc """
  Checks a root flow, by id or as a resolved tree — see the moduledoc.

      FormFlow.Data.Templates.Flows.Health.check(flow.id, form_types: form_types)
      #=> %FormFlow.Data.Templates.Flows.Health{level: :error, entries: [...]}

      flow.id |> Flows.resolve_tree() |> Health.check()

  `nil` for an id no flow has.
  """
  @spec check(Ecto.UUID.t() | map() | nil, keyword()) :: t() | nil
  def check(tree_or_id, opts \\ [])

  def check(nil, _opts), do: nil

  def check(id, opts) when is_binary(id) do
    case Flows.resolve_tree(id) do
      nil -> nil
      tree -> tree |> preload_versions() |> check(opts)
    end
  end

  def check(%{flow: flow} = tree, opts) do
    opts = %{
      flow_types: Keyword.get(opts, :flow_types, FormFlow.Config.Flows.Type.defaults()),
      form_types: Keyword.get(opts, :form_types, FormFlow.Config.Forms.Type.defaults()),
      form_paths: form_paths(tree, [])
    }

    entries =
      tree
      |> flow_entries([], [], opts)
      |> mark_ignored(ignored_records(flow))
      |> Enum.sort_by(&Entry.rank(&1.level))

    open = Enum.reject(entries, & &1.ignored)

    %__MODULE__{
      flow_id: flow.id,
      level: worst(open),
      entries: entries,
      counts:
        @empty_counts
        |> Map.merge(Enum.frequencies_by(open, & &1.level))
        |> Map.put(:ignored, length(entries) - length(open)),
      summary: summary(tree)
    }
  end

  # What the report is of: the tree's steps counted at every level,
  # connected or not — this describes the flow as built, not as reachable
  defp summary(tree) do
    nodes = all_nodes(tree)
    flows = all_flows(tree)

    %{
      label: tree.flow.label,
      steps: Enum.count(nodes, &(kind(&1) in [:form, :subflow])),
      subflows: Enum.count(nodes, &(kind(&1) == :subflow)),
      forms:
        nodes
        |> Enum.filter(&(kind(&1) == :form))
        |> Enum.uniq_by(&(&1.form_id || &1.id))
        |> length(),
      perspectives: flows |> Enum.flat_map(&Perspective.ids/1) |> Enum.uniq(),
      form_flow_types:
        for(%{label: "forms"} = flow <- flows, uniq: true, do: flow.properties["form_flow_type"])
    }
  end

  # Subtrees in the order their steps are stored, not the order of the
  # subflows map's keys, so the summary's lists come out the same every time
  defp all_nodes(nil), do: []

  defp all_nodes(tree) do
    tree.nodes ++ Enum.flat_map(tree.nodes, &all_nodes(tree.subflows[&1.id]))
  end

  defp all_flows(nil), do: []

  defp all_flows(tree) do
    [tree.flow | Enum.flat_map(tree.nodes, &all_flows(tree.subflows[&1.id]))]
  end

  @doc "Whether nothing is left to act on — no entry at any level that is not ignored."
  @spec ok?(t()) :: boolean()
  def ok?(%__MODULE__{entries: entries}), do: Enum.all?(entries, & &1.ignored)

  @doc "The entries not ignored, worst first."
  @spec open(t()) :: [Entry.t()]
  def open(%__MODULE__{entries: entries}), do: Enum.reject(entries, & &1.ignored)

  @doc "The entries an admin has ignored."
  @spec ignored(t()) :: [Entry.t()]
  def ignored(%__MODULE__{entries: entries}), do: Enum.filter(entries, & &1.ignored)

  @doc "The entries not ignored at one level."
  @spec at(t(), Entry.level()) :: [Entry.t()]
  def at(%__MODULE__{} = health, level), do: Enum.filter(open(health), &(&1.level == level))

  defp worst([]), do: :ok
  defp worst([%Entry{level: level} | _rest]), do: level

  # --- ignoring ----------------------------------------------------------------

  @doc """
  Records `entry` as ignored on the root flow `health` was checked, by
  `user_id` (the host's opaque identity, as the instance events carry it)
  and now. Returns the updated root flow. Records for entries the check no
  longer finds are dropped on the way.
  """
  @spec ignore(t(), Entry.t(), String.t() | nil) ::
          {:ok, FormFlow.Data.Templates.Flow.t()} | {:error, Ecto.Changeset.t()}
  def ignore(%__MODULE__{} = health, %Entry{} = entry, user_id) do
    record = %{
      "code" => Atom.to_string(entry.code),
      "path" => entry.path,
      "user_id" => user_id,
      "ignored_at" => DateTime.to_iso8601(DateTime.utc_now())
    }

    write_ignored(health, fn records ->
      Enum.reject(records, &same_entry?(&1, entry)) ++ [record]
    end)
  end

  @doc """
  Removes `entry`'s ignored record from the root flow `health` was checked,
  so it counts again. Returns the updated root flow.
  """
  @spec stop_ignoring(t(), Entry.t()) ::
          {:ok, FormFlow.Data.Templates.Flow.t()} | {:error, Ecto.Changeset.t()}
  def stop_ignoring(%__MODULE__{} = health, %Entry{} = entry) do
    write_ignored(health, fn records -> Enum.reject(records, &same_entry?(&1, entry)) end)
  end

  # The root flow's records, current ones only, through `change`, written
  # back as the flow's properties — Flows.update/2 without contents touches
  # nothing else
  defp write_ignored(health, change) do
    root = Repo.get(FormFlow.Data.Templates.Flow, health.flow_id)

    records =
      root
      |> ignored_records()
      |> Enum.filter(fn record -> Enum.any?(health.entries, &same_entry?(record, &1)) end)
      |> change.()

    properties =
      case records do
        [] -> Map.delete(root.properties, @ignored_key)
        records -> Map.put(root.properties, @ignored_key, records)
      end

    Flows.update(root, %{properties: properties})
  end

  defp ignored_records(%{properties: properties}) do
    case (properties || %{})[@ignored_key] do
      records when is_list(records) -> Enum.filter(records, &is_map/1)
      _none -> []
    end
  end

  defp same_entry?(record, %Entry{} = entry) do
    record["code"] == Atom.to_string(entry.code) and record["path"] == entry.path
  end

  defp mark_ignored(entries, []), do: entries

  defp mark_ignored(entries, records) do
    Enum.map(entries, fn entry ->
      case Enum.find(records, &same_entry?(&1, entry)) do
        nil ->
          entry

        record ->
          %{
            entry
            | ignored: %{user_id: record["user_id"], ignored_at: parse_at(record["ignored_at"])}
          }
      end
    end)
  end

  defp parse_at(at) when is_binary(at) do
    case DateTime.from_iso8601(at) do
      {:ok, datetime, _offset} -> datetime
      _error -> nil
    end
  end

  defp parse_at(_at), do: nil

  # --- loading ---------------------------------------------------------------

  # The tree's nodes carry their form (Flows.get/1 preloads it) but not the
  # form's versions, and whether a form is published is a question about
  # those. One query for every form in the tree, then each node's form is
  # swapped for its loaded copy.
  defp preload_versions(tree) do
    forms =
      tree
      |> collect_forms()
      |> Enum.uniq_by(& &1.id)
      |> Repo.preload(:versions)
      |> Map.new(&{&1.id, &1})

    put_forms(tree, forms)
  end

  defp collect_forms(nil), do: []

  defp collect_forms(tree) do
    own = for %{form: %{id: _id} = form} <- tree.nodes, do: form
    own ++ Enum.flat_map(tree.subflows, fn {_node_id, subtree} -> collect_forms(subtree) end)
  end

  defp put_forms(nil, _forms), do: nil

  defp put_forms(tree, forms) do
    %{
      tree
      | nodes:
          Enum.map(tree.nodes, fn
            %{form: %{id: id}} = node -> %{node | form: Map.fetch!(forms, id)}
            node -> node
          end),
        subflows:
          Map.new(tree.subflows, fn {node_id, subtree} -> {node_id, put_forms(subtree, forms)} end)
    }
  end

  # --- one flow --------------------------------------------------------------

  # `prefix` is the path of the subflow node embedding this flow ([] for the
  # root); `ancestors` the subflow nodes on the way down, for the messages.
  defp flow_entries(tree, prefix, ancestors, opts) do
    scope = scope(tree, prefix, ancestors)

    structure_entries(scope) ++
      flow_type_entries(scope, opts) ++
      Enum.flat_map(connected_nodes(scope), &node_entries(&1, scope, opts))
  end

  defp scope(tree, prefix, ancestors) do
    starts = for node <- tree.nodes, kind(node) == :start, do: node.id
    outgoing = Enum.group_by(tree.relationships, & &1.source_id, & &1.target_id)
    reachable = reachable(starts, outgoing, MapSet.new())

    %{
      tree: tree,
      flow: tree.flow,
      prefix: prefix,
      ancestors: ancestors,
      starts: starts,
      ends: for(node <- tree.nodes, kind(node) == :end, do: node.id),
      outgoing: outgoing,
      reachable: reachable
    }
  end

  defp connected_nodes(scope) do
    Enum.filter(scope.tree.nodes, &MapSet.member?(scope.reachable, &1.id))
  end

  defp structure_entries(scope) do
    end_reached? = Enum.any?(scope.ends, &MapSet.member?(scope.reachable, &1))

    [
      if(scope.starts == [], do: flow_entry(scope, :error, :no_start, "has no Start node")),
      if(scope.ends == [], do: flow_entry(scope, :error, :no_end, "has no End node")),
      if(scope.starts != [] and scope.ends != [] and not end_reached?,
        do: flow_entry(scope, :error, :end_unreachable, "does not connect Start to End")
      ),
      if(end_reached? and not Enum.any?(connected_nodes(scope), &(kind(&1) in [:form, :subflow])),
        do:
          flow_entry(
            scope,
            :warning,
            :no_steps,
            "connects Start straight to End, with no steps between them"
          )
      )
    ]
    |> Enum.reject(&is_nil/1)
    |> Kernel.++(if scope.starts != [], do: unconnected_entries(scope), else: [])
    |> Kernel.++(if end_reached?, do: dead_end_entries(scope), else: [])
  end

  # Without a Start nothing is connected, and the one error says so; naming
  # every node as unconnected on top would bury it
  defp unconnected_entries(scope) do
    for node <- scope.tree.nodes, not MapSet.member?(scope.reachable, node.id) do
      node_entry(node, scope, :warning, :unconnected, "is not connected from Start")
    end
  end

  # A reachable node nothing follows, End aside: a user can work it, but End
  # completes without waiting for it (FlowProgress's AND-join counts
  # predecessors only)
  defp dead_end_entries(scope) do
    for node <- connected_nodes(scope),
        kind(node) != :end,
        not Map.has_key?(scope.outgoing, node.id) do
      node_entry(node, scope, :warning, :dead_end, "leads nowhere — nothing follows it")
    end
  end

  # --- the flow's type -------------------------------------------------------

  # Flow types apply to "forms" flows; a "subflows" flow has none
  defp flow_type_entries(%{flow: %{label: "forms"} = flow} = scope, opts) do
    values = FormFlow.Config.Flows.Type.property_values(flow)

    case stored_type(opts.flow_types, flow.properties["form_flow_type"]) do
      {:unknown, id} ->
        [
          flow_entry(
            scope,
            :warning,
            :unknown_type,
            "uses the flow type “#{id}”, which is not offered"
          )
        ]

      {:ok, type} ->
        property_entries(type.properties, values, opts, fn level, code, text ->
          flow_entry(scope, level, code, text)
        end) ++ perspective_entries(scope, type)
    end
  end

  defp flow_type_entries(_scope, _opts), do: []

  defp perspective_entries(scope, type) do
    case Perspective.stale_ids(scope.flow, type.perspectives) do
      [] ->
        []

      stale ->
        [
          flow_entry(
            scope,
            :warning,
            :stale_perspectives,
            "is for #{quote_all(stale)}, which its type no longer declares"
          )
        ]
    end
  end

  # --- one connected node ----------------------------------------------------

  defp node_entries(node, scope, opts) do
    case kind(node) do
      :form -> form_entries(node, scope, opts)
      :subflow -> subflow_entries(node, scope, opts)
      _start_end_or_other -> []
    end
  end

  defp form_entries(node, scope, opts) do
    case node.form do
      %Ecto.Association.NotLoaded{} ->
        []

      nil ->
        [node_entry(node, scope, :error, :form_missing, "has no form")]

      form ->
        version_entries(node, form, scope) ++ form_type_entries(node, form, scope, opts)
    end
  end

  defp version_entries(node, %{versions: versions}, scope) when is_list(versions) do
    published =
      versions
      |> Enum.filter(&(&1.status == "published"))
      |> Enum.max_by(& &1.version, fn -> nil end)

    cond do
      is_nil(published) ->
        [
          node_entry(
            node,
            scope,
            :error,
            :form_not_published,
            "has no published version — users cannot start it"
          )
        ]

      Enum.any?(versions, &(&1.status == "draft" and &1.definition != published.definition)) ->
        [
          node_entry(
            node,
            scope,
            :info,
            :unpublished_changes,
            "has a draft with changes not yet published"
          )
        ]

      true ->
        []
    end
  end

  # Versions not loaded — a hand-built tree that says nothing about them
  defp version_entries(_node, _form, _scope), do: []

  defp form_type_entries(node, form, scope, opts) do
    values = FormFlow.Config.Forms.Type.property_values(form)

    case stored_type(opts.form_types, (form.properties || %{})["form_type"]) do
      {:unknown, id} ->
        [
          node_entry(
            node,
            scope,
            :warning,
            :unknown_type,
            "uses the form type “#{id}”, which is not offered"
          )
        ]

      {:ok, type} ->
        property_entries(type.properties, values, opts, fn level, code, text ->
          node_entry(node, scope, level, code, text)
        end)
    end
  end

  defp subflow_entries(node, scope, opts) do
    case scope.tree.subflows[node.id] do
      nil ->
        [node_entry(node, scope, :error, :subflow_missing, "has no subflow behind it")]

      subtree ->
        flow_entries(subtree, scope.prefix ++ [node.id], scope.ancestors ++ [node], opts)
    end
  end

  # --- types and properties --------------------------------------------------

  # The type a template stores, resolved against the host's list: the first
  # type for a template that never chose (what every page resolves an unset
  # type to), the named one, or {:unknown, id} when the list has no such type
  defp stored_type(types, nil) do
    case List.first(types) do
      nil -> {:ok, %{properties: [], perspectives: []}}
      type -> {:ok, type}
    end
  end

  defp stored_type(types, id) do
    case Enum.find(types, &(&1.id == id)) do
      nil -> {:unknown, id}
      type -> {:ok, type}
    end
  end

  # `entry` builds the struct with the right subject — the flow or the
  # node — so this can serve both
  defp property_entries(properties, values, opts, entry) do
    Enum.flat_map(properties, fn %Property{} = property ->
      value = values[property.id]

      cond do
        blank?(value) and property.required ->
          [entry.(:error, :property_missing, "needs “#{property.name}” set")]

        blank?(value) ->
          []

        property.type == :related_form and not MapSet.member?(opts.form_paths, split_path(value)) ->
          [
            entry.(
              :error,
              :related_form_missing,
              "points “#{property.name}” at a form that is no longer in this flow"
            )
          ]

        true ->
          []
      end
    end)
  end

  defp blank?(value), do: value in [nil, "", []]

  defp split_path(value) when is_binary(value), do: String.split(value, "/")
  defp split_path(value), do: value

  # Every form position in the tree, as the paths a :related_form value
  # names — connected or not, since the value was picked from what the flow
  # had, and an unconnected form is already reported as such
  defp form_paths(nil, _prefix), do: MapSet.new()

  defp form_paths(tree, prefix) do
    own = for node <- tree.nodes, kind(node) == :form, into: MapSet.new(), do: prefix ++ [node.id]

    Enum.reduce(tree.subflows, own, fn {node_id, subtree}, paths ->
      MapSet.union(paths, form_paths(subtree, prefix ++ [node_id]))
    end)
  end

  # --- building entries -----------------------------------------------------

  # A entry with the flow itself. The subject is the subflows on the way
  # down — "Review does not connect Start to End" — or "This flow" for the
  # root, which the listing already names.
  defp flow_entry(scope, level, code, text) do
    subject =
      case scope.ancestors do
        [] -> "This flow"
        ancestors -> Enum.map_join(ancestors, " / ", &node_label/1)
      end

    message = "#{subject} #{text}"

    %Entry{
      level: level,
      code: code,
      message: message,
      flow_id: scope.flow.id,
      node_id: nil,
      path: scope.prefix
    }
  end

  # A entry with one node, named the way the user-facing pages name a
  # position: "Review / Check pet details has no published version"
  defp node_entry(node, scope, level, code, text) do
    subject = Enum.map_join(scope.ancestors ++ [node], " / ", &node_label/1)

    %Entry{
      level: level,
      code: code,
      message: "“#{subject}” #{text}",
      flow_id: scope.flow.id,
      node_id: node.id,
      path: scope.prefix ++ [node.id]
    }
  end

  defp quote_all(names), do: Enum.map_join(names, ", ", &"“#{&1}”")

  # --- reading nodes ---------------------------------------------------------

  # Structural references first (a saved node always carries them), labels
  # next, and the canvas's own data.kind last — what a node not yet saved
  # has, since labels are derived from it at save
  defp kind(node) do
    cond do
      node.subflow_id -> :subflow
      node.form_id -> :form
      "Subflow" in node.labels -> :subflow
      "Form" in node.labels -> :form
      "Start" in node.labels -> :start
      "End" in node.labels -> :end
      node.properties["type"] == "subflow" -> :subflow
      true -> kind_from_data(get_in(node.properties, ["data", "kind"]))
    end
  end

  defp kind_from_data("start"), do: :start
  defp kind_from_data("form"), do: :form
  defp kind_from_data("end"), do: :end
  defp kind_from_data(_other), do: :other

  defp node_label(node) do
    get_in(node.properties, ["data", "label"]) || List.first(node.labels) || "Untitled"
  end

  # The same forward walk as connected_tree/1: everything Start reaches
  defp reachable([], _outgoing, seen), do: seen

  defp reachable([id | rest], outgoing, seen) do
    if MapSet.member?(seen, id) do
      reachable(rest, outgoing, seen)
    else
      reachable(rest ++ Map.get(outgoing, id, []), outgoing, MapSet.put(seen, id))
    end
  end
end
