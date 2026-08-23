defmodule FormFlow.Graph.Node do
  @moduledoc """
  `FormFlow.Graph.Node` Ecto Schema for a node in a graph.

  Follows Neo4j's property graph model: a node has `labels` (a set of strings —
  nodes can carry several) and `properties` (an open map of domain data). What a
  node *means* lives entirely in those two fields; the only structural columns
  are its identity and which graph it belongs to.

  `graph_id` is a real column rather than a property so the database can index
  membership and cascade deletes. When Neo4j support arrives it folds back into
  the property map at the mapping layer.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias FormFlow.Graph

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "form_flow_graph_nodes" do
    field(:labels, {:array, :string}, default: [])
    field(:properties, :map, default: %{})

    belongs_to(:graph, Graph)

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Builds a changeset for a node.
  """
  def changeset(node, attrs) do
    node
    |> cast(attrs, [:graph_id, :labels, :properties])
    |> validate_required([:graph_id])
    |> foreign_key_constraint(:graph_id)
  end
end
