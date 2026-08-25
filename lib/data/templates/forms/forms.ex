defmodule FormFlow.Data.Templates.Forms do
  @moduledoc """
  `FormFlow.Data.Templates.Forms` context module for form templates: the
  lineage/version lifecycle and the publish operation.

  A form is a lineage (`FormFlow.Data.Templates.Form` — pure identity) plus
  versions (`FormFlow.Data.Templates.Form.Version` — every definition, draft
  or published). Published versions are immutable; a fix is a new version,
  and what happens to existing instances is a publish-time policy, not a
  migration file. The design and its rationale live in
  `archive/form-versioning.md`.

  ## Drafts

  Any number of drafts may coexist per lineage. `create_draft/2` forks a
  *published* version (or starts blank), `update_draft/2` edits under an
  optimistic lock, and `stale_draft?/1` reports when the base is no longer
  the latest published version. There is no merge machinery — publishes are
  last-publish-wins with linear numbering.

  ## Publishing

  `update_status(version, :published, opts)` publishes a draft in one
  transaction: the lineage row is locked (Postgres — SQLite's single writer
  makes the lock unnecessary, and its grammar has no `FOR UPDATE`), the next
  number is computed over every version ever published (archived included),
  and the migration policy is applied to existing instances:

    * `preset: :bug_fix | :small_fix | :big_fix` — expands to the knobs below
    * `in_progress: :keep | :carry | :reset` — existing in-progress instances
      stay pinned, move to the new version keeping their data, or move and
      start over
    * `completed: :untouched | :reopen_carry | :reopen_reset` — completed
      instances are attestation records and stay untouched by default
    * `renames: %{"old" => "new"}` — re-keys carried data (applied before
      prune: a renamed field's old key is by definition absent from the new
      definition)
    * `prune: true` — drops carried keys not present in the new definition,
      snapshotting them into the event. Applies only when the definition
      declares its fields (`"fields" => [%{"name" => ...}, ...]`); a
      definition without declared fields prunes nothing rather than
      everything.
    * `actor:` — opaque host-app identity stamped into every event

  The default preset is `:small_fix` (keep / untouched) — the least
  surprising for existing users. Every pin move writes an append-only
  `FormFlow.Data.Instances.Form.Event`.
  """

  import Ecto.Query

  alias FormFlow.Data.Instances
  alias FormFlow.Data.Instances.Form.Event
  alias FormFlow.Data.Repo
  alias FormFlow.Data.Templates.Form
  alias FormFlow.Data.Templates.Form.Version

  @presets %{
    bug_fix: %{in_progress: :carry, completed: :untouched},
    small_fix: %{in_progress: :keep, completed: :untouched},
    big_fix: %{in_progress: :reset, completed: :reopen_reset}
  }

  @in_progress_policies [:keep, :carry, :reset]
  @completed_policies [:untouched, :reopen_carry, :reopen_reset]

  @doc """
  Creates a form: the lineage plus its initial draft, in one transaction.

  A `:definition` key in the attributes seeds the draft; everything else is
  lineage identity. Returns the form with its versions preloaded.
  """
  def create(attrs \\ %{}) do
    {definition, attrs} = pop_definition(attrs)

    Repo.transaction(fn ->
      with {:ok, form} <- Repo.insert(Form.changeset(%Form{}, attrs)),
           {:ok, _draft} <- insert_draft(form.id, definition, nil) do
        Repo.preload(form, :versions)
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc "Updates a lineage's identity fields (name, description)."
  def update(%Form{} = form, attrs) do
    form
    |> Ecto.Changeset.cast(attrs, [:name, :description])
    |> Ecto.Changeset.validate_required([:name])
    |> Repo.update()
  end

  @doc """
  Deletes a lineage and its versions.

  Refuses with `{:error, :has_instances}` when any instance pins any of the
  lineage's versions — fill data can never be orphaned. (Once flow releases
  exist, a second pre-check refuses when a release pins the lineage; see
  `archive/flow-versioning-plan.md`.)
  """
  def delete(%Form{} = form) do
    if has_instances?(form.id) do
      {:error, :has_instances}
    else
      Repo.transaction(fn ->
        Repo.delete_all(from(v in Version, where: v.template_form_id == ^form.id))

        case Repo.delete(form) do
          {:ok, deleted} -> deleted
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)
    end
  end

  @doc """
  Copies a lineage — the rollover operation behind copying a flow tree.

  The copy is a new lineage with `copied_from_form_id` provenance. A source
  with a published version copies as a single **published v1** carrying the
  latest published definition — version history stays with the original,
  reachable via provenance, and drafts do not copy. A source that has never
  been published copies its most recently updated draft as a draft: the copy
  of an unpublished thing is an unpublished thing.

  Pass `owner_graph_id:` to make the copy a flow tree's private property —
  the normal case; a copy without an owner lands in the catalog and must not
  collide on `(app, name)`.
  """
  def copy(%Form{} = form, opts \\ []) do
    owner_graph_id = Keyword.get(opts, :owner_graph_id)

    Repo.transaction(fn ->
      changeset =
        %Form{}
        |> Form.changeset(%{
          app: form.app,
          name: form.name,
          description: form.description,
          owner_graph_id: owner_graph_id
        })
        |> Ecto.Changeset.put_change(:copied_from_form_id, form.id)

      with {:ok, copy} <- Repo.insert(changeset),
           {:ok, _version} <- copy_version(form, copy) do
        Repo.preload(copy, :versions)
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc "Fetches a lineage by id, or nil."
  def get(form_id), do: Repo.get(Form, form_id)

  @doc "Fetches a version by id, or nil."
  def get_version(version_id), do: Repo.get(Version, version_id)

  @doc """
  Lists the catalog: reusable forms (no owner), for one app, oldest first.

  Owned forms live inside their flow trees and are reached by drill-in,
  never listed beside the catalog.
  """
  def list(app \\ "default") do
    Repo.all(
      from(f in Form,
        where: is_nil(f.owner_graph_id) and f.app == ^app,
        order_by: [asc: f.inserted_at]
      )
    )
  end

  @doc "Lists a lineage's versions, drafts and published alike, newest first."
  def list_versions(form_id) do
    Repo.all(
      from(v in Version,
        where: v.template_form_id == ^form_id,
        order_by: [desc: v.inserted_at]
      )
    )
  end

  @doc "The latest published version of a lineage, or nil. Skips drafts and archived."
  def get_latest_version(form_id) do
    Repo.one(
      from(v in Version,
        where: v.template_form_id == ^form_id and v.status == "published",
        order_by: [desc: v.version],
        limit: 1
      )
    )
  end

  @doc """
  Creates a draft for a lineage.

  `based_on: version_id` forks a *published* version of the same lineage —
  the definition is copied and the provenance recorded, powering
  `stale_draft?/1`. Drafts cannot fork drafts, and the rule is checked here
  at creation only: a base archived later leaves existing drafts valid.
  Without `based_on`, the draft starts blank.
  """
  def create_draft(form_id, opts \\ []) do
    case Keyword.get(opts, :based_on) do
      nil ->
        insert_draft(form_id, %{}, nil)

      based_on_id ->
        case Repo.get(Version, based_on_id) do
          nil ->
            {:error, :based_on_not_found}

          %Version{template_form_id: other} when other != form_id ->
            {:error, :based_on_wrong_form}

          %Version{status: status} when status != "published" ->
            {:error, :based_on_not_published}

          %Version{} = base ->
            insert_draft(form_id, base.definition, base.id)
        end
    end
  end

  @doc """
  Updates a draft's definition under the optimistic lock.

  Returns `{:error, :stale}` when the draft changed under the caller —
  surface it as "this draft changed under you", never silently overwrite.
  Non-drafts are immutable and error in the changeset.
  """
  def update_draft(%Version{} = version, attrs) do
    Repo.update(Version.update_changeset(version, attrs))
  rescue
    Ecto.StaleEntryError -> {:error, :stale}
  end

  @doc "Deletes a draft. Published and archived versions cannot be deleted."
  def delete_draft(%Version{status: "draft"} = version), do: Repo.delete(version)
  def delete_draft(%Version{}), do: {:error, :not_draft}

  @doc """
  Whether a draft's base is no longer the latest published version —
  the "based on v3, v4 has landed since" warning. Blank drafts (no base)
  are never stale.
  """
  def stale_draft?(%Version{based_on_version_id: nil}), do: false

  def stale_draft?(%Version{} = version) do
    case get_latest_version(version.template_form_id) do
      nil -> false
      latest -> latest.id != version.based_on_version_id
    end
  end

  @doc """
  Transitions a version's status.

  `update_status(version, :published, opts)` is the publish operation — see
  the moduledoc for the policy options. `update_status(version, :archived)`
  archives a published version: it drops out of `get_latest_version/1` (so
  archiving the latest is a de-facto rollback to the previous one), stops
  being a valid `based_on` target, and keeps serving its pinned instances.
  """
  def update_status(version, status, opts \\ [])

  def update_status(%Version{} = version, :archived, _opts) do
    Repo.update(Version.status_changeset(version, "archived"))
  end

  def update_status(%Version{} = version, :published, opts) do
    policy = resolve_policy!(opts)

    Repo.transaction(fn ->
      lock_lineage(version.template_form_id)

      case Repo.get(Version, version.id) do
        nil ->
          Repo.rollback(:not_found)

        %Version{status: status} when status != "draft" ->
          Repo.rollback(:not_draft)

        %Version{} = draft ->
          number = next_version_number(draft.template_form_id)
          now = DateTime.utc_now()

          case Repo.update(Version.status_changeset(draft, "published", number, now)) do
            {:ok, published} ->
              migrate_instances(published, policy)
              published

            {:error, changeset} ->
              Repo.rollback(changeset)
          end
      end
    end)
  end

  # --- publish internals ---------------------------------------------------

  defp resolve_policy!(opts) do
    preset = Keyword.get(opts, :preset, :small_fix)

    base =
      Map.get(@presets, preset) ||
        raise ArgumentError, "unknown preset #{inspect(preset)}"

    policy = %{
      in_progress: Keyword.get(opts, :in_progress, base.in_progress),
      completed: Keyword.get(opts, :completed, base.completed),
      renames: Keyword.get(opts, :renames, %{}),
      prune: Keyword.get(opts, :prune, false),
      actor: Keyword.get(opts, :actor)
    }

    unless policy.in_progress in @in_progress_policies do
      raise ArgumentError, "in_progress must be one of #{inspect(@in_progress_policies)}"
    end

    unless policy.completed in @completed_policies do
      raise ArgumentError, "completed must be one of #{inspect(@completed_policies)}"
    end

    policy
  end

  # Serializes concurrent publishes of one lineage. Postgres only: SQLite has
  # no FOR UPDATE in its grammar (an unconditional lock is a runtime syntax
  # error, not a no-op) and its single-writer model makes the lock
  # unnecessary. The unique (template_form_id, version) index is the backstop.
  defp lock_lineage(form_id) do
    query = from(f in Form, where: f.id == ^form_id)
    query = if postgres?(), do: lock(query, "FOR UPDATE"), else: query

    Repo.one(query)
  end

  defp postgres?, do: Repo.repo().__adapter__() == Ecto.Adapters.Postgres

  # Over every version ever published — archived included. Computing over
  # status == "published" alone would reissue an archived version's number
  # and trip the unique index.
  defp next_version_number(form_id) do
    max =
      Repo.one(
        from(v in Version,
          where: v.template_form_id == ^form_id and not is_nil(v.version),
          select: max(v.version)
        )
      )

    (max || 0) + 1
  end

  defp migrate_instances(published, policy) do
    instances =
      Repo.all(
        from(i in Instances.Form,
          join: v in Version,
          on: i.template_form_version_id == v.id,
          where: v.template_form_id == ^published.template_form_id,
          where: i.template_form_version_id != ^published.id
        )
      )

    Enum.each(instances, fn instance ->
      action =
        case instance.status do
          "in_progress" -> policy.in_progress
          "completed" -> policy.completed
        end

      apply_policy(instance, action, published, policy)
    end)
  end

  defp apply_policy(_instance, action, _published, _policy)
       when action in [:keep, :untouched],
       do: :ok

  defp apply_policy(instance, :carry, published, policy) do
    {data, dropped} = transform_data(instance.data, published, policy)

    migrate!(instance, published, policy, "migrated", %{data: data}, dropped)
  end

  defp apply_policy(instance, :reset, published, policy) do
    migrate!(instance, published, policy, "migrated", %{data: %{}}, instance.data)
  end

  defp apply_policy(instance, :reopen_carry, published, policy) do
    {data, dropped} = transform_data(instance.data, published, policy)

    migrate!(
      instance,
      published,
      policy,
      "reopened",
      %{data: data, status: "in_progress", completed_at: nil},
      dropped
    )
  end

  defp apply_policy(instance, :reopen_reset, published, policy) do
    migrate!(
      instance,
      published,
      policy,
      "reopened",
      %{data: %{}, status: "in_progress", completed_at: nil},
      instance.data
    )
  end

  defp migrate!(instance, published, policy, event, changes, data_snapshot) do
    changes = Map.put(changes, :template_form_version_id, published.id)

    case Repo.update(Ecto.Changeset.change(instance, changes)) do
      {:ok, _instance} -> :ok
      {:error, changeset} -> Repo.rollback(changeset)
    end

    event_attrs = %{
      instance_form_id: instance.id,
      event: event,
      from_version_id: instance.template_form_version_id,
      to_version_id: published.id,
      data_snapshot: data_snapshot,
      actor: policy.actor
    }

    case Repo.insert(Event.changeset(%Event{}, event_attrs)) do
      {:ok, _event} -> :ok
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  # Renames re-key first, then prune drops keys absent from the new
  # definition — the only correct order: a renamed field's old key is by
  # definition not in the new definition. Returns {data, dropped} where
  # dropped is what prune removed (the event's data_snapshot).
  defp transform_data(data, published, policy) do
    data =
      Enum.reduce(policy.renames, data, fn {old, new}, acc ->
        case Map.pop(acc, old) do
          {nil, _acc} -> acc
          {value, acc} -> Map.put(acc, new, value)
        end
      end)

    prune_data(data, published, policy)
  end

  defp prune_data(data, published, %{prune: true}) do
    case declared_field_names(published.definition) do
      # A definition that doesn't declare its fields prunes nothing —
      # never everything
      nil -> {data, %{}}
      names -> {Map.take(data, names), Map.drop(data, names)}
    end
  end

  defp prune_data(data, _published, _policy), do: {data, %{}}

  defp declared_field_names(%{"fields" => fields}) when is_list(fields) do
    names = for %{"name" => name} <- fields, is_binary(name), do: name

    if names == [], do: nil, else: names
  end

  defp declared_field_names(_definition), do: nil

  # --- helpers --------------------------------------------------------------

  # Published source → published v1 from the latest published definition;
  # never-published source → the most recently updated draft copies as a draft
  defp copy_version(source, copy) do
    case get_latest_version(source.id) do
      %Version{} = published ->
        with {:ok, draft} <- insert_draft(copy.id, published.definition, nil) do
          Repo.update(Version.status_changeset(draft, "published", 1, DateTime.utc_now()))
        end

      nil ->
        latest_draft =
          Repo.one(
            from(v in Version,
              where: v.template_form_id == ^source.id and v.status == "draft",
              order_by: [desc: v.updated_at],
              limit: 1
            )
          )

        definition = (latest_draft && latest_draft.definition) || %{}

        insert_draft(copy.id, definition, nil)
    end
  end

  defp insert_draft(form_id, definition, based_on_id) do
    Repo.insert(
      Version.create_changeset(%Version{}, %{
        template_form_id: form_id,
        definition: definition || %{},
        based_on_version_id: based_on_id
      })
    )
  end

  defp has_instances?(form_id) do
    Repo.exists?(
      from(i in Instances.Form,
        join: v in Version,
        on: i.template_form_version_id == v.id,
        where: v.template_form_id == ^form_id
      )
    )
  end

  defp pop_definition(attrs) do
    cond do
      Map.has_key?(attrs, :definition) -> {attrs.definition, Map.delete(attrs, :definition)}
      Map.has_key?(attrs, "definition") -> {attrs["definition"], Map.delete(attrs, "definition")}
      true -> {%{}, attrs}
    end
  end
end
