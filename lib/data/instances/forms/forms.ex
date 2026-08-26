defmodule FormFlow.Data.Instances.Forms do
  @moduledoc """
  `FormFlow.Data.Instances.Forms` context module for form instances.

  The lifecycle of an in-journey form instance runs through one entry
  point, `update_status/4`, addressed by journey + position — the same
  consolidation `FormFlow.Data.Templates.Forms.update_status/3` gives the
  template side. The two statuses make three transitions:

    * `update_status(journey, path, :in_progress)` — "the user is working
      here." On an empty position this *creates* the instance — created on
      first open, not when the journey starts, because creation is what
      pins the version: the row permanently records which published
      definition the user saw, so creating rows any earlier would pin
      versions for forms the user may never reach and miss improvements
      published in the meantime. On a completed instance it *reopens*
      (back to `in_progress`, `completed_at` cleared, `reopened` event),
      keeping the answers for editing. Already in progress: a no-op.
    * `update_status(journey, path, :completed, data: answers)` — submit:
      the answers land in `data`, `status`/`completed_at` are stamped, and
      a `status_changed` event is written. Completion is what unlocks
      successor positions in `FormFlow.Data.Instances.Progress`. Completing
      a completed instance is a no-op — reopen first.

  Deletion stays its own named operation: `delete_instance/2` is the host's
  retention decision, made visibly. Events never cascade-delete with their
  instance, so it is the only deletion path.

  Two browser tabs opening the same untouched position race their inserts;
  the `(instance_flow_id, path)` unique index lets exactly one win.
  Deliberately unhandled for now — the loser surfaces the changeset error
  and the user retries; catch-and-fetch can be added if it becomes a real
  irritation. The same goes for concurrent edits: the changeset's optimistic
  lock raises `Ecto.StaleEntryError` rather than silently overwriting, and a
  friendlier `{:error, :stale}` surface waits for a real need.
  """

  import Ecto.Query

  alias FormFlow.Data.Instances
  alias FormFlow.Data.Instances.Form.Event
  alias FormFlow.Data.Repo
  alias FormFlow.Data.Templates

  @doc "Fetches an instance by id, or nil."
  def get(instance_form_id), do: Repo.get(Instances.Form, instance_form_id)

  @doc """
  Moves the form instance at a journey position to `status` — the one entry
  point for opening, submitting, and reopening (see the moduledoc).

  `opts`:

    * `:data` — the answers, written on `:completed` (left untouched when
      absent, so a bare re-stamp never wipes answers)
    * `:user_id` — the acting user, recorded on the event
    * `:data_snapshot` — free-form event payload

  Returns `{:ok, instance}`. Errors: `{:error, :not_found}` (completing a
  position with no instance), `{:error, :unknown_position}` (no such node —
  the flow may have been edited), `{:error, :not_a_form_position}`,
  `{:error, :no_published_version}` (the form was never published), or an
  error changeset.
  """
  def update_status(journey, path, status, opts \\ [])

  def update_status(%Instances.Flow{} = journey, path, status, opts)
      when is_list(path) and path != [] and status in [:in_progress, :completed] do
    instance =
      Repo.one(
        from(f in Instances.Form,
          where:
            f.instance_flow_id == ^journey.id and f.path == ^path and
              is_nil(f.superseded_at)
        )
      )

    case {instance, status} do
      {nil, :in_progress} -> create_at(journey, path, opts)
      {nil, :completed} -> {:error, :not_found}
      {%Instances.Form{status: "in_progress"}, :in_progress} -> {:ok, instance}
      {%Instances.Form{}, :in_progress} -> reopen(instance, opts)
      {%Instances.Form{status: "completed"}, :completed} -> {:ok, instance}
      {%Instances.Form{}, :completed} -> complete(instance, opts)
    end
  end

  @doc """
  Deletes an instance and its event trail, deliberately and in order:
  events first (the `restrict` FK forbids any other order), then the
  instance. This is the only deletion path — there is no cascade.
  """
  def delete_instance(%Instances.Form{} = instance, _opts \\ []) do
    Repo.transaction(fn ->
      Repo.delete_all(from(e in Event, where: e.instance_form_id == ^instance.id))

      case Repo.delete(instance) do
        {:ok, deleted} -> deleted
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp complete(instance, opts) do
    Repo.transaction(fn ->
      changes = %{status: "completed", completed_at: DateTime.utc_now()}

      changes =
        case Keyword.fetch(opts, :data) do
          {:ok, data} when is_map(data) -> Map.put(changes, :data, data)
          :error -> changes
        end

      with {:ok, completed} <- Repo.update(Ecto.Changeset.change(instance, changes)),
           {:ok, _event} <- insert_event(completed, "status_changed", opts) do
        completed
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp reopen(instance, opts) do
    Repo.transaction(fn ->
      changes = %{status: "in_progress", completed_at: nil}

      with {:ok, reopened} <- Repo.update(Ecto.Changeset.change(instance, changes)),
           {:ok, _event} <- insert_event(reopened, "reopened", opts) do
        reopened
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp create_at(journey, path, opts) do
    node = Templates.Flows.get_node(List.last(path))

    cond do
      is_nil(node) ->
        {:error, :unknown_position}

      is_nil(node.form_id) ->
        {:error, :not_a_form_position}

      true ->
        case Templates.Forms.get_latest_version(node.form_id) do
          nil -> {:error, :no_published_version}
          version -> insert_instance(journey, path, version, opts)
        end
    end
  end

  defp insert_instance(journey, path, version, opts) do
    Repo.transaction(fn ->
      changeset =
        Instances.Form.visit_changeset(
          %Instances.Form{},
          %{template_form_version_id: version.id},
          journey.id,
          path
        )

      with {:ok, instance} <- Repo.insert(changeset),
           {:ok, _event} <- insert_event(instance, "created", opts) do
        instance
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp insert_event(instance, event, opts) do
    attrs = %{
      instance_form_id: instance.id,
      event: event,
      user_id: Keyword.get(opts, :user_id),
      data_snapshot: Keyword.get(opts, :data_snapshot, %{})
    }

    Repo.insert(Event.changeset(%Event{}, attrs))
  end
end
