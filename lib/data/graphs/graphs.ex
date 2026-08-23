defmodule FormFlow.Data.Graphs do
  @moduledoc """
  `FormFlow.Data.Graphs` context module for `FormFlow.Data.Graph` records.

  A graph is the aggregate: the `form_flow_graphs` row plus its
  `FormFlow.Data.Graph.Node` and `FormFlow.Data.Graph.Relationship` children.
  `create/1` and `update/2` accept the whole aggregate — pass `:nodes` and
  `:relationships` in the attributes and the contents are written alongside the
  row, in one transaction, nodes before the relationships that reference them.

  `list/0` deliberately does not load nodes and relationships; `get/1` does.

  ## Subflows and ownership

  A node whose `subflow_id` is set embeds another graph. By default such
  graphs are private: their `owner_graph_id` points at the root flow they
  belong to (the ownership root — flat, not the immediate parent), and they
  are cleaned up automatically when they stop being referenced (see
  `update/2`) or when their root is deleted.

  `make_reusable/1` detaches a graph from its owner and stamps
  `made_reusable_at`, putting it in the catalog `list_reusable/0` returns.
  Reusable graphs can be referenced by many flows — edits show up everywhere —
  or copied with `duplicate/2` for a private point-in-time copy.

  See the Neo4j guide (`guides/neo4j.md`) for how all of this maps onto a
  graph database when the dual-write extension lands.
  """

  import Ecto.Query

  alias FormFlow.Data.Graph
  alias FormFlow.Data.Graph.Node
  alias FormFlow.Data.Graph.Relationship
  alias FormFlow.Data.Repo

  @doc """
  Returns all graphs, oldest first, without their nodes and relationships —
  just the counts, in the `:nodes_count` and `:relationships_count` virtual
  fields, as summary data for listings.
  """
  def list do
    Repo.all(
      from(g in Graph,
        left_join: n in assoc(g, :nodes),
        left_join: r in assoc(g, :relationships),
        group_by: g.id,
        order_by: [asc: g.inserted_at],
        select: %{
          g
          | nodes_count: count(n.id, :distinct),
            relationships_count: count(r.id, :distinct)
        }
      )
    )
  end

  @doc """
  Returns the reusable catalog: graphs made reusable, newest first.

  Backed by a partial index on `made_reusable_at`, so this is a real-time
  query — no caching needed.
  """
  def list_reusable do
    Repo.all(
      from(g in Graph,
        where: not is_nil(g.made_reusable_at),
        order_by: [desc: g.made_reusable_at]
      )
    )
  end

  @doc """
  Fetches one graph by id with its nodes and relationships loaded, or `nil`.

  Ids often arrive from URLs, so anything that is not a UUID is `nil` rather
  than an `Ecto.Query.CastError`.
  """
  def get(id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Graph{} = graph <- Repo.get(Graph, id) do
      Repo.preload(graph, [:nodes, :relationships])
    else
      _other -> nil
    end
  end

  @doc """
  Whether the graph is some root flow's private property.

  Unowned graphs are root flows or reusable subflows — structurally the same
  thing; `made_reusable_at` is what lists a graph in the reusable catalog.
  """
  def owned?(%Graph{owner_graph_id: nil}), do: false
  def owned?(%Graph{}), do: true

  @doc """
  Creates a graph, along with any nodes and relationships in the attributes.

      {:ok, graph} = FormFlow.Data.Graphs.create()
      {:ok, graph} = FormFlow.Data.Graphs.create(%{nodes: [...], relationships: [...]})

  Pass `:owner_graph_id` to create a graph owned by a root flow — the default
  for subflows.
  """
  def create(attrs \\ %{}) do
    save(Graph.changeset(%Graph{}, attrs), attrs, &Repo.insert/1)
  end

  @doc """
  Updates a graph.

  When `attrs` include `:nodes` or `:relationships`, the graph's contents are
  replaced to match — existing rows are deleted and the given ones written.
  Attributes without contents leave the contents untouched.

  Replacing contents also garbage-collects: owned graphs in the same ownership
  domain that are no longer reachable through subflow references are deleted,
  with everything under them. Removing a subflow node from the canvas is how
  an owned subflow (and its whole private subtree) goes away.
  """
  def update(%Graph{} = graph, attrs) do
    save(Graph.changeset(graph, attrs), attrs, &Repo.update/1)
  end

  @doc """
  Deletes a graph, everything it owns, and their nodes and relationships.

  Refused with an error changeset while other flows still reference the graph
  as a subflow — remove those references (or `duplicate/2` first) and retry.
  """
  def delete(%Graph{} = graph) do
    Repo.transaction(fn ->
      owned_ids =
        Repo.all(from(g in Graph, where: g.owner_graph_id == ^graph.id, select: g.id))

      tree_ids = [graph.id | owned_ids]

      referenced? =
        Repo.exists?(
          from(n in Node, where: n.subflow_id == ^graph.id and n.graph_id not in ^tree_ids)
        )

      if referenced? do
        graph
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.add_error(:id, "is still used as a subflow by another flow")
        |> Repo.rollback()
      else
        delete_graphs(tree_ids)
        graph
      end
    end)
  end

  @doc """
  Makes a graph reusable: detaches it from its owner and stamps
  `made_reusable_at`, which lists it in `list_reusable/0`.

  Its private descendants stay private — they are re-homed from the old
  ownership root to this graph, which becomes the root of its own ownership
  domain. Already-reusable graphs pass through unchanged.
  """
  def make_reusable(%Graph{made_reusable_at: %DateTime{}} = graph), do: {:ok, graph}

  def make_reusable(%Graph{} = graph) do
    Repo.transaction(fn ->
      old_owner_id = graph.owner_graph_id

      {:ok, graph} =
        graph
        |> Ecto.Changeset.change(owner_graph_id: nil, made_reusable_at: DateTime.utc_now())
        |> Repo.update()

      if old_owner_id do
        rehome_ids = reachable_owned([graph.id], old_owner_id)

        Repo.update_all(
          from(g in Graph, where: g.id in ^rehome_ids),
          set: [owner_graph_id: graph.id]
        )
      end

      graph
    end)
  end

  @doc """
  Deep-copies a graph: a new graph with new UUIDs throughout, its contents
  copied, relationships re-pointed at the copied nodes.

  Subflow references follow the copy boundary: graphs the source *owns* are
  deep-copied along with it; *reusable* graphs stay shared references. The
  copy is never in the reusable catalog — `made_reusable_at` starts empty.

      {:ok, copy} = FormFlow.Data.Graphs.duplicate(graph)
      {:ok, copy} = FormFlow.Data.Graphs.duplicate(graph, owner_graph_id: root.id)
  """
  def duplicate(%Graph{} = graph, opts \\ []) do
    owner_id = Keyword.get(opts, :owner_graph_id)

    Repo.transaction(fn ->
      copy_id = copy_graph(graph.id, owner_id, nil)

      Repo.preload(Repo.get(Graph, copy_id), [:nodes, :relationships])
    end)
  end

  defp save(changeset, attrs, operation) do
    Repo.transaction(fn ->
      with {:ok, graph} <- operation.(changeset),
           {:ok, graph} <- replace_contents(graph, attrs) do
        graph
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp replace_contents(graph, attrs) do
    if Map.has_key?(attrs, :nodes) or Map.has_key?(attrs, :relationships) do
      # Deleting the nodes cascades to any relationships that referenced them
      Repo.delete_all(from(n in Node, where: n.graph_id == ^graph.id))
      Repo.delete_all(from(r in Relationship, where: r.graph_id == ^graph.id))

      with {:ok, _nodes} <- insert_contents(graph, Node, Map.get(attrs, :nodes, [])),
           {:ok, _rels} <-
             insert_contents(graph, Relationship, Map.get(attrs, :relationships, [])) do
        sweep_unreachable(graph)

        {:ok, graph}
      end
    else
      {:ok, graph}
    end
  end

  defp insert_contents(graph, schema, attrs_list) do
    Enum.reduce_while(attrs_list, {:ok, []}, fn attrs, {:ok, inserted} ->
      changeset = schema.changeset(struct(schema), Map.put(attrs, :graph_id, graph.id))

      case Repo.insert(changeset) do
        {:ok, record} -> {:cont, {:ok, [record | inserted]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  # Garbage collection after a save: owned graphs in this ownership domain
  # that are no longer reachable through subflow references get deleted, with
  # their contents. Multi-level removal comes for free — a removed subflow's
  # own children stop being reachable too.
  defp sweep_unreachable(graph) do
    root_id = graph.owner_graph_id || graph.id
    reachable = reachable_owned([root_id], root_id)

    doomed =
      Repo.all(
        from(g in Graph,
          where: g.owner_graph_id == ^root_id and g.id not in ^reachable,
          select: g.id
        )
      )

    if doomed != [], do: delete_graphs(doomed)

    :ok
  end

  # Graphs owned by `owner_id` reachable by following subflow references out
  # of `frontier`. Within one ownership domain the reference structure is a
  # tree, but the seen-set guards against cycles regardless.
  defp reachable_owned(frontier, owner_id), do: reachable_owned(frontier, owner_id, MapSet.new())

  defp reachable_owned([], _owner_id, seen), do: MapSet.to_list(seen)

  defp reachable_owned(frontier, owner_id, seen) do
    children =
      Repo.all(
        from(n in Node,
          join: g in Graph,
          on: g.id == n.subflow_id,
          where: n.graph_id in ^frontier and g.owner_graph_id == ^owner_id,
          distinct: true,
          select: g.id
        )
      )

    new = Enum.reject(children, &MapSet.member?(seen, &1))

    reachable_owned(new, owner_id, Enum.into(new, seen))
  end

  # Deletes graphs in an order that never trips the subflow foreign key:
  # nodes first (removing every subflow reference; their relationships cascade),
  # then the graph rows themselves.
  defp delete_graphs(ids) do
    Repo.delete_all(from(n in Node, where: n.graph_id in ^ids))
    Repo.delete_all(from(g in Graph, where: g.id in ^ids))

    :ok
  end

  # Copies one graph and, recursively, everything it owns. `domain_id` is the
  # ownership root of the new tree: the requested owner, or the top copy
  # itself once it exists.
  defp copy_graph(source_id, owner_id, domain_id) do
    source = get(source_id)
    copy_id = Ecto.UUID.generate()
    domain_id = domain_id || owner_id || copy_id

    {:ok, _graph} =
      %Graph{id: copy_id}
      |> Ecto.Changeset.change(owner_graph_id: owner_id)
      |> Repo.insert()

    node_ids = Map.new(source.nodes, fn node -> {node.id, Ecto.UUID.generate()} end)

    Enum.each(source.nodes, fn node ->
      {:ok, _node} =
        %Node{}
        |> Node.changeset(%{
          id: node_ids[node.id],
          graph_id: copy_id,
          subflow_id: copy_subflow_reference(node.subflow_id, domain_id),
          labels: node.labels,
          properties: node.properties
        })
        |> Repo.insert()
    end)

    Enum.each(source.relationships, fn relationship ->
      {:ok, _relationship} =
        %Relationship{}
        |> Relationship.changeset(%{
          id: Ecto.UUID.generate(),
          graph_id: copy_id,
          source_id: node_ids[relationship.source_id],
          target_id: node_ids[relationship.target_id],
          label: relationship.label,
          properties: relationship.properties
        })
        |> Repo.insert()
    end)

    copy_id
  end

  defp copy_subflow_reference(nil, _domain_id), do: nil

  defp copy_subflow_reference(subflow_id, domain_id) do
    # The copy boundary: owned graphs are copied into the new domain,
    # reusable graphs stay shared references
    case Repo.get(Graph, subflow_id) do
      %Graph{owner_graph_id: nil} -> subflow_id
      %Graph{} -> copy_graph(subflow_id, domain_id, domain_id)
      nil -> nil
    end
  end
end
