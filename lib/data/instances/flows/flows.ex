defmodule FormFlow.Data.Instances.Flows do
  @moduledoc """
  `FormFlow.Data.Instances.Flows` context module for journeys —
  `FormFlow.Data.Instances.Flow` records.

  Deliberately minimal until the runner lands: creation (with its `created`
  event), the completion stamp, the derived-progress helpers, stranded
  listing, and the one operation that must exist concretely from day one —
  explicit deletion, because nothing on the instance side ever cascades.
  """

  import Ecto.Query

  alias FormFlow.Data.Instances
  alias FormFlow.Data.Instances.Flow.Event
  alias FormFlow.Data.Instances.Progress
  alias FormFlow.Data.Repo
  alias FormFlow.Data.Templates

  @doc "Fetches a journey by id, or nil."
  def get(instance_flow_id), do: Repo.get(Instances.Flow, instance_flow_id)

  @doc """
  Creates a journey and its `created` event in one transaction.

  The journey's own `user_id` (the owner) comes from `attrs`; the event's
  `user_id` (the actor of this creation) defaults to the same and can be
  overridden with `opts[:user_id]`.
  """
  def create(attrs \\ %{}, opts \\ []) do
    Repo.transaction(fn ->
      with {:ok, instance} <- Repo.insert(Instances.Flow.changeset(%Instances.Flow{}, attrs)),
           {:ok, _event} <- insert_event(instance, "created", opts) do
        instance
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Stamps `status: "completed"` and `completed_at`, writing a
  `status_changed` event. The stamp is a fact at a moment, never recomputed
  — it may legitimately diverge from `complete?/1` after a later template
  edit. Who calls it — runner-automatic on End reached, host-triggered, or
  End-node custom logic (planned) — is deliberately not decided here.
  Completing a completed journey is a no-op.
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
  `FormFlow.Data.Instances.Progress`.
  """
  def progress(%Instances.Flow{} = instance) do
    Progress.derive(Templates.Flows.resolve_tree(instance.flow_id), form_instances(instance))
  end

  @doc """
  The derivation-side completion answer — distinct from the stamped
  `status`, which is a fact at a moment. The two may diverge after a
  template edit; hosts should ask the question they mean.
  """
  def complete?(%Instances.Flow{} = instance) do
    Progress.complete?(Templates.Flows.resolve_tree(instance.flow_id), form_instances(instance))
  end

  @doc """
  The journey's stranded form instances: active (not superseded) instances
  whose `path` matches no position in the current tree. Accepts a
  `Templates.Flow` to sweep every journey of that root at once — one edit
  to a shared reusable subflow can strand instances across every consumer
  journey simultaneously, and batch reconciliation builds on this.
  """
  def list_stranded(instance_or_flow, opts \\ [])

  def list_stranded(%Instances.Flow{} = instance, _opts) do
    instances = form_instances(instance)
    statuses = Progress.derive(Templates.Flows.resolve_tree(instance.flow_id), instances)

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
  """
  def delete_instance(%Instances.Flow{} = instance, opts \\ []) do
    Repo.transaction(fn ->
      Repo.delete_all(from(e in Event, where: e.instance_flow_id == ^instance.id))

      instance
      |> form_instances()
      |> Enum.each(&delete_form_instance!(&1, opts))

      case Repo.delete(instance) do
        {:ok, deleted} -> deleted
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp form_instances(%Instances.Flow{} = instance) do
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
