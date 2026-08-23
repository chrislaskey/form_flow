defmodule FormFlow.Graph.Relationship do
  @moduledoc """
  `FormFlow.Graph.Relationship` Ecto Schema for a directed relationship between
  two nodes in a graph.

  Follows Neo4j's property graph model: a relationship connects a `source` node
  to a `target` node, carries a single `label` (where a node carries many), and
  has `properties` of its own — edge data like conditions or display hints
  belongs there, not on the nodes it connects.

  A source/target pair can only be linked once per label. That is a deliberate
  divergence from Neo4j, where parallel relationships are legal — in a flow
  diagram a duplicate connection is a data error.

  Deleting either endpoint node deletes the relationship (Neo4j's DETACH DELETE
  as the only mode), enforced by the database.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias FormFlow.Graph
  alias FormFlow.Graph.Node

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
  """
  def changeset(relationship, attrs) do
    relationship
    |> cast(attrs, [:graph_id, :source_id, :target_id, :label, :properties])
    |> validate_required([:graph_id, :source_id, :target_id, :label])
    |> foreign_key_constraint(:graph_id)
    |> foreign_key_constraint(:source_id)
    |> foreign_key_constraint(:target_id)
    |> unique_constraint([:source_id, :target_id, :label])
  end
end
