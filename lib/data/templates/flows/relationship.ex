defmodule FormFlow.Data.Templates.Flow.Relationship do
  @moduledoc """
  `FormFlow.Data.Templates.Flow.Relationship` Ecto Schema for a directed
  relationship between two nodes in a flow.

  Follows Neo4j's property graph model: a relationship connects a `source` node
  to a `target` node, carries a single `label` (where a node carries many), and
  has `properties` of its own — edge data like conditions or display hints
  belongs there, not on the nodes it connects.

  A source/target pair can only be linked once per label. That is a deliberate
  divergence from Neo4j, where parallel relationships are legal — in a flow
  diagram a duplicate connection is a data error.

  Deleting either endpoint node deletes the relationship (Neo4j's DETACH DELETE
  as the only mode), enforced by the database.

  `flow_id` is written to both locations: the dedicated column, so the
  database can index membership and cascade deletes, and a `"flow_id"` key
  inside `properties`, which is the copy that carries over to Neo4j, where
  there is no column. The changeset keeps the copy in sync — the column is
  authoritative, and a stale `"flow_id"` arriving in `properties` is
  overwritten. `tenant_id` — the flow's, stamped at insert — is written the
  same way, so the Neo4j property map carries the tenant on every edge as
  well as every node, and so does the relationship's own `id`.

  The labels `IN`, `EMBEDS`, and `OWNED_BY` are reserved: they become
  FormFlow's structural relationship types when the Neo4j dual-write lands.
  See the Neo4j guide (`guides/neo4j.md`).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias FormFlow.Data.Templates.Flow
  alias FormFlow.Data.Templates.Flow.Node

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "form_flow_template_flow_relationships" do
    field(:label, :string)
    field(:properties, :map, default: %{})
    field(:tenant_id, :string)

    belongs_to(:flow, Flow)
    belongs_to(:source, Node)
    belongs_to(:target, Node)

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Builds a changeset for a relationship.

  `:id` is castable so callers can supply their own UUIDs — that is how ids
  stay stable when `FormFlow.Data.Templates.Flows.update/2` replaces a flow's
  contents.
  """
  def changeset(relationship, attrs) do
    relationship
    |> cast(attrs, [:id, :flow_id, :tenant_id, :source_id, :target_id, :label, :properties])
    |> validate_required([:flow_id, :source_id, :target_id, :label])
    |> validate_exclusion(:label, ~w(IN EMBEDS OWNED_BY), message: "is reserved by FormFlow")
    |> put_new_id()
    |> copy_into_properties(:id, "id")
    |> copy_into_properties(:flow_id, "flow_id")
    |> copy_into_properties(:tenant_id, "tenant_id")
    |> foreign_key_constraint(:flow_id)
    |> foreign_key_constraint(:source_id)
    |> foreign_key_constraint(:target_id)
    # Two names for one index. Postgres reports the index's own name, which the
    # migration spells out because the name Ecto would derive is longer than
    # Postgres allows an identifier to be. SQLite has no way to report the name
    # at all, so its adapter rebuilds Ecto's from the columns in the violation.
    |> unique_constraint([:source_id, :target_id, :label],
      name: :form_flow_template_flow_relationships_source_target_label_index
    )
    |> unique_constraint([:source_id, :target_id, :label])
  end

  # The id has to exist before it can be copied into `properties`; see the
  # same helper on `FormFlow.Data.Templates.Flow.Node`.
  defp put_new_id(changeset) do
    case get_field(changeset, :id) do
      nil -> put_change(changeset, :id, Ecto.UUID.generate())
      _id -> changeset
    end
  end

  # The dual-write: properties carry a copy of the column, for Neo4j — and
  # none when the column is empty
  defp copy_into_properties(changeset, field, key) do
    properties = get_field(changeset, :properties) || %{}

    properties =
      case get_field(changeset, field) do
        nil -> Map.delete(properties, key)
        value -> Map.put(properties, key, value)
      end

    put_change(changeset, :properties, properties)
  end
end
