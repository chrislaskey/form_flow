defmodule FormFlow.Data.Templates.Form.Version do
  @moduledoc """
  `FormFlow.Data.Templates.Form.Version` Ecto Schema for one definition of a
  form template — a draft, a published version, or an archived one.

  This schema is the immutability enforcement point (hard rule 2 in
  `archive/form-versioning.md`): once a version's persisted status is
  `published` or `archived`, its `definition` rejects every change at the
  changeset level. What did users see and attest to must always be
  answerable, so a fix is always a *new* version — never an edit.

  Changesets here can't bind `Repo.update_all` or raw SQL; the accompanying
  code convention is that no bulk write may ever target `definition`.

  ## Statuses

  `draft → published → archived`, whitelisted — enforced here, not in the
  database. Drafts are mutable working copies (several may coexist per
  lineage); `version` numbers and `published_at` are assigned only by
  `FormFlow.Data.Templates.Forms.update_status/3` and are never castable
  from external input, the same discipline as `lock_version` — casting a
  lock column would let a caller silently bypass the lock.

  `based_on_version_id` records which published version a draft forked from,
  powering the "based on v3, v4 has landed since" staleness warning. The
  published-only rule is enforced at draft creation (in the context, which
  can query); a base archived later leaves existing drafts valid.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias FormFlow.Data.Templates.Form

  @statuses ~w(draft published archived)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "form_flow_template_form_versions" do
    belongs_to(:template_form, Form, foreign_key: :template_form_id)

    field(:status, :string, default: "draft")
    field(:version, :integer)

    belongs_to(:based_on_version, __MODULE__, foreign_key: :based_on_version_id)

    field(:lock_version, :integer, default: 1)
    field(:definition, :map, default: %{})
    field(:published_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec)
  end

  def statuses, do: @statuses

  @doc """
  Builds a changeset for a new draft.

  Only the lineage, the definition, and the fork provenance are castable —
  a version is born a draft with no number.
  """
  def create_changeset(version, attrs \\ %{}) do
    version
    |> cast(attrs, [:template_form_id, :definition, :based_on_version_id])
    |> validate_required([:template_form_id])
    |> foreign_key_constraint(:template_form_id)
    |> foreign_key_constraint(:based_on_version_id)
  end

  @doc """
  Builds a changeset for editing a draft's definition.

  Fails on any persisted version whose status is not `draft` — published and
  archived definitions are immutable. Carries the optimistic lock, so two
  editors in the same draft get "this draft changed under you" instead of
  silent last-write-wins.
  """
  def update_changeset(version, attrs \\ %{}) do
    version
    |> cast(attrs, [:definition])
    |> reject_unless_draft()
    |> optimistic_lock(:lock_version)
  end

  @doc """
  Builds a changeset for a status transition.

  Whitelist: `draft → published` (which also stamps the assigned `version`
  number and `published_at` — supplied by the context, not cast) and
  `published → archived`. Everything else is rejected.
  """
  def status_changeset(version, "published", number, published_at) do
    version
    |> change()
    |> validate_transition("published")
    |> put_change(:version, number)
    |> put_change(:published_at, published_at)
    |> put_change(:status, "published")
    |> unique_constraint([:template_form_id, :version],
      name: :form_flow_template_form_versions_template_form_id_version_index
    )
  end

  def status_changeset(version, "archived") do
    version
    |> change()
    |> validate_transition("archived")
    |> put_change(:status, "archived")
  end

  defp reject_unless_draft(changeset) do
    persisted? = Ecto.get_meta(changeset.data, :state) == :loaded

    if persisted? and changeset.data.status != "draft" and changeset.changes != %{} do
      add_error(changeset, :definition, "cannot be changed after publishing")
    else
      changeset
    end
  end

  defp validate_transition(changeset, to) do
    from = changeset.data.status

    case {from, to} do
      {"draft", "published"} -> changeset
      {"published", "archived"} -> changeset
      _other -> add_error(changeset, :status, "cannot transition from #{from} to #{to}")
    end
  end
end
