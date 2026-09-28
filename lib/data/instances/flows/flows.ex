defmodule FormFlow.Data.Instances.Flows do
  @moduledoc """
  `FormFlow.Data.Instances.Flows` context module for whole-root-flow
  instances - journeys: a `FormFlow.Data.Instances.Flow` row plus every form
  instance filled at a position inside it (see `FormFlow.Data.Instances` for
  the term).

  Deliberately minimal until the runner lands: creation (with its `created`
  event), completion and its other direction (`complete/2`, `reopen/2`),
  the derived-progress helpers, stranded listing, and the one operation
  that must exist concretely from day one - explicit deletion, because
  nothing on the instance side ever cascades.

  **A journey's recorded status follows its forms.** Neither `complete/2`
  nor `reopen/2` waits for a host to notice: after any change
  `FormFlow.Data.Instances.Forms.update_status/4` makes, that function asks
  the derivation whether the root flow's End is reached and calls whichever
  of the two matches. So a journey finishes when its user submits its last
  form, and goes back to in progress if an admin reopens one of them. What
  does **not** move a journey's status is a template edit: a journey reads
  the snapshot of the flow it started on (`FormFlow.Data.Instances.Flow`),
  and only the editor's Move (`move_to_snapshot/3`) puts it on another.
  See `update_next_positions/2` on why its sweep touches only journeys
  still in progress.

  Beside those, the one cache the instance side keeps: **where the flow is
  open** for a journey, written by `update_next_positions/2` onto the
  journey row (`next_path`, `next_node_id`, the two counts, and
  `next_computed_at`) and into `FormFlow.Data.Instances.Flow.NextPosition`,
  one row per open position, and read by a listing through
  `narrow_next_position/2`. The derivation stays the truth
  (`FormFlow.Data.Instances.FlowProgress`); the cache is what a page can
  filter and count by in SQL without opening every journey.
  """

  import Ecto.Query

  alias FormFlow.Config.Flows.Perspective
  alias FormFlow.Context
  alias FormFlow.Data.Instances
  alias FormFlow.Data.Instances.Flow.Event
  alias FormFlow.Data.Instances.Flow.NextPosition
  alias FormFlow.Data.Instances.FlowProgress
  alias FormFlow.Data.Repo
  alias FormFlow.Data.Templates
  alias FormFlow.Data.Templates.Flows.Snapshots

  @doc "Fetches a journey by id, or nil."
  def get(instance_flow_id), do: Repo.get(Instances.Flow, instance_flow_id)

  @doc """
  Journeys, newest first, with `:template_flow` preloaded. `opts[:user_id]` narrows
  to one creator, `opts[:tenant_id]` to one tenant, `opts[:flow]` to
  instances of one or more flow templates (see `narrow_flow/2`), and
  `opts[:status]` to journeys in one status - `"in_progress"` or
  `"completed"`, the journey's own recorded status (`complete/2`), not the flow's -
  query conveniences for "my journeys" listings, not access control: the
  library never enforces visibility.
  """
  def list(opts \\ []) do
    Repo.all(
      from(i in list_query(opts), order_by: [desc: i.inserted_at], preload: [:template_flow])
    )
  end

  @doc """
  The same listing as a composable query: unordered and unpreloaded, so
  callers (like Slab's table in query mode) can layer `order_by`,
  `limit`/`offset`, `Repo.aggregate(:count)`, and their own preloads on top.

  `opts[:user_id]`, `opts[:tenant_id]`, `opts[:flow]`, and `opts[:status]`
  narrow exactly as in `list/1` - and with the same caveat: listing
  conveniences, not access control. This is the building block for the
  `instances` attr of `FormFlow.Web.router/1`: the listing page's own
  default is `list_query(user_id: user_id)`, narrowed to the flows the page
  offers when it offers some in particular. `status: "completed"` is how a
  host that completes journeys asks for a user's finished ones - last year's
  filing, for a form that prefills from it.
  """
  def list_query(opts \\ []) do
    from(i in Instances.Flow)
    |> narrow(:user_id, Keyword.get(opts, :user_id))
    |> narrow_tenant(Keyword.get(opts, :tenant_id))
    |> narrow_flow(Keyword.get(opts, :flow))
    |> narrow(:status, Keyword.get(opts, :status))
  end

  @doc """
  `query` - one over `FormFlow.Data.Instances.Flow` - narrowed to instances
  of one or more flow templates: a `FormFlow.Data.Templates.Flow`, an id, or
  a slug, or a list mixing them (`nil` entries dropped). `nil` leaves the
  query as it is; `[]` matches nothing.

  Slugs are unique per tenant, not globally, so a slug alone matches the
  flow of that slug in every tenant - pair it with `tenant_id:` when that
  matters, as the listing page does.
  """
  def narrow_flow(query, nil), do: query

  def narrow_flow(query, flows) do
    refs = flows |> List.wrap() |> Enum.reject(&is_nil/1)
    struct_ids = for %Templates.Flow{id: id} <- refs, do: id
    {ids, slugs} = refs |> Enum.filter(&is_binary/1) |> Enum.split_with(&uuid?/1)
    ids = struct_ids ++ ids

    templates = from(f in Templates.Flow, where: f.id in ^ids or f.slug in ^slugs, select: f.id)

    from(i in query, where: i.template_flow_id in subquery(templates))
  end

  # Node and flow ids are UUIDs and slugs never are, so one string can only
  # be one of the two - the same distinction the router draws in a URL
  defp uuid?(value), do: match?({:ok, _uuid}, Ecto.UUID.cast(value))

  @doc """
  `query` - one over `FormFlow.Data.Instances.Flow`, such as a host's
  `instances` attr - narrowed to one tenant.
  `nil` leaves it as it is, the whole table being the scope of a host with
  no tenants.
  """
  def narrow_tenant(query, tenant_id), do: narrow(query, :tenant_id, tenant_id)

  @doc """
  `query` - one over `FormFlow.Data.Instances.Flow` - narrowed to instances
  of flows whose status allows `action` (`:start`, `:continue`, or `:see`;
  `FormFlow.Data.Templates.Flow.allows?/2`). The listing page applies
  `:see` on top of whatever it lists, the host's query included, the way it
  applies the tenant: a draft flow's instances are nobody's to see on the
  user-facing side.
  """
  def narrow_allowed(query, action) do
    statuses = Templates.Flow.statuses_allowing(action)
    templates = from(f in Templates.Flow, where: f.status in ^statuses, select: f.id)

    from(i in query, where: i.template_flow_id in subquery(templates))
  end

  @doc """
  `query` - one over `FormFlow.Data.Instances.Flow` - without the instances
  of flows in `status`. The listing page drops pre-release flows this way
  for a user the page does not name among its pre-release users.
  """
  def exclude_status(query, status) when is_binary(status) do
    templates = from(f in Templates.Flow, where: f.status == ^status, select: f.id)

    from(i in query, where: i.template_flow_id not in subquery(templates))
  end

  defp narrow(query, _field, nil), do: query
  defp narrow(query, field, value), do: from(i in query, where: field(i, ^field) == ^value)

  @doc """
  Creates a journey and its `created` event in one transaction.

  The journey's own `user_id` (the owner) and `tenant_id` come from
  `attrs`; the event's `user_id` (the actor of this creation) defaults to
  the owner and can be overridden with `opts[:user_id]`.

  The flow's status is not consulted: whether a user may start this flow
  is the pages' rule (`FormFlow.Data.Templates.Flow.allows?/2`, asked by
  the listing at the click), so that a host's own route - an appeal taken
  after the deadline, a support tool repairing a record - can do what it is
  asked. A route of its own that should honour the status asks `allows?/2`
  first, as the pages do.

  One thing about the status is recorded: a journey started while the flow
  is `pre_release` gets `"form_flow" => %{"pre_release" => true}` in its
  `metadata`, so the pre-release run can be told from the real one once the
  flow opens - by `FormFlow.Data.Instances.Flow.pre_release?/1` on a row, or
  `list_pre_release/1` for a flow's; the marker is inside the map, so there
  is no `where` for it to hand a listing query. `metadata` is otherwise
  the host's map; `"form_flow"` is the one key FormFlow claims in it.

  The journey records its snapshot as it is created: the flow's tree is
  resolved once (`opts[:tree]` when the caller has it), matched against the
  root's snapshots or taken fresh
  (`FormFlow.Data.Templates.Flows.Snapshots.get_or_create/2`), and its id
  set on the row. From then on the journey reads its flow from that
  snapshot. The snapshot is taken **before** the journey's transaction
  opens, in one of its own: on Postgres `get_or_create/2` locks the root
  row, and starts of one flow should queue behind that for the moment the
  snapshot takes, not for the journey's insert, its event, and its first
  refresh too. A start that fails after that leaves a snapshot nobody
  reads - a row, which a duplicate already costs.

  The journey's first open position is written as it is created too
  (`update_next_positions/2`, against that same tree): the positions Start
  reaches, and counts of `0` of the tree's forms - so a journey is in every
  queue it belongs in from its first moment. `opts[:flow_types]` and
  `opts[:callback_data]` reach that refresh.
  """
  def create(attrs \\ %{}, opts \\ []) do
    flow_id = attrs[:template_flow_id] || attrs["template_flow_id"]
    flow = flow_id && Repo.get(Templates.Flow, flow_id)
    changeset = Instances.Flow.changeset(%Instances.Flow{}, mark_pre_release(attrs, flow))

    with {:ok, tree, snapshot} <- snapshot_for_start(flow, changeset, opts) do
      changeset = Ecto.Changeset.put_change(changeset, :template_flow_snapshot_id, snapshot.id)

      Repo.transaction(fn -> insert_and_refresh(changeset, tree, opts) end)
    end
  end

  defp insert_and_refresh(changeset, tree, opts) do
    with {:ok, instance} <- Repo.insert(changeset),
         {:ok, _event} <- insert_event(instance, "created", opts),
         {:ok, instance} <-
           refresh_next_positions(instance, Keyword.put(opts, :tree, tree)) do
      instance
    else
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  # The snapshot a journey starts on, with the tree it was taken from so the
  # first refresh reads the same one. No flow means no tree and no snapshot;
  # the changeset says so on `template_flow_id`, the field the foreign key
  # would have named, so a caller reads one shape whichever check spoke
  defp snapshot_for_start(nil, changeset, _opts) do
    {:error, Ecto.Changeset.add_error(changeset, :template_flow_id, "does not exist")}
  end

  defp snapshot_for_start(%Templates.Flow{} = flow, _changeset, opts) do
    tree = Keyword.get_lazy(opts, :tree, fn -> Templates.Flows.resolve_tree(flow.id) end)

    with {:ok, snapshot} <- Snapshots.get_or_create(flow, tree) do
      {:ok, tree, snapshot}
    end
  end

  @pre_release_marker %{"form_flow" => %{"pre_release" => true}}

  # Merged inside the "form_flow" namespace, not over it: the next key
  # FormFlow puts there must survive a pre-release start
  defp mark_pre_release(attrs, %Templates.Flow{status: "pre_release"}) do
    key = if Map.has_key?(attrs, "template_flow_id"), do: "metadata", else: :metadata

    Map.update(attrs, key, @pre_release_marker, fn metadata ->
      Map.update(metadata || %{}, "form_flow", @pre_release_marker["form_flow"], fn own ->
        Map.merge(own || %{}, @pre_release_marker["form_flow"])
      end)
    end)
  end

  defp mark_pre_release(attrs, _flow), do: attrs

  @doc """
  Note: this function does not check the form flow template's status, only
  the journey. Check that before calling this function.

  Sets `status: "completed"` and `completed_at`, writing a
  `status_changed` event. Both are facts recorded at a moment, never
  recomputed. Completing a completed journey is a no-op. The flow's status
  is not consulted: this is an administrative action on the journey, not a
  user continuing it, and a host closing out a read-only year may well
  call it.

  `FormFlow.Data.Instances.Forms.update_status/4` calls this itself, after
  any change it makes, when the derivation says the root flow's End is
  reached - so an ordinary journey finishes when its user submits its last
  form, and no host has to watch for it. `reopen/2` is the other direction
  of the same rule. A host calls this directly for the administrative case
  above.

  The call refreshes the journey's open positions in the same transaction
  (`update_next_positions/2`): a completed journey has none, whatever its
  forms say, so it leaves every queue. `opts[:flow_types]` and
  `opts[:callback_data]` reach the refresh as they do from `create/2`, and
  so does `opts[:tree]` when the caller has the journey's tree in hand.
  """
  def complete(instance, opts \\ [])

  def complete(%Instances.Flow{status: "completed"} = instance, _opts), do: {:ok, instance}

  def complete(%Instances.Flow{} = instance, opts) do
    Repo.transaction(fn ->
      changes = %{status: "completed", completed_at: DateTime.utc_now()}

      # The status is written before the refresh, not after: the refresh
      # reads it to decide there are no open positions (see
      # `derive_next_positions/4`), which is what empties the queues
      with {:ok, completed} <- Repo.update(Ecto.Changeset.change(instance, changes)),
           {:ok, _event} <- insert_event(completed, "status_changed", "completed", opts),
           {:ok, completed} <- refresh_next_positions(completed, opts) do
        completed
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Note: this function does not check the form flow template's status, only
  the journey. Check that before calling this function.

  `complete/2` run backwards: `status` back to `"in_progress"`,
  `completed_at` cleared, a `status_changed` event written, and the
  journey's open positions refreshed - which now fills rather than
  empties, so the journey rejoins every queue it left. Reopening an
  in-progress journey is a no-op. The journey keeps its snapshot: the
  editor's Move is the only thing that changes one.

  Nothing else is cleared: the trail holds the completion and the reopen
  as separate rows, with their times and their users, and holds every
  earlier pair too - which is why there is no `reopened_at` column. A
  column could say when, once; the trail says how many times.

  `FormFlow.Data.Instances.Forms.update_status/4` calls this itself when a
  change it made leaves a completed journey's flow unfinished - an admin
  reopening one form of a finished journey, most often. A host calls it
  directly to take back a completion.

  `opts` are `complete/2`'s: `:tree`, `:flow_types`, `:callback_data`,
  and `:snapshot` for the event's free-form map.
  """
  def reopen(instance, opts \\ [])

  def reopen(%Instances.Flow{status: "in_progress"} = instance, _opts), do: {:ok, instance}

  def reopen(%Instances.Flow{} = instance, opts) do
    Repo.transaction(fn ->
      changes = %{status: "in_progress", completed_at: nil}

      with {:ok, reopened} <- Repo.update(Ecto.Changeset.change(instance, changes)),
           {:ok, _event} <- insert_event(reopened, "status_changed", "in_progress", opts),
           {:ok, reopened} <- refresh_next_positions(reopened, opts) do
        reopened
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  # The refresh a write of this module runs after itself
  defp refresh_next_positions(journey, opts) do
    update_next_positions(journey, Keyword.take(opts, [:tree, :flow_types, :callback_data]))
  end

  @doc """
  Derived traversal state for a journey - `%{path => status}` from the
  journey's snapshot tree and its form instances. Never persisted; see
  `FormFlow.Data.Instances.FlowProgress`.
  """
  def progress(%Instances.Flow{} = instance) do
    FlowProgress.derive(Snapshots.tree(instance), form_instances(instance))
  end

  @doc """
  The derivation-side completion answer - distinct from the recorded
  `status`, which is a fact at a moment. The two may diverge after a
  journey is moved to a new snapshot; hosts should ask the question they
  mean.
  """
  def complete?(%Instances.Flow{} = instance) do
    FlowProgress.complete?(Snapshots.tree(instance), form_instances(instance))
  end

  @doc """
  The position a user should go to next - the first available (or already
  in-progress) form position in flow order, descending into subflows - or
  nil when nothing is actionable. This is the after-submit redirect.
  """
  def next_path_position(%Instances.Flow{} = instance) do
    FlowProgress.next_path_position(Snapshots.tree(instance), form_instances(instance))
  end

  @doc """
  Writes where the flow is open for a journey - the cache
  `FormFlow.Data.Instances.Flow` and `FormFlow.Data.Instances.Flow.NextPosition`
  hold - from a fresh derivation: every form position the flow lets a user
  work now, in flow order. Plural, because it writes every such position,
  not one.

  Given a `FormFlow.Data.Instances.Flow`, one journey; returns
  `{:ok, journey}` with the columns as written. Given a
  `FormFlow.Data.Templates.Flow`, every open journey of that root
  (`status == "in_progress"`; a completed journey's positions are none and
  its counts final); returns `{:ok, count}` of journeys rewritten. The
  flow may be a subflow; its root is found through `owner_flow_id`, so no
  caller has to remember which it holds. It runs in chunks of a few
  hundred journeys, each chunk against the tree of the snapshot those
  journeys read, reading only narrow form instance rows; a host with a
  job runner may call it from a job, and a bulk write that wants one
  sweep rather than one refresh per row calls it once at the end.

  A position is open when the flow's order rule says so at every level:
  the form's own "forms" flow type says the form is editable
  (`c:FormFlow.Config.Flows.Type.editable?/2` - the flow's order rule, which
  for the library's in-order types is `FlowProgress.actionable?/1` and for
  its any-order types is "not yet completed"), and every "subflows" flow
  above it says the step holding it may be entered
  (`c:FormFlow.Config.Flows.Type.enterable?/2`). The types are asked with
  **no viewer** in the context - no `user_id`, no `tenant_id`, no
  `perspectives`; everything the flow itself carries, its own
  `flow_perspectives` included, is filled in as the pages fill it - and
  `visible?/2` is never asked: whose position a node is stays a read-time
  question (`narrow_next_position/2`), so nothing here holds a perspective
  and an admin adding one moves nothing. The journey's `next_path` is the
  first open position; the table gets a row for each.

  `completed_forms` counts the tree's form positions whose instance is
  completed and `forms_total` counts them all - the whole tree, every
  perspective's forms included.

  `opts`:

    * `:tree` - the journey's tree (`FormFlow.Data.Templates.Flows.Snapshots.tree/1`),
      when the caller has it; loaded otherwise
    * `:flow_types` - the host's `FormFlow.Config.Flows.Type` list, the
      pages' `flow_types` attr; `FormFlow.Config.Flows.Type.defaults/0`
      when absent - which is right for a host that added no type, and
      wrong for one that did, so a host's own callers pass theirs
    * `:callback_data` - handed to the type callbacks; `%{}` when absent

  Only the journey's active form instances are read, and only their
  `id`, `path`, `status`, and `superseded_at` - never `data`. The journey
  row and the child table's rows are written in one transaction, so the
  two cannot disagree. `FormFlow.Data.Instances.Forms.update_status/4`,
  `create/2`, `complete/2`, and `reopen/2` call this themselves after every
  change they make, so a page never has to, and there is no way to ask them
  not to. The `Templates.Flow` clause is the sweep: every `in_progress`
  journey of the root, each against the tree of its own snapshot - the
  journeys are grouped by `template_flow_snapshot_id` and one tree serves
  each group - so `opts[:tree]` is the journey clause's alone. The editor's
  Move calls the sweep after pointing every journey at the new snapshot
  (`move_to_snapshot/3`), and the form template pages call it, through
  `FormFlow.Data.Templates.Forms.refresh_next_positions/2`, after a publish
  that reopened submitted forms.
  """
  def update_next_positions(journey_or_flow, opts \\ [])

  def update_next_positions(%Instances.Flow{} = journey, opts) do
    started_at = DateTime.utc_now()

    tree = Keyword.get_lazy(opts, :tree, fn -> Snapshots.tree(journey) end)
    instances = narrow_form_instances(journey)
    derived = derive_next_positions(tree, instances, journey, opts)

    Repo.transaction(fn ->
      {:ok, journey} = write_next_positions(journey, derived, started_at)
      journey
    end)
  end

  # A few hundred journeys per chunk: one read of their form instances,
  # one transaction of writes
  @sweep_chunk 200

  # The sweep: every open journey of the root, grouped by the snapshot it
  # reads, each group in chunks against that snapshot's tree. Per chunk one
  # read of the form instances, one UPDATE per journey (each needs its own
  # values - there is no single value for `update_all` to set), one DELETE
  # and one insert_all for the child table, in one transaction. The UPDATE
  # per journey is the floor: one round trip per open journey, cheap on
  # SQLite and not on Postgres over a network - see the plan's §5.4 for the
  # measurement.
  def update_next_positions(%Templates.Flow{} = flow, opts) do
    started_at = DateTime.utc_now()
    root_id = flow.owner_flow_id || flow.id

    # `in_progress` only, and that is load-bearing rather than a saving: it
    # is what leaves a completed journey's `completed_forms` and
    # `forms_total` where completion left them. A journey that finished
    # 50 of 50 forms reads 50 of 50 forever, on a listing as on its own
    # page, whatever the template gains afterwards.
    from(i in Instances.Flow,
      where: i.template_flow_id == ^root_id and i.status == "in_progress",
      order_by: [asc: i.inserted_at, asc: i.id]
    )
    |> Repo.all()
    |> Enum.group_by(& &1.template_flow_snapshot_id)
    |> Enum.reduce_while({:ok, 0}, fn {snapshot_id, journeys}, {:ok, count} ->
      case sweep_group(journeys, Snapshots.tree(snapshot_id), opts, started_at) do
        :ok -> {:cont, {:ok, count + length(journeys)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp sweep_group(journeys, tree, opts, started_at) do
    journeys
    |> Enum.chunk_every(@sweep_chunk)
    |> Enum.reduce_while(:ok, fn chunk, :ok ->
      case sweep_chunk(chunk, tree, opts, started_at) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp sweep_chunk(journeys, tree, opts, started_at) do
    ids = Enum.map(journeys, & &1.id)

    instances_by_journey =
      from(f in Instances.Form,
        where: f.instance_flow_id in ^ids and is_nil(f.superseded_at),
        select: %Instances.Form{
          id: f.id,
          instance_flow_id: f.instance_flow_id,
          path: f.path,
          status: f.status
        }
      )
      |> Repo.all()
      |> Enum.group_by(& &1.instance_flow_id)

    derived =
      for journey <- journeys do
        instances = Map.get(instances_by_journey, journey.id, [])
        {journey, derive_next_positions(tree, instances, journey, opts)}
      end

    Repo.transaction(fn -> write_chunk(derived, started_at) end)
    |> case do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # The journey rows are one guarded UPDATE each - the guard is what decides
  # whether this run still owns the journey (see `update_journey_columns/3`) -
  # and only the journeys it won have their table rows replaced. The child
  # table's side then batches: one DELETE for the winners, one insert_all of
  # every new row. Rows nothing points at, holding nothing the sweep owns.
  defp write_chunk(derived, started_at) do
    won =
      for {journey, d} <- derived, update_journey_columns(journey, d, started_at) == :written do
        {journey, d}
      end

    ids = Enum.map(won, fn {journey, _d} -> journey.id end)

    if ids != [] do
      Repo.delete_all(from(p in NextPosition, where: p.instance_flow_id in ^ids))

      rows =
        Enum.flat_map(won, fn {journey, d} -> next_position_rows(journey, d, started_at) end)

      if rows != [], do: Repo.insert_all(NextPosition, rows)
    end

    :ok
  end

  # The form instance columns the derivation reads, and no answers: a
  # journey of eighty forms is eighty narrow rows, not eighty maps of data
  defp narrow_form_instances(%Instances.Flow{id: id}) do
    Repo.all(
      from(f in Instances.Form,
        where: f.instance_flow_id == ^id and is_nil(f.superseded_at),
        select: %Instances.Form{id: f.id, path: f.path, status: f.status}
      )
    )
  end

  # What the refresh writes: `next_path` is the first open position and
  # `open_paths` every one of them, in flow order; a completed journey has
  # neither (see `complete/2`)
  defp derive_next_positions(tree, instances, %Instances.Flow{} = journey, opts) do
    # One walk of the tree, two views of it: `forms/2` and `subflows/2` each
    # derive from scratch, and the sweep runs this once per journey
    statuses = FlowProgress.derive(tree, instances)
    forms = FlowProgress.forms(tree, instances, statuses)
    steps = FlowProgress.subflows(tree, instances, statuses)
    flow_types = Keyword.get(opts, :flow_types) || FormFlow.Config.Flows.Type.defaults()
    callback_data = Keyword.get(opts, :callback_data) || %{}

    # A completed journey has no open position, whatever its forms say.
    # This branch is also the only "clear the cache" path there is: the
    # write below turns `[]` into a null `next_path` and a delete of the
    # child rows, so completing a journey empties its queues by running the
    # ordinary refresh against a row that now says `completed` - which is
    # why `complete/2` writes the status first.
    open_paths =
      if journey.status == "completed" do
        []
      else
        for form <- forms,
            open?(form, forms, steps, tree, journey, flow_types, callback_data),
            do: form.path
      end

    %{
      next_path: List.first(open_paths),
      open_paths: open_paths,
      completed_forms: Enum.count(forms, &(&1.status == :completed)),
      forms_total: length(forms)
    }
  end

  # The flow's order rule at every level, with no viewer asked about: each
  # step above the form may be entered, and the form itself may be edited
  #
  # The context is the one the flow instance's page builds for the same
  # form (`FormFlow.Web.Instances.Flows.Shared`) less the viewer's three
  # fields: `flow_perspectives`, the flow's own data, is filled in so a
  # type reading it answers the same here and there.
  defp open?(form, forms, steps, tree, journey, flow_types, callback_data) do
    type = FormFlow.Config.Flows.Type.for_flow(flow_types, form.flow)

    context = %Context{
      flow: tree.flow,
      subflow: form.flow,
      subflow_node: List.last(form.ancestors),
      form_node: form.node,
      flow_type_property_values: FormFlow.Config.Flows.Type.property_values(form.flow),
      flow_perspectives: Perspective.for_flow(form.flow, type.perspectives),
      flow_instance: journey,
      form_progress: form,
      flow_progress: FlowProgress.forms_in_flow(forms, form.path),
      flow_instance_progress: forms,
      flow_instance_subflows: steps
    }

    steps_enterable?(context, form, steps, flow_types, callback_data) and
      type.module.editable?(context, callback_data)
  end

  defp steps_enterable?(context, form, steps, flow_types, callback_data) do
    Enum.all?(1..length(form.ancestors)//1, fn depth ->
      case FlowProgress.find_subflow(steps, Enum.take(form.path, depth)) do
        nil ->
          false

        step ->
          step_context = %{
            context
            | subflow: step.flow,
              subflow_node: step.node,
              subflow_progress: step,
              complex_progress: FlowProgress.subflows_in_flow(steps, step.path),
              flow_type_property_values: FormFlow.Config.Flows.Type.property_values(step.flow)
          }

          FormFlow.Config.Flows.Type.for_flow(flow_types, step.flow).module.enterable?(
            step_context,
            callback_data
          )
      end
    end)
  end

  # The journey's five columns and its rows in the child table, replaced
  # whole
  defp write_next_positions(%Instances.Flow{} = journey, derived, started_at) do
    case update_journey_columns(journey, derived, started_at) do
      :written ->
        Repo.delete_all(from(p in NextPosition, where: p.instance_flow_id == ^journey.id))

        rows = next_position_rows(journey, derived, started_at)
        if rows != [], do: Repo.insert_all(NextPosition, rows)

        {:ok, journey_with(journey, derived, started_at)}

      :skipped ->
        {:ok, journey}
    end
  end

  # One row per open position. `node_id` is the path's last segment, put
  # here and nowhere else - the two are one fact, and this is the only
  # writer of the table. The database's `null: false` and the unique
  # `(instance_flow_id, path)` index are the guards.
  defp next_position_rows(%Instances.Flow{} = journey, derived, now) do
    for path <- derived.open_paths do
      %{
        id: Ecto.UUID.generate(),
        instance_flow_id: journey.id,
        path: path,
        node_id: List.last(path),
        tenant_id: journey.tenant_id,
        inserted_at: now,
        updated_at: now
      }
    end
  end

  # The columns are set on the row by id rather than through a changeset of
  # the struct in hand: a caller's struct may be older than the row (a page
  # holds the journey it loaded while its forms move), and a changeset
  # compares against the struct, skipping a column whose new value the
  # stale struct happens to hold already. `updated_at` is left alone - it
  # is when the journey itself changed, not when its cache did.
  #
  # `started_at` is set once per run of `update_next_positions/2`, before
  # it reads anything, and the `where` refuses a row a *newer* run already
  # wrote. That is what makes two overlapping runs safe: a slow sweep of the
  # tree as it was cannot land its answer on top of a later one. Without it
  # the loser's write arrives last in wall clock, wins, and leaves a stale
  # answer carrying a fresh `next_computed_at` - a wrong row that
  # `next_positions_stale?/1` then calls fresh, which nothing repairs.
  # Last run *started* wins, not last finished. `:skipped` says another run
  # owns the journey, which is a correct outcome and not an error; a row
  # that has gone is skipped the same way, since deletion is the only other
  # way to match nothing and a deleted journey wants no cache.
  defp update_journey_columns(%Instances.Flow{} = journey, derived, started_at) do
    query =
      from(i in Instances.Flow,
        where:
          i.id == ^journey.id and
            (is_nil(i.next_computed_at) or i.next_computed_at < ^started_at)
      )

    case Repo.update_all(query, set: changes_for(derived, started_at)) do
      {0, _} -> :skipped
      {_written, _} -> :written
    end
  end

  defp changes_for(derived, started_at) do
    [
      next_path: derived.next_path,
      next_node_id: derived.next_path && List.last(derived.next_path),
      completed_forms: derived.completed_forms,
      forms_total: derived.forms_total,
      next_computed_at: started_at
    ]
  end

  # The struct as the row now reads, for the caller that holds it
  defp journey_with(%Instances.Flow{} = journey, derived, started_at),
    do: struct(journey, changes_for(derived, started_at))

  @doc """
  Whether a journey's cached open positions may be out of date: no refresh
  has reached it (`next_computed_at` nil). A journey reads a frozen tree,
  so nothing moves under its cache but a move to a new snapshot - and
  `move_to_snapshot/3` clears `next_computed_at` before it sweeps, so a
  moved journey whose sweep did not finish reads stale here: a listing
  draws its cached value with a quiet mark, and the flow instance's page,
  which derives live anyway, rewrites it on open (read-repair).

  **A completed journey is never stale.** Its cache is not behind, it is
  final: the last refresh was its completion, the sweep takes only journeys
  still in progress, and `completed_forms` / `forms_total` are the counts
  as of the moment it finished (`FormFlow.Data.Instances.Flow`'s
  moduledoc). Answering `true` for one would invite the two callers to
  undo exactly that. This clause is where that rule is kept for both of
  them, and for any caller after them.
  """
  def next_positions_stale?(%Instances.Flow{status: "completed"}), do: false
  def next_positions_stale?(%Instances.Flow{next_computed_at: nil}), do: true
  def next_positions_stale?(%Instances.Flow{}), do: false

  @doc """
  `query` - one over `FormFlow.Data.Instances.Flow` - narrowed to journeys
  whose flow is open at one of the nodes in `node_ids`: a row in
  `FormFlow.Data.Instances.Flow.NextPosition` whose `node_id` is among
  them. Written as `id in (subquery)` over the child table rather than a
  join, so a journey open at three of the nodes is one row and Slab's
  count needs no `distinct`; and rather than a correlated `exists`, so it
  names no binding and can be stacked twice or on a host's query that
  names its own.

  `tenant_id`, when given, filters the child table's own copy of the
  tenant too, so the `(tenant_id, node_id)` index drives the subquery
  and the cost follows the journeys that match, not the journeys of the
  tenant. The listing page passes the router's; `nil` - a host with no
  tenants - drives off the bare `node_id` index instead.

  Which nodes those are is the caller's business: a reviews page asks the
  flow type's `visible?/2` for every form node of its trees and passes the
  reviewer's, so the table holds no perspective and this helper names none
  (`FormFlow.Web.Instances.Flows.Index`). `[]` matches nothing.
  """
  def narrow_next_position(query, node_ids, tenant_id \\ nil) when is_list(node_ids) do
    open_at =
      from(p in NextPosition, where: p.node_id in ^node_ids, select: p.instance_flow_id)
      |> narrow_position_tenant(tenant_id)

    from(i in query, where: i.id in subquery(open_at))
  end

  defp narrow_position_tenant(query, nil), do: query

  defp narrow_position_tenant(query, tenant_id),
    do: from(p in query, where: p.tenant_id == ^tenant_id)

  @doc """
  The journey's stranded form instances: active (not superseded) instances
  whose `path` matches no position in the journey's tree. A journey reads
  a frozen tree, so this is empty until a move (`move_to_snapshot/3`)
  puts it on a snapshot without a step it had started.

  `opts[:tree]` is the journey's tree and `opts[:form_instances]` its form
  instances, for a caller that has already loaded them - the flow instance
  pages have both in hand - so neither is read again. Either one left out
  is loaded here.
  """
  def list_stranded(%Instances.Flow{} = instance, opts \\ []) do
    instances = Keyword.get_lazy(opts, :form_instances, fn -> form_instances(instance) end)

    tree = Keyword.get_lazy(opts, :tree, fn -> Snapshots.tree(instance) end)
    statuses = FlowProgress.derive(tree, instances)

    stranded_paths =
      for {path, :stranded} <- statuses, into: MapSet.new() do
        path
      end

    Enum.filter(instances, fn form_instance ->
      is_nil(form_instance.superseded_at) and MapSet.member?(stranded_paths, form_instance.path)
    end)
  end

  @doc """
  Moves every `in_progress` journey of `root` to `snapshot` - the editor's
  Move, after a save (`FormFlow.Web.Templates.Flows.Edit`). Each journey
  not already on it has `template_flow_snapshot_id` set to the snapshot's
  and `next_computed_at` cleared, and a `moved` event written with the
  snapshot numbers it left and reached; then where every journey of the
  root stands is recomputed against its new tree (`update_next_positions/2`
  on the root). Completed journeys are never moved: the tree a journey
  finished on is the tree it reads forever (`FormFlow.Data.Instances.Flow`).

  Clearing `next_computed_at` first is what keeps a moved journey honest
  when the sweep does not finish: it reads as never refreshed
  (`next_positions_stale?/1`), the listing marks it, and its page repairs
  it on open. The move and its events are one transaction; the sweep runs
  after it, as the publish sweep does, and its failure is returned.

  Returns `{:ok, moved}` - how many journeys moved - or the sweep's
  `{:error, reason}`. `opts` are `update_next_positions/2`'s
  (`:flow_types`, `:callback_data`), and `:user_id` for the events. The
  snapshot must be the root's own; another root's does not match.
  """
  def move_to_snapshot(
        %Templates.Flow{id: root_id} = root,
        %Templates.Flow.Snapshot{template_flow_id: root_id} = snapshot,
        opts \\ []
      ) do
    moved =
      Repo.transaction(fn ->
        journeys =
          Repo.all(
            from(i in Instances.Flow,
              where:
                i.template_flow_id == ^root.id and i.status == "in_progress" and
                  i.template_flow_snapshot_id != ^snapshot.id
            )
          )

        numbers = Map.new(Snapshots.list(root), &{&1.id, &1.number})

        Enum.each(journeys, &insert_move_event(&1, snapshot, numbers, opts))

        ids = Enum.map(journeys, & &1.id)

        Repo.update_all(from(i in Instances.Flow, where: i.id in ^ids),
          set: [
            template_flow_snapshot_id: snapshot.id,
            next_computed_at: nil,
            updated_at: DateTime.utc_now()
          ]
        )

        length(ids)
      end)

    with {:ok, moved} <- moved,
         {:ok, _swept} <-
           update_next_positions(root, Keyword.take(opts, [:flow_types, :callback_data])) do
      {:ok, moved}
    end
  end

  defp insert_move_event(journey, snapshot, numbers, opts) do
    snapshot_numbers = %{
      "from_snapshot" => numbers[journey.template_flow_snapshot_id],
      "to_snapshot" => snapshot.number
    }

    case insert_event(journey, "moved", snapshot_numbers, opts) do
      {:ok, _event} -> :ok
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  @doc """
  Deletes a journey, its event trail, its attached form instances, and its
  open positions, deliberately and in order: journey events first, then
  each form instance through `FormFlow.Data.Instances.Forms.delete_instance/2`
  (its events first - the `restrict` FKs forbid any other order), then the
  rows of `FormFlow.Data.Instances.Flow.NextPosition`, then the journey
  row. This is the only deletion path - there is no cascade.

  The copies a review's events hold of another instance's answers are not
  redacted along the way (`redact: false`): every copy a journey's instances
  made lives in that journey, so its deletion takes them all with it.
  """
  def delete_instance(%Instances.Flow{} = instance, opts \\ []) do
    Repo.transaction(fn ->
      Repo.delete_all(from(e in Event, where: e.instance_flow_id == ^instance.id))

      instance
      |> form_instances()
      |> Enum.each(&delete_form_instance!(&1, Keyword.put(opts, :redact, false)))

      Repo.delete_all(from(p in NextPosition, where: p.instance_flow_id == ^instance.id))

      case Repo.delete(instance) do
        {:ok, deleted} -> deleted
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  The journeys of a root flow started while it was `pre_release`
  (`FormFlow.Data.Instances.Flow.pre_release?/1`), oldest first - the trial
  run the status dialog offers to delete when the flow moves on. The marker
  sits inside the `metadata` map, so the journeys of the flow are read and
  filtered here rather than in a JSON query the two databases would spell
  differently; a flow's pre-release run is small.
  """
  def list_pre_release(%Templates.Flow{id: flow_id}) do
    Repo.all(
      from(i in Instances.Flow,
        where: i.template_flow_id == ^flow_id,
        order_by: [asc: i.inserted_at]
      )
    )
    |> Enum.filter(&Instances.Flow.pre_release?/1)
  end

  @doc """
  Deletes every journey of `flow` started while it was `pre_release`
  (`list_pre_release/1`), each through `delete_instance/2`, and writes one
  `pre_release_instances_deleted` event on the flow's own log
  (`FormFlow.Data.Templates.Flow.Event`) with the `"count"` and
  `opts[:user_id]`, all in one transaction - so the trial run an admin
  cleared away is a recorded decision, not rows that went missing. Returns
  `{:ok, count}`; with nothing to delete, `{:ok, 0}` and no event. The
  flow's status is not consulted: this is the admin's call, made from the
  status dialog as the flow leaves Pre-release.
  """
  def delete_pre_release(%Templates.Flow{} = flow, opts \\ []) do
    Repo.transaction(fn -> delete_journeys(flow, list_pre_release(flow), opts) end)
  end

  # Nothing marked is nothing to record
  defp delete_journeys(_flow, [], _opts), do: 0

  # The snapshots the trial run alone read go with it: a snapshot nobody
  # reads is a row nobody reads, and this is the one moment the library
  # knows a batch of readers is gone (`Snapshots.delete_unreferenced/1`)
  defp delete_journeys(flow, journeys, opts) do
    Enum.each(journeys, &delete_journey!(&1, opts))
    Snapshots.delete_unreferenced(flow)

    attrs = %{
      flow_id: flow.id,
      event: "pre_release_instances_deleted",
      snapshot: %{"count" => length(journeys)},
      user_id: Keyword.get(opts, :user_id)
    }

    case Repo.insert(Templates.Flow.Event.changeset(%Templates.Flow.Event{}, attrs)) do
      {:ok, _event} -> length(journeys)
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp delete_journey!(journey, opts) do
    case delete_instance(journey, opts) do
      {:ok, _deleted} -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  @doc "All of a journey's form instances, superseded ones included."
  def form_instances(%Instances.Flow{} = instance) do
    Repo.all(from(f in Instances.Form, where: f.instance_flow_id == ^instance.id))
  end

  @doc """
  Everything that has happened in a journey, oldest first: its own events
  (`FormFlow.Data.Instances.Flow.Event` - created, status_changed,
  reconciled) and every form instance's
  (`FormFlow.Data.Instances.Form.Event`), superseded instances included,
  merged by `inserted_at` then `id`. Each entry is `%{event: event,
  form_instance: form_instance}`, with `form_instance` nil for the
  journey's own.

  Two queries, whatever the count of forms: the trail is read whole, so a
  page listing it or deriving a perspective status from it asks once.
  """
  @spec list_events(Instances.Flow.t()) :: [
          %{event: Event.t() | Instances.Form.Event.t(), form_instance: Instances.Form.t() | nil}
        ]
  def list_events(%Instances.Flow{id: id}) do
    own =
      from(e in Event, where: e.instance_flow_id == ^id)
      |> Repo.all()
      |> Enum.map(&%{event: &1, form_instance: nil})

    forms =
      from(e in Instances.Form.Event,
        join: f in Instances.Form,
        on: e.instance_form_id == f.id,
        where: f.instance_flow_id == ^id,
        select: {e, f}
      )
      |> Repo.all()
      |> Enum.map(fn {event, form} -> %{event: event, form_instance: form} end)

    Enum.sort_by(own ++ forms, &{&1.event.inserted_at, &1.event.id}, fn
      {a_at, a_id}, {b_at, b_id} ->
        case DateTime.compare(a_at, b_at) do
          :lt -> true
          :gt -> false
          :eq -> a_id <= b_id
        end
    end)
  end

  defp delete_form_instance!(form_instance, opts) do
    case Instances.Forms.delete_instance(form_instance, opts) do
      {:ok, _deleted} -> :ok
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp insert_event(instance, event, opts) do
    attrs = %{
      instance_flow_id: instance.id,
      event: event,
      snapshot: Keyword.get(opts, :snapshot, %{}),
      user_id: Keyword.get(opts, :user_id, instance.user_id)
    }

    Repo.insert(Event.changeset(%Event{}, attrs))
  end

  # `complete/2` and `reopen/2` write the same event kind, so the row has to
  # carry which way it went or a reader cannot tell them apart. It goes in
  # the snapshot under "form_flow", the one key FormFlow claims in a host's
  # maps - merged inside that namespace rather than over it, so a host's own
  # `snapshot:` survives, the rule `mark_pre_release/2` follows for
  # `metadata`. Read back by `FormFlow.Data.Instances.Flow.Event.status/1`.
  # The move's two snapshot numbers travel the same way.
  defp insert_event(instance, event, status, opts) when is_binary(status),
    do: insert_event(instance, event, %{"status" => status}, opts)

  defp insert_event(instance, event, %{} = own_keys, opts) do
    snapshot = Keyword.get(opts, :snapshot) || %{}
    own = Map.get(snapshot, "form_flow") || %{}
    snapshot = Map.put(snapshot, "form_flow", Map.merge(own, own_keys))

    insert_event(instance, event, Keyword.put(opts, :snapshot, snapshot))
  end
end
