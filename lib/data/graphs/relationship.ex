defmodule FormFlow.Data.Graph.Relationship do
  @moduledoc """
  `FormFlow.Data.Graph.Relationship` Ecto Schema for a directed relationship
  between two nodes in a graph.

  Follows Neo4j's property graph model: a relationship connects a `source` node
  to a `target` node, carries a single `label` (where a node carries many), and
  has `properties` of its own — edge data like conditions or display hints
  belongs there, not on the nodes it connects.

  A source/target pair can only be linked once per label. That is a deliberate
  divergence from Neo4j, where parallel relationships are legal — in a flow
  diagram a duplicate connection is a data error.

  Deleting either endpoint node deletes the relationship (Neo4j's DETACH DELETE
  as the only mode), enforced by the database.

  `graph_id` is written to both locations: the dedicated column, so the
  database can index membership and cascade deletes, and a `"graph_id"` key
  inside `properties`, which is the copy that carries over to Neo4j, where
  there is no column. The changeset keeps the copy in sync — the column is
  authoritative, and a stale `"graph_id"` arriving in `properties` is
  overwritten.

  The labels `IN`, `EMBEDS`, and `OWNED_BY` are reserved: they become
  FormFlow's structural relationship types when the Neo4j dual-write lands.
  See the Neo4j guide (`guides/neo4j.md`).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias FormFlow.Data.Graph
  alias FormFlow.Data.Graph.Node

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "form_flow_graph_relationships" do
    field(:label, :string)
    field(:properties, :map, default: %{})

    belongs_to(:graph, Graph)
    belongs_to(:source, Node)
    belongs_to(:target, Node)

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Builds a changeset for a relationship.

  `:id` is castable so callers can supply their own UUIDs — that is how ids
  stay stable when `FormFlow.Data.Graphs.update/2` replaces a graph's contents.
  """
  def changeset(relationship, attrs) do
    relationship
    |> cast(attrs, [:id, :graph_id, :source_id, :target_id, :label, :properties])
    |> validate_required([:graph_id, :source_id, :target_id, :label])
    |> validate_exclusion(:label, ~w(IN EMBEDS OWNED_BY), message: "is reserved by FormFlow")
    |> copy_graph_id_into_properties()
    |> foreign_key_constraint(:graph_id)
    |> foreign_key_constraint(:source_id)
    |> foreign_key_constraint(:target_id)
    |> unique_constraint([:source_id, :target_id, :label])
  end

  # The dual-write: properties carry a copy of the graph_id column, for Neo4j
  defp copy_graph_id_into_properties(changeset) do
    case get_field(changeset, :graph_id) do
      nil ->
        changeset

      graph_id ->
        properties = get_field(changeset, :properties) || %{}

        put_change(changeset, :properties, Map.put(properties, "graph_id", graph_id))
    end
  end
end
