defmodule FormFlow.Data.Templates.Flow.Snapshot do
  @moduledoc """
  `FormFlow.Data.Templates.Flow.Snapshot` Ecto Schema for a template flow
  snapshot: the whole of one root flow - every flow of its tree, every
  node, every relationship - as `FormFlow.Data.Templates.Flows.resolve_tree/1`
  loaded it at one moment, held as JSON in `data`.

  A journey (`FormFlow.Data.Instances.Flow`) records a snapshot when it
  starts and reads its flow from it ever after, never from the live
  template: the flow an admin goes on editing is not the flow a user
  part-way through is walking. Editing stays what it is - many small
  saves; no draft, no publish, no flow versions. The snapshot is taken on
  demand, at start (`FormFlow.Data.Templates.Flows.Snapshots.get_or_create/2`):
  the live tree is loaded, hashed, and matched against the root's existing
  snapshots; a hit is reused, a miss inserted. A hundred saves between two
  starts make one snapshot; a save nobody starts against makes none.

  ## What `data` holds

  The tree as the loader returns it, as JSON primitives: `"flow"`,
  `"nodes"`, `"relationships"`, and `"subflows"` keyed by the embedding
  node's id, recursively. Every column of every row - timestamps included,
  as ISO 8601 strings - and the whole `properties` map of every row, canvas
  positions and perspective ids included, in the loader's order. No
  sorting, no canonical form, no key list to maintain: `take/1` reads each
  schema's own field list, so a column added later is in the next snapshot
  without a change here.

  Three things are left out, each because an admin did not write it: the
  flow's `status`, which is read live when the snapshot is read back; the
  virtual counts a listing fills; and every `_`-prefixed key in any
  `properties` map, the library's own bookkeeping (`_health_metadata`
  today).

  So **any save followed by a start is a new snapshot** - a drag, a rename,
  a save with nothing changed, since a save re-inserts every node and
  relationship and moves their timestamps. A status change is one too: it
  moves the flow row's `updated_at`. Snapshots mean "the rows changed",
  not "the logic changed"; a duplicate costs a row nobody reads - some
  tens of kilobytes of JSON for a flow of a few dozen steps - and there
  is no second definition of "changed" for a dialog to disagree with. A
  health refresh makes none: it writes through `update_all`, and the key
  it writes is stripped.

  Perspectives freeze with the rest of `properties`. Who may see a step is
  a property of the flow holding it, so a journey keeps the visibility
  rule it started with; an admin changing that rule reaches journeys in
  flight through the editor's Move, the same door as every other change.

  A diamond - one subflow referenced from two sibling steps - is held once
  per position, as `resolve_tree/1` resolves it: each position is a
  distinct traversal.

  Form templates appear by id only. Each form instance records its own
  `template_form_version_id`, and the form template rows are loaded live
  when the snapshot is read back - so a form template is one row, never
  copied into every snapshot of every flow that uses it.

  ## Columns

  `template_flow_id` is the root; `number` counts the root's snapshots 1,
  2, 3 - and names a row, not a place in a history: after a prune
  (`FormFlow.Data.Templates.Flows.Snapshots.delete_unreferenced/1`) the
  next snapshot takes the highest number left plus one, which may be one
  a pruned row wore. `checksum` is SHA-256 over the encoded `data`, and
  `(template_flow_id, checksum)` is unique so one tree is one row.
  `tenant_id` is the root's. Nothing updates a snapshot row today -
  `updated_at` is there because leaving it out would constrain a future
  change, not describe the data. Rows are written by `get_or_create/2`
  alone; nothing casts them from outside.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias FormFlow.Data.Templates.Flow

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "form_flow_template_flow_snapshots" do
    belongs_to(:template_flow, Flow)

    field(:tenant_id, :string)
    field(:number, :integer)
    field(:checksum, :string)
    field(:data, :map)

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  The changeset `FormFlow.Data.Templates.Flows.Snapshots.get_or_create/2`
  inserts with. Both unique indexes are named, so a concurrent start that
  wins the race comes back as a changeset error rather than a raise.
  """
  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [:template_flow_id, :tenant_id, :number, :checksum, :data])
    |> validate_required([:template_flow_id, :number, :checksum, :data])
    |> foreign_key_constraint(:template_flow_id)
    |> unique_constraint([:template_flow_id, :number],
      name: :form_flow_template_flow_snapshots_flow_id_number_index
    )
    |> unique_constraint([:template_flow_id, :checksum],
      name: :form_flow_template_flow_snapshots_flow_id_checksum_index
    )
  end

  @doc """
  The `data` map for a resolved tree (`FormFlow.Data.Templates.Flows.resolve_tree/1`):
  string keys and JSON primitives throughout, so the map returned here is
  the map the row holds and `checksum/1` can be re-verified from a row.
  The `nil` clause is for the recursion into a subtree whose flow is gone,
  not for a caller: `data` is not null, and `get_or_create/2` takes a
  tree.
  """
  @spec take(map() | nil) :: map() | nil
  def take(nil), do: nil

  def take(%{
        flow: %Flow{} = flow,
        nodes: nodes,
        relationships: relationships,
        subflows: subflows
      }) do
    %{
      "flow" => row(flow, [:status]),
      "nodes" => Enum.map(nodes, &row(&1, [])),
      "relationships" => Enum.map(relationships, &row(&1, [])),
      "subflows" => Map.new(subflows, fn {node_id, subtree} -> {node_id, take(subtree)} end)
    }
  end

  @doc "SHA-256 of the JSON encoding of `data`, as lowercase hex."
  @spec checksum(map()) :: String.t()
  def checksum(data) do
    :crypto.hash(:sha256, Jason.encode!(data)) |> Base.encode16(case: :lower)
  end

  # Every column the schema declares, less `drop`, as a string-keyed map
  # of JSON primitives. Virtual fields are not in `__schema__(:fields)`, so
  # the counts a listing fills never arrive here.
  defp row(%schema{} = struct, drop) do
    for field <- schema.__schema__(:fields), field not in drop, into: %{} do
      {Atom.to_string(field), primitive(field, Map.fetch!(struct, field))}
    end
  end

  # The library's own bookkeeping in a `properties` map is not something
  # an admin wrote, so it is no part of what changed
  defp primitive(:properties, %{} = properties) do
    Map.reject(properties, fn {key, _value} -> bookkeeping?(key) end)
  end

  defp primitive(_field, %DateTime{} = at), do: DateTime.to_iso8601(at)
  defp primitive(_field, value), do: value

  defp bookkeeping?(key) when is_binary(key), do: String.starts_with?(key, "_")
  defp bookkeeping?(_key), do: false
end
