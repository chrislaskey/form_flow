defmodule FormFlow.Data.Instances.Forms do
  @moduledoc """
  `FormFlow.Data.Instances.Forms` context module for form instances.

  The lifecycle of a form instance filled inside a whole root flow instance —
  a journey (see `FormFlow.Data.Instances`) — runs through one entry point,
  `update_status/4`, addressed by that journey plus the position within it:
  the `path` through the flow's tree. That is the same consolidation
  `FormFlow.Data.Templates.Forms.update_status/3` gives the template side.
  The two statuses make three transitions:

    * `update_status(journey, path, :in_progress)` — "the user is working
      here." On an empty position this *creates* the instance — created on
      first start, not when the journey starts, because creation is what
      pins the version: the row permanently records which published
      definition the user saw, so creating rows any earlier would pin
      versions for forms the user may never reach and miss improvements
      published in the meantime. On a completed instance it *reopens*
      (back to `in_progress`, `completed_at` cleared, `reopened` event),
      keeping the answers for editing. Already in progress: a no-op.
    * `update_status(journey, path, :completed, data: answers)` — submit:
      the answers land in `data`, `status`/`completed_at` are stamped, and
      a `status_changed` event is written. Completion is what unlocks
      successor positions in `FormFlow.Data.Instances.FlowProgress`.
      Completing a completed instance is a no-op — reopen first.

  Deletion stays its own named operation: `delete_instance/2` is the host's
  retention decision, made visibly. Events never cascade-delete with their
  instance, so it is the only deletion path. The trail itself is read through
  `list_events/2` and `latest_event/2`.

  Two browser tabs starting the same untouched position race their inserts;
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
  The live instance at a journey position, or nil — the row a position is
  addressed by. Superseded instances are skipped: they are attestation
  records, not the answers being worked on.
  """
  def get_at(%Instances.Flow{} = journey, path) when is_list(path) and path != [] do
    find_instance(journey, path)
  end

  @doc """
  An instance's event trail, oldest first — `inserted_at` then `id`, so
  events written in one transaction keep a stable order. `event:` filters by
  kind (`"created"`, `"migrated"`, `"reopened"`, `"status_changed"`).
  """
  @spec list_events(Instances.Form.t(), keyword()) :: [Event.t()]
  def list_events(%Instances.Form{id: id}, opts \\ []) do
    from(e in Event,
      where: e.instance_form_id == ^id,
      order_by: [asc: e.inserted_at, asc: e.id]
    )
    |> filter_event(opts[:event])
    |> Repo.all()
  end

  defp filter_event(query, nil), do: query
  defp filter_event(query, event), do: from(e in query, where: e.event == ^event)

  @doc "The newest event of a kind, or nil."
  @spec latest_event(Instances.Form.t(), String.t()) :: Event.t() | nil
  def latest_event(%Instances.Form{} = instance, event) do
    instance |> list_events(event: event) |> List.last()
  end

  @doc """
  Moves the form instance at a journey position to `status` — the one entry
  point for opening, submitting, and reopening (see the moduledoc).

  `opts`:

    * `:data` — the answers, written on `:completed` (left untouched when
      absent, so a bare re-stamp never wipes answers)
    * `:user_id` — the acting user, recorded on the event
    * `:snapshot_data` — free-form event payload

  Returns `{:ok, instance}`. Errors: `{:error, :not_found}` (completing a
  position with no instance), `{:error, :unknown_position}` (no such node —
  the flow may have been edited), `{:error, :not_a_form_position}`,
  `{:error, :no_published_version}` (the form was never published), or an
  error changeset.
  """
  def update_status(journey, path, status, opts \\ [])

  def update_status(%Instances.Flow{} = journey, path, status, opts)
      when is_list(path) and path != [] and status in [:in_progress, :completed] do
    journey
    |> find_instance(path)
    |> apply_status(status, journey, path, opts)
  end

  defp find_instance(journey, path) do
    Repo.one(
      from(f in Instances.Form,
        where:
          f.instance_flow_id == ^journey.id and f.path == ^path and
            is_nil(f.superseded_at)
      )
    )
  end

  defp apply_status(nil, :in_progress, journey, path, opts), do: create_at(journey, path, opts)
  defp apply_status(nil, :completed, _journey, _path, _opts), do: {:error, :not_found}

  defp apply_status(
         %Instances.Form{status: "in_progress"} = instance,
         :in_progress,
         _journey,
         _path,
         _opts
       ),
       do: {:ok, instance}

  defp apply_status(%Instances.Form{} = instance, :in_progress, _journey, _path, opts),
    do: reopen(instance, opts)

  defp apply_status(
         %Instances.Form{status: "completed"} = instance,
         :completed,
         _journey,
         _path,
         _opts
       ),
       do: {:ok, instance}

  defp apply_status(%Instances.Form{} = instance, :completed, _journey, _path, opts),
    do: complete(instance, opts)

  @doc """
  Deletes an instance and its event trail, deliberately and in order: the
  copies other instances' events hold of its answers are blanked first
  (`redact_snapshots/1`, so a failed redaction aborts the deletion rather
  than leaving copies behind), then its events (the `restrict` FK forbids
  any other order), then the instance. This is the only deletion path —
  there is no cascade.

  `redact: false` skips the redaction — for a caller deleting the whole
  journey, whose copies go with it (`FormFlow.Data.Instances.Flows.delete_instance/2`).
  """
  def delete_instance(%Instances.Form{} = instance, opts \\ []) do
    Repo.transaction(fn ->
      if Keyword.get(opts, :redact, true), do: redact_snapshots(instance)

      Repo.delete_all(from(e in Event, where: e.instance_form_id == ^instance.id))

      case Repo.delete(instance) do
        {:ok, deleted} -> deleted
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Blanks the answers in every review snapshot that references `instance` —
  the copies review submissions made of it, found by
  `"reviewed"."instance_id"` in the `snapshot_data` of the `status_changed`
  events of the journey's other instances, superseded ones included (a
  superseded review's trail is kept, not deleted, so its copy has to be
  blanked too). Each copy's `"data"` becomes `%{}` and `"redacted_at"` is
  stamped beside it; nothing else on the row changes. Returns how many
  copies were blanked.

  This is the only sanctioned update of an event row
  (`FormFlow.Data.Instances.Form.Event`). It is for deleting one instance
  out of a surviving journey — `delete_instance/2` runs it first — and is
  public for a host's own erasure flow. Deleting the whole journey takes
  the copies with it, so `FormFlow.Data.Instances.Flows.delete_instance/2`
  skips it. A standalone instance has no journey and no copies.
  """
  @spec redact_snapshots(Instances.Form.t()) :: {:ok, non_neg_integer()}
  def redact_snapshots(%Instances.Form{instance_flow_id: nil}), do: {:ok, 0}

  def redact_snapshots(%Instances.Form{} = instance) do
    redacted_at = DateTime.to_iso8601(DateTime.utc_now())

    # The two supported adapters query JSON differently, so the match on the
    # snapshot happens here rather than in the query: a journey's events are
    # few, and this needs no index
    events =
      Repo.all(
        from(e in Event,
          join: f in Instances.Form,
          on: f.id == e.instance_form_id,
          where: f.instance_flow_id == ^instance.instance_flow_id and f.id != ^instance.id,
          where: e.event == "status_changed"
        )
      )

    Repo.transaction(fn ->
      events
      |> Enum.filter(&(get_in(&1.snapshot_data, ["reviewed", "instance_id"]) == instance.id))
      |> Enum.reduce(0, fn event, count ->
        reviewed =
          Map.merge(event.snapshot_data["reviewed"], %{
            "data" => %{},
            "redacted_at" => redacted_at
          })

        snapshot = Map.put(event.snapshot_data, "reviewed", reviewed)

        # Written as a plain column update so nothing else on the row moves,
        # `updated_at` included
        {1, _} =
          Repo.update_all(from(e in Event, where: e.id == ^event.id),
            set: [snapshot_data: snapshot]
          )

        count + 1
      end)
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
      snapshot_data: Keyword.get(opts, :snapshot_data, %{})
    }

    Repo.insert(Event.changeset(%Event{}, attrs))
  end
end
