defmodule FormFlow.Graphs do
  @moduledoc """
  `FormFlow.Graphs` context module for `FormFlow.Graph` records.

  A graph is the aggregate: the `form_flow_graphs` row plus its
  `FormFlow.Graph.Node` and `FormFlow.Graph.Relationship` children. This module
  covers the lifecycle of the aggregate root — node- and relationship-level
  operations (adding steps, connecting them, replacing a graph's contents from
  the editor) come in a later phase.

  `list/0` deliberately does not load nodes and relationships; `get/1` does.
  """

  import Ecto.Query

  alias FormFlow.Data.Repo
  alias FormFlow.Graph

  @doc """
  Returns all graphs, oldest first, without their nodes and relationships.
  """
  def list do
    Repo.all(from(g in Graph, order_by: [asc: g.inserted_at]))
  end

  @doc """
  Fetches one graph by id with its nodes and relationships loaded, or `nil`.
  """
  def get(id) do
    case Repo.get(Graph, id) do
      nil -> nil
      graph -> Repo.preload(graph, [:nodes, :relationships])
    end
  end

  @doc """
  Creates a graph.

      {:ok, graph} = FormFlow.Graphs.create()
  """
  def create(attrs \\ %{}) do
    %Graph{}
    |> Graph.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a graph's own fields.

  The graph row is just an identity today, so this is plumbing for graph-level
  fields to come — it does not touch nodes or relationships.
  """
  def update(%Graph{} = graph, attrs) do
    graph
    |> Graph.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a graph and, through database cascades, every node and relationship
  in it.
  """
  def delete(%Graph{} = graph) do
    Repo.delete(graph)
  end
end
