defmodule FormFlow.Data.Templates.Flows.Health do
  @moduledoc """
  `FormFlow.Data.Templates.Flows.Health` checks a root flow — the whole
  tree, subflows included — and reports what it finds as a list of
  `FormFlow.Data.Templates.Flows.Health.Entry` structs sorted worst first,
  with the worst level as the one-word answer. A health check, in prose;
  what it lists are **entries**, not problems, because a check reads the
  flow's shape and can be wrong about what is fine on purpose — see
  "Ignoring an entry" below.

  The pages draw it: every flow page carries a badge with the flow's cached
  status (`status/1`), and `/flows/:id/health` lays the whole report out.
  Nothing here writes anything but its own bookkeeping on the root flow —
  the cached status and the ignores — and nothing refuses a save on it: the
  checks describe a flow as it stands, so an admin building one sees what is
  left to do, and a finished flow shows none.

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
  | `:related_form_missing` | error | a `:related_form` property names a position the tree no longer has, or one no Start reaches — either way the property resolves to nothing at runtime (`FormFlow.Config.Forms.Type.related_form/2` looks among the connected positions) |
  | `:related_form_shared` | error | a catalog form — one lineage shared by every step reusing it — has a `:related_form` value, a position in one flow; it can be right in one flow only, and re-picking it from another breaks the first (the form pages refuse the choice; a copied flow arrives with it) |
  | `:unconnected` | warning | a node no Start reaches; users can never get there |
  | `:dead_end` | warning | a node Start reaches that nothing follows, so End never waits for it |
  | `:no_steps` | warning | Start reaches End with no form or subflow step between them |
  | `:unknown_type` | warning | a flow or form names a type the host's list does not have |
  | `:stale_perspectives` | warning | a flow stores a perspective id its type no longer declares |
  | `:unpublished_changes` | info | a form has a draft whose definition differs from its latest published version |

  Each entry carries, besides its one-sentence `message`, a paragraph on
  why the check matters and a sentence on what to do — per code, from
  `FormFlow.Data.Templates.Flows.Health.Entry.explanation/1` and `fix/1` —
  so a page has the words and a host drawing its own has them too.

  "Connected" is the reading `FormFlow.Data.Templates.Flows.connected_tree/1`
  and `FormFlow.Data.Instances.FlowProgress` share: reachable from a Start
  node following relationships forward. Checks on what a step points at —
  its form, its subflow, their types — run for connected steps only. An
  unconnected step is reported once, as unconnected; whatever is behind it
  is not a user's concern until it is wired in, and reporting it too would
  bury the one thing to do.

  The report also counts what it evaluated, in `checks_run`: one per node
  per check that applies to it, one per flow per flow-level check. So
  `checks_run - length(entries)` is how many checks passed — the number a
  page shows beside an empty list, so "nothing to report" is visibly the
  result of looking.

  ## Levels

  `:error` — a user cannot work the flow as it stands. `:warning` — the
  flow works, but part of it does not take part. `:info` — nothing changes
  for users, but an admin may want to know. See
  `FormFlow.Data.Templates.Flows.Health.Entry`.

  Two questions follow, and both have a function so a host's badge answers
  them the way the library's does: `ok?/1` — is **nothing** open, info
  included; and `healthy?/1` — is nothing **wrong**, meaning no open error
  or warning, with `wrong/1` the count of those. The badge draws `healthy?/1`
  (a check, in the info colour when only info entries remain), since a draft
  with unpublished changes is the normal state of a form being worked on and
  should not make a sound flow read as unwell. Both take a report or a
  cached status (`status/1`).

  ## The cached status

  Running the check means loading the whole tree, which a listing of ten
  flows cannot afford per row. So the result is **cached on the root flow**,
  under `properties["_health_metadata"]["status"]`: the `level`, the
  `counts`, the `summary`, `checks_run`, and `checked_at`. `status/1` reads
  it off a flow struct — no query — and that is what the badges on the
  index and the flow pages draw. `refresh/2` recomputes it: the full check,
  written back, once, **at the end of each save** — the flow edit page's
  save, a step's rename, a form's publish or archive or draft, a step
  deleted, a form reused, a copy made — called by the page or the operation
  that owns the whole save, never from inside the context functions a save
  calls many times. A missed caller means a badge that lags, never a page
  that is wrong: the health page runs the check on every visit and writes
  the cache back. A flow never checked has no status, and its badge says so.
  The write touches the `properties` column alone: a check is derived from
  the flow and does not move its `updated_at`, and a caller's own save
  cannot clobber it (`FormFlow.Data.Templates.Flows.update/2` keeps the
  stored `_` keys over whatever map the caller holds).

  The `_` prefix marks the key as the library's own bookkeeping beside the
  admin-set keys in the same map; see `guides/neo4j.md`.

  ## Ignoring an entry

  A check cannot know what is fine on purpose — a step left unwired for a
  later phase, a draft kept beside the published version. An admin who
  keeps seeing "5 warnings" stops reading them, and misses the sixth. So an
  entry can be **ignored**: `ignore/3` records it on the root flow, under
  `properties["_health_metadata"]["ignored_entries"]`, with who ignored it
  and when; from then on `check/2` still lists it — marked, in `Entry`'s
  `:ignored` — but it no longer counts toward `level` and `counts`, so the
  badge says what is new. `stop_ignoring/3` removes the record. An entry is
  matched by its `code` and `path`, both stable across saves (the canvas
  keeps node ids), and a record whose entry has gone — the step was wired,
  or deleted — is dropped the next time `refresh/2` or either toggle
  writes. Both toggles write the status too, from the report they hold, so
  the badge follows without a second check, and each writes an event to the
  flow's log (`FormFlow.Data.Templates.Flow.Event`, `health_ignored` and
  `health_unignored`) in the same transaction: the record is the state, the
  log is who decided it and when.

  The records live in the flow's `properties`, beside its type and
  perspectives, because that is the flow's own open map and it travels with
  the flow: `FormFlow.Data.Templates.Flows.copy/2` carries the ignores along
  with the shape they describe, re-pointed at the copied nodes
  (`for_copy/2`), since the same findings are fine on purpose in a copy.
  """

  import Ecto.Query, only: [from: 2]

  alias FormFlow.Config.Flows.Perspective
  alias FormFlow.Config.Property
  alias FormFlow.Data.Repo
  alias FormFlow.Data.Templates.Flow
  alias FormFlow.Data.Templates.Flows
  alias FormFlow.Data.Templates.Flows.Health.Entry

  @metadata_key "_health_metadata"
  @empty_counts %{error: 0, warning: 0, info: 0, ignored: 0}
  @summary_keys [:label, :steps, :subflows, :forms, :perspectives, :form_flow_types]

  defstruct [
    :flow_id,
    level: :ok,
    entries: [],
    counts: @empty_counts,
    summary: %{},
    checks_run: 0
  ]

  @typedoc """
  `level` is the worst level among the entries not ignored, `:ok` when
  none; `counts` counts those by level, and the ignored ones under
  `:ignored`; `entries` has every entry, worst first, an ignored one in
  its place — ignoring changes what counts, not where it is listed, so
  a list an admin is working down does not reorder under them. `summary`
  describes the flow that was checked, whole tree, for a page to say what
  the report is of: its `label`, how many `steps` (form and subflow nodes),
  `subflows`, and distinct `forms` it has, and the `perspectives` and
  `form_flow_types` (ids; `nil` for a "forms" flow that never chose) its
  flows name. `checks_run` is how many checks were evaluated, entries
  included.
  """
  @type t :: %__MODULE__{
          flow_id: Ecto.UUID.t() | nil,
          level: Entry.level() | :ok,
          entries: [Entry.t()],
          counts: counts(),
          summary: summary(),
          checks_run: non_neg_integer()
        }

  @type counts :: %{
          error: non_neg_integer(),
          warning: non_neg_integer(),
          info: non_neg_integer(),
          ignored: non_neg_integer()
        }

  @type summary :: %{
          label: String.t() | nil,
          steps: non_neg_integer(),
          subflows: non_neg_integer(),
          forms: non_neg_integer(),
          perspectives: [String.t()],
          form_flow_types: [String.t() | nil]
        }

  @typedoc """
  What `status/1` reads off a flow: the report minus its entries, as
  `refresh/2` last cached it, plus when. `nil` for a flow never checked.
  """
  @type status :: %{
          level: Entry.level() | :ok,
          counts: counts(),
          summary: summary(),
          checks_run: non_neg_integer(),
          checked_at: DateTime.t() | nil
        }

  @doc """
  Checks a root flow, by id or as a resolved tree — see the moduledoc.

      FormFlow.Data.Templates.Flows.Health.check(flow.id, form_types: form_types)
      #=> %FormFlow.Data.Templates.Flows.Health{level: :error, entries: [...]}

      flow.id |> Flows.resolve_tree() |> Health.check()

  An owned subflow's id is its root's check: a subflow's health is its
  root's, as its status and history are, so the report — and anything
  `ignore/3` writes from it — lands on the root. `nil` for an id no flow
  has. Reads only; `refresh/2` is the check that writes.
  """
  @spec check(Ecto.UUID.t() | map() | nil, keyword()) :: t() | nil
  def check(tree_or_id, opts \\ [])

  def check(nil, _opts), do: nil

  def check(id, opts) when is_binary(id) do
    case Flows.resolve_tree(id) do
      nil -> nil
      %{flow: %Flow{owner_flow_id: root_id}} when is_binary(root_id) -> check(root_id, opts)
      tree -> tree |> preload_versions() |> check(opts)
    end
  end

  def check(%{flow: flow} = tree, opts) do
    opts = %{
      flow_types: Keyword.get(opts, :flow_types, FormFlow.Config.Flows.Type.defaults()),
      form_types: Keyword.get(opts, :form_types, FormFlow.Config.Forms.Type.defaults()),
      form_paths: form_paths(tree, [], :all),
      connected_form_paths: form_paths(tree, [], :connected)
    }

    # Every check evaluated yields one result: an entry, or :pass
    results = flow_results(tree, [], [], opts)
    entries = for %Entry{} = entry <- results, do: entry

    build(flow.id, entries, length(results), summary(tree), ignored_records(flow))
  end

  # The report from its parts: entries marked against the ignored records,
  # sorted worst first, and counted. The toggles rebuild from the entries
  # they hold and the records as they now stand.
  defp build(flow_id, entries, checks_run, summary, records) do
    entries =
      entries
      |> Enum.map(&%{&1 | ignored: nil})
      |> mark_ignored(records)
      |> Enum.sort_by(&Entry.rank(&1.level))

    open = Enum.reject(entries, & &1.ignored)

    %__MODULE__{
      flow_id: flow_id,
      level: worst(open),
      entries: entries,
      counts:
        @empty_counts
        |> Map.merge(Enum.frequencies_by(open, & &1.level))
        |> Map.put(:ignored, length(entries) - length(open)),
      summary: summary,
      checks_run: checks_run
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
      forms: nodes |> Enum.map(& &1.form_id) |> Enum.reject(&is_nil/1) |> Enum.uniq() |> length(),
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

  @doc """
  How many open entries say something is wrong with the flow: the errors and
  the warnings. Info entries are left out — they describe work in progress,
  not a flow left in a bad state. Takes a report or a cached status.
  """
  @spec wrong(t() | status()) :: non_neg_integer()
  def wrong(%{counts: counts}), do: counts.error + counts.warning

  @doc "Whether nothing is wrong — no open error or warning. Info may remain; see `ok?/1`."
  @spec healthy?(t() | status()) :: boolean()
  def healthy?(%{counts: _counts} = report), do: wrong(report) == 0

  @doc "How many checks passed: those run, less those that produced an entry."
  @spec passing(t()) :: non_neg_integer()
  def passing(%__MODULE__{checks_run: run, entries: entries}), do: run - length(entries)

  defp worst([]), do: :ok
  defp worst([%Entry{level: level} | _rest]), do: level

  # --- the cached status -------------------------------------------------------

  @doc """
  The status `refresh/2` last cached on `flow` — a root flow struct, as the
  index rows and the flow pages already hold one — or `nil` for a flow never
  checked. No query: it reads `properties`. See "The cached status".

      Health.status(flow)
      #=> %{level: :warning, counts: %{error: 0, warning: 2, info: 0, ignored: 1}, ...}
  """
  @spec status(%{properties: map() | nil}) :: status() | nil
  def status(%{properties: _properties} = flow) do
    case metadata(flow)["status"] do
      %{"level" => level} = status when level in ~w(ok error warning info) ->
        counts = status["counts"] || %{}
        summary = status["summary"] || %{}

        %{
          level: String.to_existing_atom(level),
          counts:
            Map.new(@empty_counts, fn {key, _} -> {key, counts[Atom.to_string(key)] || 0} end),
          summary: Map.new(@summary_keys, &{&1, summary[Atom.to_string(&1)]}),
          checks_run: status["checks_run"] || 0,
          checked_at: parse_at(status["checked_at"])
        }

      _none ->
        nil
    end
  end

  @doc """
  Runs the check over the root flow `flow_or_id` belongs to — a root, or an
  owned subflow, whose root is found through `owner_flow_id` — and caches
  the result on the root (`status/1`), dropping ignored records that match
  no entry any more. Returns the report, or `nil` for a flow that no longer
  exists — including one deleted between the check and the write. Takes
  `check/2`'s options.

  Call it **once, at the end of a save**, from the page or the operation
  that owns the whole save — never from inside a function a save calls per
  record. See "The cached status".

      Health.refresh(flow, flow_types: flow_types, form_types: form_types)
  """
  @spec refresh(Flow.t() | Ecto.UUID.t() | nil, keyword()) :: t() | nil
  def refresh(flow_or_id, opts \\ [])

  def refresh(nil, _opts), do: nil

  def refresh(id, opts) when is_binary(id), do: refresh(Repo.get(Flow, id), opts)

  def refresh(%Flow{owner_flow_id: root_id}, opts) when is_binary(root_id),
    do: refresh(Repo.get(Flow, root_id), opts)

  def refresh(%Flow{owner_flow_id: nil} = root, opts) do
    case check(root.id, opts) do
      nil ->
        nil

      health ->
        written =
          write_metadata(root.id, fn metadata ->
            metadata
            |> put_records(current_records(metadata, health))
            |> Map.put("status", encode_status(health))
          end)

        case written do
          {:ok, _root} -> health
          {:error, :not_found} -> nil
        end
    end
  end

  @doc """
  `refresh/2` for every root flow that uses the form lineage `form_id`
  (`FormFlow.Data.Templates.Flows.form_usages/1`) — what a form's pages call
  after a publish, an archive, or a draft saved or deleted, since a catalog
  form's lineage is shared by every flow with a step on it, and an owned
  form's one usage is its own tree.
  """
  @spec refresh_for_form(Ecto.UUID.t(), keyword()) :: :ok
  def refresh_for_form(form_id, opts \\ []) do
    form_id
    |> Flows.form_usages()
    |> Enum.map(& &1.root.id)
    |> Enum.uniq()
    |> Enum.each(&refresh(&1, opts))
  end

  @doc """
  `properties` as a root copy of the flow starts with them
  (`FormFlow.Data.Templates.Flows.copy/2`): without the cached status, which
  describes a check the copy has not had, and with the ignored records
  re-pointed through `plan` — the copy's id for each of the source's node
  ids — since the copy has the source's shape, and what was fine on purpose
  there is fine on purpose here. A record naming a node the plan does not
  know is dropped: it describes a step the copy does not have.
  """
  @spec for_copy(map() | nil, %{optional(Ecto.UUID.t()) => Ecto.UUID.t()}) :: map()
  def for_copy(properties, plan) do
    properties = properties || %{}

    records =
      %{properties: properties}
      |> metadata()
      |> records()
      |> Enum.flat_map(&repoint(&1, plan))

    case records do
      [] -> Map.delete(properties, @metadata_key)
      records -> Map.put(properties, @metadata_key, %{"ignored_entries" => records})
    end
  end

  defp repoint(record, plan) do
    case record["path"] do
      path when is_list(path) ->
        copied = Enum.map(path, &plan[&1])
        if Enum.all?(copied), do: [Map.put(record, "path", copied)], else: []

      _other ->
        []
    end
  end

  @doc """
  `properties` without the health bookkeeping — what an owned copy of a
  flow starts with (`FormFlow.Data.Templates.Flows.copy/2`), since health
  is the root's and the tree it joins has its own.
  """
  @spec forget(map() | nil) :: map()
  def forget(properties), do: Map.delete(properties || %{}, @metadata_key)

  defp encode_status(%__MODULE__{} = health) do
    %{
      "level" => Atom.to_string(health.level),
      "counts" => Map.new(health.counts, fn {key, count} -> {Atom.to_string(key), count} end),
      "summary" => Map.new(health.summary, fn {key, value} -> {Atom.to_string(key), value} end),
      "checks_run" => health.checks_run,
      "checked_at" => DateTime.to_iso8601(DateTime.utc_now())
    }
  end

  # --- ignoring ----------------------------------------------------------------

  @doc """
  Records `entry` as ignored on the root flow `health` was checked, by
  `user_id` (the host's opaque identity, as the instance events carry it)
  and now, caches the status as it now stands, and logs `health_ignored`
  on the flow, all in one transaction. Returns the updated root flow, or
  `{:error, :not_found}` when the flow has been deleted since the check.
  Records for entries the check no longer finds are dropped on the way.
  """
  @spec ignore(t(), Entry.t(), String.t() | nil) :: {:ok, Flow.t()} | {:error, :not_found}
  def ignore(%__MODULE__{} = health, %Entry{} = entry, user_id) do
    record = %{
      "code" => Atom.to_string(entry.code),
      "path" => entry.path,
      "user_id" => user_id,
      "ignored_at" => DateTime.to_iso8601(DateTime.utc_now())
    }

    toggle(
      health,
      fn records -> Enum.reject(records, &same_entry?(&1, entry)) ++ [record] end,
      {"health_ignored", entry, user_id}
    )
  end

  @doc """
  Removes `entry`'s ignored record from the root flow `health` was checked,
  so it counts again, caches the status as it now stands, and logs
  `health_unignored` by `user_id`, all in one transaction. Returns the
  updated root flow, or `{:error, :not_found}` when the flow has been
  deleted since the check.
  """
  @spec stop_ignoring(t(), Entry.t(), String.t() | nil) ::
          {:ok, Flow.t()} | {:error, :not_found}
  def stop_ignoring(%__MODULE__{} = health, %Entry{} = entry, user_id) do
    toggle(
      health,
      fn records -> Enum.reject(records, &same_entry?(&1, entry)) end,
      {"health_unignored", entry, user_id}
    )
  end

  # The root's current records — those the report still finds — through
  # `change`; then the report as it stands with them, as the status. The
  # report already holds what a second check would find. The event goes in
  # the same transaction as the record, so the log never says what the flow
  # does not.
  defp toggle(health, change, {event, entry, user_id}) do
    write_metadata(
      health.flow_id,
      fn metadata ->
        records = metadata |> current_records(health) |> change.()
        health = build(health.flow_id, health.entries, health.checks_run, health.summary, records)

        metadata
        |> put_records(records)
        |> Map.put("status", encode_status(health))
      end,
      fn root -> log(root, event, entry, user_id) end
    )
  end

  defp log(root, event, entry, user_id) do
    attrs = %{
      flow_id: root.id,
      event: event,
      user_id: user_id,
      snapshot: %{
        "code" => Atom.to_string(entry.code),
        "path" => entry.path,
        "subject" => entry.subject
      }
    }

    case Repo.insert(Flow.Event.changeset(%Flow.Event{}, attrs)) do
      {:ok, _event} -> root
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  # Read-modify-write of the one key, the root re-read inside the
  # transaction right before, so an identity save made while a page was open
  # is not undone by the page's toggle (the row is not locked: two toggles in
  # the same instant could still lose one, a race narrow enough to accept).
  # The one column is written, not the changeset: bookkeeping derived from
  # the flow does not move the flow's own `updated_at`. A root deleted
  # underneath is an error, not a crash — the page it came from may be open
  # in another tab.
  defp write_metadata(root_id, change, after_write \\ &Function.identity/1) do
    Repo.transaction(fn ->
      case Repo.get(Flow, root_id) do
        nil ->
          Repo.rollback(:not_found)

        root ->
          root
          |> write_properties(
            Map.put(root.properties || %{}, @metadata_key, change.(metadata(root)))
          )
          |> after_write.()
      end
    end)
  end

  defp write_properties(root, properties) do
    query = from(f in Flow, where: f.id == ^root.id)

    case Repo.update_all(query, set: [properties: properties]) do
      {1, _rows} -> %{root | properties: properties}
      {0, _rows} -> Repo.rollback(:not_found)
    end
  end

  defp metadata(%{properties: properties}) do
    case (properties || %{})[@metadata_key] do
      %{} = metadata -> metadata
      _none -> %{}
    end
  end

  defp records(metadata) do
    case metadata["ignored_entries"] do
      records when is_list(records) -> Enum.filter(records, &is_map/1)
      _none -> []
    end
  end

  # The records that still name an entry the report has
  defp current_records(metadata, health) do
    metadata
    |> records()
    |> Enum.filter(fn record -> Enum.any?(health.entries, &same_entry?(record, &1)) end)
  end

  defp put_records(metadata, []), do: Map.delete(metadata, "ignored_entries")
  defp put_records(metadata, records), do: Map.put(metadata, "ignored_entries", records)

  defp ignored_records(flow), do: flow |> metadata() |> records()

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

  # Every function below returns results: one per check evaluated, an
  # %Entry{} when it found something and :pass when it did not, so the
  # report can count what it looked at as well as what it found.
  #
  # `prefix` is the path of the subflow node embedding this flow ([] for the
  # root); `ancestors` the subflow nodes on the way down, for the messages.
  defp flow_results(tree, prefix, ancestors, opts) do
    scope = scope(tree, prefix, ancestors)

    structure_results(scope) ++
      flow_type_results(scope, opts) ++
      Enum.flat_map(connected_nodes(scope), &node_results(&1, scope, opts))
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

  # Start and End are always looked for; the walk from Start to End only
  # when both exist; what lies on the walk only when it arrives
  defp structure_results(scope) do
    end_reached? = Enum.any?(scope.ends, &MapSet.member?(scope.reachable, &1))

    presence_results(scope) ++
      walk_results(scope, end_reached?) ++
      if(scope.starts != [], do: unconnected_results(scope), else: []) ++
      if(end_reached?, do: dead_end_results(scope), else: [])
  end

  defp presence_results(scope) do
    [
      if(scope.starts == [],
        do: flow_entry(scope, :error, :no_start, "has no Start node"),
        else: :pass
      ),
      if(scope.ends == [], do: flow_entry(scope, :error, :no_end, "has no End node"), else: :pass)
    ]
  end

  defp walk_results(%{starts: []}, _end_reached?), do: []
  defp walk_results(%{ends: []}, _end_reached?), do: []

  defp walk_results(scope, false),
    do: [flow_entry(scope, :error, :end_unreachable, "does not connect Start to End")]

  defp walk_results(scope, true), do: [:pass, steps_result(scope)]

  defp steps_result(scope) do
    if Enum.any?(connected_nodes(scope), &(kind(&1) in [:form, :subflow])),
      do: :pass,
      else:
        flow_entry(
          scope,
          :warning,
          :no_steps,
          "connects Start straight to End, with no steps between them"
        )
  end

  # Without a Start nothing is connected, and the one error says so; naming
  # every node as unconnected on top would bury it
  defp unconnected_results(scope) do
    for node <- scope.tree.nodes do
      if MapSet.member?(scope.reachable, node.id),
        do: :pass,
        else: node_entry(node, scope, :warning, :unconnected, "is not connected from Start")
    end
  end

  # A reachable node nothing follows, End aside: a user can work it, but End
  # completes without waiting for it (FlowProgress's AND-join counts
  # predecessors only)
  defp dead_end_results(scope) do
    for node <- connected_nodes(scope), kind(node) != :end do
      if Map.has_key?(scope.outgoing, node.id),
        do: :pass,
        else: node_entry(node, scope, :warning, :dead_end, "leads nowhere — nothing follows it")
    end
  end

  # --- the flow's type -------------------------------------------------------

  # Flow types apply to "forms" flows; a "subflows" flow has none
  defp flow_type_results(%{flow: %{label: "forms"} = flow} = scope, opts) do
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
        [:pass] ++
          property_results(type.properties, values, opts, fn level, code, text ->
            flow_entry(scope, level, code, text)
          end) ++ perspective_results(scope, type)
    end
  end

  defp flow_type_results(_scope, _opts), do: []

  defp perspective_results(scope, type) do
    case Perspective.stale_ids(scope.flow, type.perspectives) do
      [] ->
        [:pass]

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

  defp node_results(node, scope, opts) do
    case kind(node) do
      :form -> form_results(node, scope, opts)
      :subflow -> subflow_results(node, scope, opts)
      _start_end_or_other -> []
    end
  end

  defp form_results(node, scope, opts) do
    case node.form do
      %Ecto.Association.NotLoaded{} ->
        []

      nil ->
        [node_entry(node, scope, :error, :form_missing, "has no form")]

      form ->
        [:pass] ++
          version_results(node, form, scope) ++ form_type_results(node, form, scope, opts)
    end
  end

  # One check of the form's versions, three outcomes: nothing published, a
  # draft ahead of what is published, or fine
  defp version_results(node, %{versions: versions}, scope) when is_list(versions) do
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
        [:pass]
    end
  end

  # Versions not loaded — a hand-built tree that says nothing about them
  defp version_results(_node, _form, _scope), do: []

  defp form_type_results(node, form, scope, opts) do
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
        shared = shared_form_results(node, form, type, values, scope)

        # The shared entry says why the path is wrong here; the missing
        # entry would say the same thing less well, so it stands down
        properties =
          if shared == [],
            do: type.properties,
            else: Enum.reject(type.properties, &(&1.type == :related_form))

        [:pass] ++
          shared ++
          property_results(properties, values, opts, fn level, code, text ->
            node_entry(node, scope, level, code, text)
          end)
    end
  end

  # A catalog form is one lineage for every step reusing it, with one place
  # for its type's property values, so a `:related_form` value — a position
  # in one flow — can be right in one flow only; every other sees a stale
  # pick, and re-picking there breaks the first. The form pages refuse the
  # choice (`FormFlow.Web.Templates.Forms.Edit`); this catches what arrived
  # otherwise — a copied flow whose step reuses such a form, a host writing
  # properties directly. A type that merely declares the property, unset,
  # points at nothing and is fine.
  defp shared_form_results(node, %{owner_flow_id: nil}, type, values, scope) do
    case Enum.find(type.properties, &(&1.type == :related_form and not blank?(values[&1.id]))) do
      nil ->
        []

      property ->
        [
          node_entry(
            node,
            scope,
            :error,
            :related_form_shared,
            "is a shared form that points “#{property.name}” at a step of one flow"
          )
        ]
    end
  end

  defp shared_form_results(_node, _owned, _type, _values, _scope), do: []

  defp subflow_results(node, scope, opts) do
    case scope.tree.subflows[node.id] do
      nil ->
        [node_entry(node, scope, :error, :subflow_missing, "has no subflow behind it")]

      subtree ->
        [:pass] ++
          flow_results(subtree, scope.prefix ++ [node.id], scope.ancestors ++ [node], opts)
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

  # One check per property the type declares. `entry` builds the struct with
  # the right subject — the flow or the node — so this can serve both
  defp property_results(properties, values, opts, entry) do
    Enum.map(properties, fn %Property{} = property ->
      value = values[property.id]

      cond do
        blank?(value) and property.required ->
          entry.(:error, :property_missing, "needs “#{property.name}” set")

        blank?(value) ->
          :pass

        property.type == :related_form and
            not MapSet.member?(opts.connected_form_paths, split_path(value)) ->
          entry.(:error, :related_form_missing, related_form_text(property, value, opts))

        true ->
          :pass
      end
    end)
  end

  # The runtime resolves a related form among the connected positions only,
  # so a form the tree has but no Start reaches is as absent as one deleted
  # — the message says which, since the fix differs
  defp related_form_text(property, value, opts) do
    if MapSet.member?(opts.form_paths, split_path(value)),
      do: "points “#{property.name}” at a form no Start reaches",
      else: "points “#{property.name}” at a form that is no longer in this flow"
  end

  defp blank?(value), do: value in [nil, "", []]

  defp split_path(value) when is_binary(value), do: String.split(value, "/")
  defp split_path(value), do: value

  # The form positions in the tree, as the paths a :related_form value
  # names: `:all` of them, or the `:connected` ones — those a Start reaches
  # at every level down, which is where the runtime looks
  # (`FormFlow.Config.Forms.Type.related_form/2` over the progress list)
  defp form_paths(nil, _prefix, _which), do: MapSet.new()

  defp form_paths(tree, prefix, which) do
    nodes =
      case which do
        :all -> tree.nodes
        :connected -> connected_nodes(scope(tree, prefix, []))
      end

    own = for node <- nodes, kind(node) == :form, into: MapSet.new(), do: prefix ++ [node.id]

    Enum.reduce(nodes, own, fn node, paths ->
      MapSet.union(paths, form_paths(tree.subflows[node.id], prefix ++ [node.id], which))
    end)
  end

  # --- building entries -----------------------------------------------------

  # An entry with the flow itself. The subject is the subflows on the way
  # down — "Review does not connect Start to End" — or "This flow" for the
  # root, which the listing already names; the struct's subject is nil then.
  defp flow_entry(scope, level, code, text) do
    subject =
      case scope.ancestors do
        [] -> nil
        ancestors -> Enum.map_join(ancestors, " / ", &node_label/1)
      end

    %Entry{
      level: level,
      code: code,
      message: "#{subject || "This flow"} #{text}",
      subject: subject,
      explanation: Entry.explanation(code),
      fix: Entry.fix(code),
      flow_id: scope.flow.id,
      node_id: nil,
      path: scope.prefix
    }
  end

  # An entry with one node, named the way the user-facing pages name a
  # position: "Review / Check pet details has no published version"
  defp node_entry(node, scope, level, code, text) do
    subject = Enum.map_join(scope.ancestors ++ [node], " / ", &node_label/1)

    %Entry{
      level: level,
      code: code,
      message: "“#{subject}” #{text}",
      subject: subject,
      explanation: Entry.explanation(code),
      fix: Entry.fix(code),
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
