defmodule FormFlow.Data.Graph.Node do
  @moduledoc """
  `FormFlow.Data.Graph.Node` Ecto Schema for a node in a graph.

  Follows Neo4j's property graph model: a node has `labels` (a set of strings —
  nodes can carry several) and `properties` (an open map of domain data). What a
  node *means* lives entirely in those two fields; the only structural columns
  are its identity and which graph it belongs to.

  `graph_id` is written to both locations: the dedicated column, so the
  database can index membership and cascade deletes, and a `"graph_id"` key
  inside `properties`, which is the copy that carries over to Neo4j, where
  there is no column. The changeset keeps the copy in sync — the column is
  authoritative, and a stale `"graph_id"` arriving in `properties` is
  overwritten.

  ## Subflows

  A node that embeds another graph carries that graph's id in `subflow_id` —
  the reference behind `FormFlow.Data.Graphs`' subflow operations. It follows
  the same dual-write rule as `graph_id`, with one addition: when only the
  `properties` copy arrives (the editor round-trips properties untouched), the
  column adopts it, so a subflow node surviving an editor save keeps its
  reference. In Neo4j this reference becomes an `EMBEDS` relationship — see
  the Neo4j guide (`guides/neo4j.md`).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias FormFlow.Data.Graph

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "form_flow_graph_nodes" do
    field(:labels, {:array, :string}, default: [])
    field(:properties, :map, default: %{})

    belongs_to(:graph, Graph)
    belongs_to(:subflow, Graph, foreign_key: :subflow_id)

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Builds a changeset for a node.

  `:id` is castable so callers can supply their own UUIDs — that is how ids
  stay stable when `FormFlow.Data.Graphs.update/2` replaces a graph's contents.
  """
  def changeset(node, attrs) do
    node
    |> cast(attrs, [:id, :graph_id, :subflow_id, :labels, :properties])
    |> validate_required([:graph_id])
    |> adopt_subflow_id_from_properties()
    |> copy_into_properties(:graph_id, "graph_id")
    |> copy_into_properties(:subflow_id, "subflow_id")
    |> foreign_key_constraint(:graph_id)
    |> foreign_key_constraint(:subflow_id)
  end

  # The editor round-trips properties untouched, so a saved subflow node
  # arrives with only the properties copy — the column adopts it. An explicit
  # :subflow_id in the attributes wins over the copy.
  defp adopt_subflow_id_from_properties(changeset) do
    properties = get_field(changeset, :properties) || %{}

    case {get_field(changeset, :subflow_id), properties["subflow_id"]} do
      {nil, id} when is_binary(id) ->
        case Ecto.UUID.cast(id) do
          {:ok, id} -> put_change(changeset, :subflow_id, id)
          :error -> add_error(changeset, :subflow_id, "is invalid")
        end

      _other ->
        changeset
    end
  end

  # The dual-write: properties carry a copy of the column, for Neo4j
  defp copy_into_properties(changeset, field, key) do
    case get_field(changeset, field) do
      nil ->
        changeset

      value ->
        properties = get_field(changeset, :properties) || %{}

        put_change(changeset, :properties, Map.put(properties, key, value))
    end
  end
end
