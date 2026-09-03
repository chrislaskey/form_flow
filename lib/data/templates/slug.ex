defmodule FormFlow.Data.Templates.Slug do
  @moduledoc """
  `FormFlow.Data.Templates.Slug` — the secondary identifier of a
  `FormFlow.Data.Templates.Flow` or `FormFlow.Data.Templates.Form`.

  A slug is a stable, human-chosen name a host can look a template up by
  (`FormFlow.Data.Templates.Flows.get_by_slug/2`,
  `FormFlow.Data.Templates.Forms.get_by_slug/2`) without knowing the `id`,
  which differs between environments. It is optional, unique per tenant
  within its table, and never used as a foreign key. It never follows a
  rename: once set it stays until an admin changes it.

  ## Generation

  Nothing requires a slug, but every template gets one by default so the
  host has something to look up. A template created without one is named
  from its `name`, one **segment** of at most ten characters — lowercase
  letters and digits only:

    * one or two words concatenate and truncate: "User Information" is
      `userinform`
    * three or more words take each word's first letter, keeping all-digit
      words whole: "Dog License Application 2026" is `dla2026`
    * a name with nothing usable falls back to the kind: `flow` or `form`

  Owned children — the subflows and forms a save creates for the nodes on a
  canvas — prefix their segment with the slug of the flow that contains
  them, joined by `_`, so a form "User Information" inside `dla2026` is
  `dla2026_userinform`, and a form inside a subflow of it carries the whole
  chain. A slug already taken in the tenant gets `-2`, `-3`, … appended,
  chosen by querying the existing ones (`available/3`) rather than by
  retrying the insert, since a violated constraint aborts the enclosing
  transaction on Postgres. The unique index stays as the backstop for the
  rare race.

  ## Hand-written slugs

  `validate_slug/2` runs in both template changesets: lowercase, `[a-z0-9]`
  plus `_` and `-`, at most `max_length/0` characters, unique per tenant. A
  blank slug is `nil` — a template may legitimately have none.
  """

  import Ecto.Changeset
  import Ecto.Query

  alias FormFlow.Data.Repo

  @segment_length 10
  @max_length 100
  @format ~r/^[a-z0-9][a-z0-9_-]*$/

  @doc "The longest slug the changesets accept."
  def max_length, do: @max_length

  @doc """
  The slug segment for `name` — see the moduledoc for the rule — or
  `fallback` when the name has nothing usable in it.
  """
  def segment(name, fallback) do
    case words(name) do
      [] ->
        fallback

      words when length(words) <= 2 ->
        words |> Enum.join() |> String.slice(0, @segment_length)

      words ->
        words |> Enum.map_join(&initial/1) |> String.slice(0, @segment_length)
    end
  end

  defp words(nil), do: []

  defp words(name) do
    name
    |> String.normalize(:nfd)
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s]/u, "")
    |> String.split()
  end

  defp initial(word) do
    if String.match?(word, ~r/^\d+$/), do: word, else: String.first(word)
  end

  @doc "A child's slug: its segment under the containing flow's slug."
  def join(nil, segment), do: segment
  def join(prefix, segment), do: prefix <> "_" <> segment

  @doc """
  `slug` with the old root prefix swapped for the new one — what a copied
  child gets when its root is copied under a new slug. A slug not under the
  old prefix (one an admin wrote by hand) is returned as it is.
  """
  def rewrite(nil, _old_prefix, _new_prefix), do: nil
  def rewrite(slug, nil, _new_prefix), do: slug
  def rewrite(slug, _old_prefix, nil), do: slug

  def rewrite(slug, old_prefix, new_prefix) do
    String.replace_prefix(slug, old_prefix <> "_", new_prefix <> "_")
  end

  @doc """
  `candidate` if no row of `schema` in the tenant has it, otherwise the first
  free `candidate-2`, `candidate-3`, …. A `nil` tenant is the scope of rows
  with no tenant — the whole table, for a host with no tenants.
  """
  def available(_schema, nil, _tenant_id), do: nil

  def available(schema, candidate, tenant_id) do
    taken = taken(schema, candidate, tenant_id)

    if MapSet.member?(taken, candidate),
      do: first_free_suffix(candidate, taken),
      else: candidate
  end

  defp first_free_suffix(candidate, taken) do
    Stream.iterate(2, &(&1 + 1))
    |> Stream.map(&"#{candidate}-#{&1}")
    |> Enum.find(&(not MapSet.member?(taken, &1)))
  end

  # Every slug starting with the candidate — a superset of what could
  # collide (LIKE treats the candidate's underscores as wildcards, which
  # only widens the match), so the suffix chosen is always free
  defp taken(schema, candidate, tenant_id) do
    query = from(s in schema, where: like(s.slug, ^(candidate <> "%")), select: s.slug)

    query =
      case tenant_id do
        nil -> from(s in query, where: is_nil(s.tenant_id))
        tenant_id -> from(s in query, where: s.tenant_id == ^tenant_id)
      end

    MapSet.new(Repo.all(query))
  end

  @doc """
  The changeset rules for a slug — normalized to lowercase and trimmed,
  format and length checked, and the tenant-scoped unique index mapped to a
  `:slug` error by `index_name`.
  """
  def validate_slug(changeset, index_name) do
    changeset
    |> update_change(:slug, &normalize/1)
    |> validate_format(:slug, @format,
      message: "may only contain lowercase letters, numbers, _ and -"
    )
    |> validate_length(:slug, max: @max_length)
    |> unique_constraint(:slug, name: index_name)
  end

  defp normalize(nil), do: nil

  defp normalize(slug) do
    case slug |> String.trim() |> String.downcase() do
      "" -> nil
      slug -> slug
    end
  end

  @doc """
  `attrs` with `slug` filled in when they carry none — atom or string keys,
  matching what is already there, since `Ecto.Changeset.cast/4` refuses a
  mix.
  """
  def put_default(attrs, slug) do
    case get(attrs, :slug) do
      blank when blank in [nil, ""] -> put(attrs, :slug, slug)
      _slug -> attrs
    end
  end

  @doc "An attribute by atom or string key."
  def get(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, to_string(key))

  defp put(attrs, key, value) do
    if Enum.any?(Map.keys(attrs), &is_binary/1),
      do: Map.put(attrs, to_string(key), value),
      else: Map.put(attrs, key, value)
  end
end
