defmodule FormFlow.Graph do
  @moduledoc """
  `FormFlow.Graph` Ecto Schema for a graph — the aggregate root the nodes and
  relationships of one flow diagram hang off.

  The row itself is just an identity (`form_flow_graphs` has only an id and
  timestamps for now); the substance lives in the associated `FormFlow.Graph.Node`
  and `FormFlow.Graph.Relationship` records, following Neo4j's property graph
  vocabulary. `FormFlow.Graphs.get/1` returns the whole aggregate with both
  associations loaded.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias FormFlow.Graph.Node
  alias FormFlow.Graph.Relationship

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "form_flow_graphs" do
    has_many(:nodes, Node)
    has_many(:relationships, Relationship)

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Builds a changeset for a graph.

  There are no castable fields yet — the row is an identity — but every write
  goes through here so graph-level fields added later slot in without callers
  changing.
  """
  def changeset(graph, attrs \\ %{}) do
    cast(graph, attrs, [])
  end
end
