defmodule FormFlow.Data.Instances.Flows do
  @moduledoc """
  `FormFlow.Data.Instances.Flows` context module for whole-root-flow
  instances — journeys: a `FormFlow.Data.Instances.Flow` row plus every form
  instance filled at a position inside it (see `FormFlow.Data.Instances` for
  the term).

  Deliberately minimal until the runner lands: creation (with its `created`
  event), the completion stamp, the derived-progress helpers, stranded
  listing, and the one operation that must exist concretely from day one —
  explicit deletion, because nothing on the instance side ever cascades.
  """

  import Ecto.Query

  alias FormFlow.Data.Instances
  alias FormFlow.Data.Instances.Flow.Event
  alias FormFlow.Data.Instances.FlowProgress
  alias FormFlow.Data.Repo
  alias FormFlow.Data.Templates

  @doc "Fetches a journey by id, or nil."
  def get(instance_flow_id), do: Repo.get(Instances.Flow, instance_flow_id)

  @doc """
  Journeys, newest first, with `:flow` preloaded. `opts[:user_id]` narrows
  to one creator, `opts[:tenant_id]` to one tenant, and `opts[:flow]` to
  instances of one or more flow templates (see `narrow_flow/2`) — query
  conveniences for "my journeys" listings, not access control: the library
  never enforces visibility.
  """
  def list(opts \\ []) do
    Repo.all(from(i in list_query(opts), order_by: [desc: i.inserted_at], preload: [:flow]))
  end

  @doc """
  The same listing as a composable query: unordered and unpreloaded, so
  callers (like Slab's table in query mode) can layer `order_by`,
  `limit`/`offset`, `Repo.aggregate(:count)`, and their own preloads on top.

  `opts[:user_id]`, `opts[:tenant_id]`, and `opts[:flow]` narrow exactly as
  in `list/1` — and with the same caveat: listing conveniences, not access
  control. This is the building block for the `instances` attr of
  `FormFlow.Web.router/1`: the listing page's own default is
  `list_query(user_id: user_id)`, narrowed to the flows the page offers
  when it offers some in particular.
  """
  def list_query(opts \\ []) do
    from(i in Instances.Flow)
    |> narrow(:user_id, Keyword.get(opts, :user_id))
    |> narrow_tenant(Keyword.get(opts, :tenant_id))
    |> narrow_flow(Keyword.get(opts, :flow))
  end

  @doc """
  `query` — one over `FormFlow.Data.Instances.Flow` — narrowed to instances
  of one or more flow templates: a `FormFlow.Data.Templates.Flow`, an id, or
  a slug, or a list mixing them (`nil` entries dropped). `nil` leaves the
  query as it is; `[]` matches nothing.

  Slugs are unique per tenant, not globally, so a slug alone matches the
  flow of that slug in every tenant — pair it with `tenant_id:` when that
  matters, as the listing page does.
  """
  def narrow_flow(query, nil), do: query

  def narrow_flow(query, flows) do
    refs = flows |> List.wrap() |> Enum.reject(&is_nil/1)
    struct_ids = for %Templates.Flow{id: id} <- refs, do: id
    {ids, slugs} = refs |> Enum.filter(&is_binary/1) |> Enum.split_with(&uuid?/1)
    ids = struct_ids ++ ids

    templates = from(f in Templates.Flow, where: f.id in ^ids or f.slug in ^slugs, select: f.id)

    from(i in query, where: i.flow_id in subquery(templates))
  end

  # Node and flow ids are UUIDs and slugs never are, so one string can only
  # be one of the two — the same distinction the router draws in a URL
  defp uuid?(value), do: match?({:ok, _uuid}, Ecto.UUID.cast(value))

  @doc """
  `query` — one over `FormFlow.Data.Instances.Flow`, such as a host's
  `instances` attr — narrowed to one tenant.
  `nil` leaves it as it is, the whole table being the scope of a host with
  no tenants.
  """
  def narrow_tenant(query, tenant_id), do: narrow(query, :tenant_id, tenant_id)

  @doc """
  `query` — one over `FormFlow.Data.Instances.Flow` — narrowed to instances
  of flows whose status allows `action` (`:start`, `:continue`, or `:see`;
  `FormFlow.Data.Templates.Flow.allows?/2`). The listing page applies
  `:see` on top of whatever it lists, the host's query included, the way it
  applies the tenant: a draft flow's instances are nobody's to see on the
  user-facing side.
  """
  def narrow_allowed(query, action) do
    statuses = Templates.Flow.statuses_allowing(action)
    templates = from(f in Templates.Flow, where: f.status in ^statuses, select: f.id)

    from(i in query, where: i.flow_id in subquery(templates))
  end

  @doc """
  `query` — one over `FormFlow.Data.Instances.Flow` — without the instances
  of flows in `status`. The listing page drops pre-release flows this way
  for a user the page does not name among its pre-release users.
  """
  def exclude_status(query, status) when is_binary(status) do
    templates = from(f in Templates.Flow, where: f.status == ^status, select: f.id)

    from(i in query, where: i.flow_id not in subquery(templates))
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
  the listing at the click), so that a host's own route — an appeal taken
  after the deadline, a support tool repairing a record — can do what it is
  asked. A route of its own that should honour the status asks `allows?/2`
  first, as the pages do.

  One thing about the status is recorded: a journey started while the flow
  is `pre_release` gets `"form_flow" => %{"pre_release" => true}` in its
  `metadata`, so a listing or an export can tell the pre-release run's
  instances from the real ones once the flow opens. `metadata` is otherwise
  the host's map; `"form_flow"` is the one key FormFlow claims in it.
  """
  def create(attrs \\ %{}, opts \\ []) do
    flow_id = attrs[:flow_id] || attrs["flow_id"]

    Repo.transaction(fn ->
      attrs = mark_pre_release(attrs, flow_id && Repo.get(Templates.Flow, flow_id))

      with {:ok, instance} <- Repo.insert(Instances.Flow.changeset(%Instances.Flow{}, attrs)),
           {:ok, _event} <- insert_event(instance, "created", opts) do
        instance
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @pre_release_marker %{"form_flow" => %{"pre_release" => true}}

  defp mark_pre_release(attrs, %Templates.Flow{status: "pre_release"}) do
    key = if Map.has_key?(attrs, "flow_id"), do: "metadata", else: :metadata
    Map.update(attrs, key, @pre_release_marker, &Map.merge(&1 || %{}, @pre_release_marker))
  end

  defp mark_pre_release(attrs, _flow), do: attrs

  @doc """
  Stamps `status: "completed"` and `completed_at`, writing a
  `status_changed` event. The stamp is a fact at a moment, never recomputed
  — it may legitimately diverge from `complete?/1` after a later template
  edit. Who calls it — runner-automatic on End reached, host-triggered, or
  End-node custom logic (planned) — is deliberately not decided here.
  Completing a completed journey is a no-op. The flow's status is not
  consulted: this is an administrative stamp on the journey, not a user
  continuing it, and a host closing out a read-only year may well call it.
  """
  def complete(instance, opts \\ [])

  def complete(%Instances.Flow{status: "completed"} = instance, _opts), do: {:ok, instance}

  def complete(%Instances.Flow{} = instance, opts) do
    Repo.transaction(fn ->
      changes = %{status: "completed", completed_at: DateTime.utc_now()}

      with {:ok, completed} <- Repo.update(Ecto.Changeset.change(instance, changes)),
           {:ok, _event} <- insert_event(completed, "status_changed", opts) do
        completed
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Derived traversal state for a journey — `%{path => status}` from the live
  tree and the journey's form instances. Never persisted; see
  `FormFlow.Data.Instances.FlowProgress`.
  """
  def progress(%Instances.Flow{} = instance) do
    FlowProgress.derive(Templates.Flows.resolve_tree(instance.flow_id), form_instances(instance))
  end

  @doc """
  The derivation-side completion answer — distinct from the stamped
  `status`, which is a fact at a moment. The two may diverge after a
  template edit; hosts should ask the question they mean.
  """
  def complete?(%Instances.Flow{} = instance) do
    FlowProgress.complete?(
      Templates.Flows.resolve_tree(instance.flow_id),
      form_instances(instance)
    )
  end

  @doc """
  The position a user should go to next — the first available (or already
  in-progress) form position in flow order, descending into subflows — or
  nil when nothing is actionable. This is the after-submit redirect.
  """
  def next_path_position(%Instances.Flow{} = instance) do
    FlowProgress.next_path_position(
      Templates.Flows.resolve_tree(instance.flow_id),
      form_instances(instance)
    )
  end

  @doc """
  The journey's stranded form instances: active (not superseded) instances
  whose `path` matches no position in the current tree. Accepts a
  `Templates.Flow` to sweep every journey of that root at once — one edit
  to a subflow strands instances across every journey of the root
  simultaneously, and batch reconciliation builds on this.
  """
  def list_stranded(instance_or_flow, opts \\ [])

  def list_stranded(%Instances.Flow{} = instance, _opts) do
    instances = form_instances(instance)
    statuses = FlowProgress.derive(Templates.Flows.resolve_tree(instance.flow_id), instances)

    stranded_paths =
      for {path, :stranded} <- statuses, into: MapSet.new() do
        path
      end

    Enum.filter(instances, fn form_instance ->
      is_nil(form_instance.superseded_at) and MapSet.member?(stranded_paths, form_instance.path)
    end)
  end

  def list_stranded(%Templates.Flow{} = flow, opts) do
    Repo.all(from(i in Instances.Flow, where: i.flow_id == ^flow.id))
    |> Enum.flat_map(&list_stranded(&1, opts))
  end

  @doc """
  Deletes a journey, its event trail, and its attached form instances,
  deliberately and in order: journey events first, then each form instance
  through `FormFlow.Data.Instances.Forms.delete_instance/2` (its events
  first — the `restrict` FKs forbid any other order), then the journey row.
  This is the only deletion path — there is no cascade.

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

      case Repo.delete(instance) do
        {:ok, deleted} -> deleted
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc "All of a journey's form instances, superseded ones included."
  def form_instances(%Instances.Flow{} = instance) do
    Repo.all(from(f in Instances.Form, where: f.instance_flow_id == ^instance.id))
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
end
