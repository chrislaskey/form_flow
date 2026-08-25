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

  ## Declared flavor

  Every graph declares its flavor at creation in `label`: `"forms"` flows
  contain form steps, `"subflows"` flows contain subflow steps — never mixed
  (structural Start/End nodes are exempt). Saves validate the rule, and the
  label is immutable: converting means wrapping in a new parent flow.

  Saving a `"subflows"` graph also creates the children: any subflow node
  without a `subflow_id` gets a fresh graph — owned by the root, seeded with
  `starter_nodes/0`, named from the node's canvas label, its own label taken
  from the node's `data.subflow_label` (declared when the node was added in
  the editor) — and the node is pointed at it.

  See the Neo4j guide (`guides/neo4j.md`) for how all of this maps onto a
  graph database when the dual-write extension lands.
  """

  import Ecto.Query

  alias FormFlow.Data.Graph
  alias FormFlow.Data.Graph.Node
  alias FormFlow.Data.Graph.Relationship
  alias FormFlow.Data.Repo
  alias FormFlow.Data.Templates

  @doc """
  Returns the top-level flows — root flows and reusable subflows — oldest
  first, without their nodes and relationships; just the counts, in the
  `:nodes_count` and `:relationships_count` virtual fields, as summary data
  for listings.

  Owned subflow children are deliberately excluded: they live inside their
  root and are reached by drill-in, not listed beside it.
  """
  def list do
    Repo.all(
      from(g in Graph,
        where: is_nil(g.owner_graph_id),
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
  Fetches one node by id, or `nil`. Drill-in URLs carry node ids — the node's
  `subflow_id` is the graph they open.
  """
  def get_node(id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Node{} = node <- Repo.get(Node, id) do
      node
    else
      _other -> nil
    end
  end

  @doc """
  The node within an ownership domain that embeds the given graph, or `nil`.

  Used to build the drill-in URL of a graph's *containing* page: the node's id
  is the `/flows/:root/nodes/:node_id` segment. Scoped to the domain because a
  reusable graph can be embedded by many flows — only the usage under this
  root is wanted.
  """
  def embedding_node(graph_id, root_id) do
    case Ecto.UUID.cast(root_id) do
      {:ok, root_id} ->
        Repo.one(
          from(n in Node,
            join: g in Graph,
            on: g.id == n.graph_id,
            where:
              n.subflow_id == ^graph_id and
                (g.id == ^root_id or g.owner_graph_id == ^root_id),
            limit: 1
          )
        )

      :error ->
        nil
    end
  end

  @doc """
  The node attributes every flow starts from: a pinned `Start` and `End`,
  nothing else — the user connects the dots. One universal seed for both
  flavors, used for new flows and for subflow children created at save.
  """
  def starter_nodes do
    [
      %{
        labels: [],
        properties: %{
          "type" => "step",
          "position" => %{"x" => 240, "y" => 0},
          "deletable" => false,
          "data" => %{"label" => "Start", "kind" => "start"}
        }
      },
      %{
        labels: [],
        properties: %{
          "type" => "step",
          "position" => %{"x" => 240, "y" => 260},
          "deletable" => false,
          "data" => %{"label" => "End", "kind" => "end"}
        }
      }
    ]
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
    save(Graph.changeset(%Graph{}, attrs), attrs, &Repo.insert/1, sweep?: false)
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
    save(Graph.changeset(graph, attrs), attrs, &Repo.update/1, sweep?: true)
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
        delete_tree_with_owned_forms(graph, tree_ids)
      end
    end)
  end

  # Owned forms are deleted explicitly — their owner FK nilifies on graph
  # deletion, and a nil owner is the *definition* of a catalog form, so
  # leaving them to the FK would launder every owned form into /forms.
  # Ordering matters: the fill-data check comes first (refuse before
  # destroying anything), the form rows go last (their node FK, though
  # :nothing, still enforces — nodes must delete first).
  defp delete_tree_with_owned_forms(graph, tree_ids) do
    forms =
      case owned_forms_deletable(graph) do
        {:ok, forms} -> forms
        {:error, changeset} -> Repo.rollback(changeset)
      end

    delete_graphs(tree_ids)

    Enum.each(forms, fn form ->
      {:ok, _form} = Templates.Forms.delete(form)
    end)

    graph
  end

  @doc """
  Deletes one node from its graph — the drill-in "delete this subflow".

  The node row goes (its relationships cascade), and the ownership domain is
  swept: an owned subflow the node referenced becomes unreachable and is
  collected with everything under it. A reusable subflow just loses this
  usage and survives.
  """
  def delete_node(%Node{} = node) do
    Repo.transaction(fn ->
      graph = Repo.get(Graph, node.graph_id)

      {:ok, _node} = Repo.delete(node)

      sweep_unreachable(graph)

      node
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

        # Owned forms referenced from the rehomed tree move with it — left in
        # the old domain, the old root's next sweep would collect them while
        # this graph still references them
        form_ids =
          Repo.all(
            from(n in Node,
              where: n.graph_id in ^[graph.id | rehome_ids] and not is_nil(n.form_id),
              select: n.form_id
            )
          )

        Repo.update_all(
          from(f in Templates.Form,
            where: f.owner_graph_id == ^old_owner_id and f.id in ^form_ids
          ),
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

  # Only updates sweep: replacing existing contents is the one way owned
  # graphs become unreachable. Creates must not — a child graph created
  # mid-save of its parent would sweep the domain before the parent's node
  # points at it, collecting itself.
  defp save(changeset, attrs, operation, sweep?: sweep?) do
    Repo.transaction(fn -> do_save(changeset, attrs, operation, sweep?) end)
  end

  defp do_save(changeset, attrs, operation, sweep?) do
    with {:ok, graph} <- operation.(changeset),
         {:ok, graph} <- replace_contents(graph, attrs) do
      if sweep? and contents?(attrs), do: sweep_unreachable(graph)

      graph
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp contents?(attrs) do
    Map.has_key?(attrs, :nodes) or Map.has_key?(attrs, :relationships)
  end

  defp replace_contents(graph, attrs) do
    if contents?(attrs) do
      with :ok <- validate_flavor(graph, Map.get(attrs, :nodes, [])),
           :ok <- clear_contents(graph),
           {:ok, nodes} <- insert_contents(graph, Node, Map.get(attrs, :nodes, [])),
           {:ok, _rels} <-
             insert_contents(graph, Relationship, Map.get(attrs, :relationships, [])),
           {:ok, _children} <- create_missing_subflows(graph, nodes),
           {:ok, _forms} <- create_missing_forms(graph, nodes) do
        {:ok, graph}
      end
    else
      {:ok, graph}
    end
  end

  # Deleting the nodes cascades to any relationships that referenced them
  defp clear_contents(graph) do
    Repo.delete_all(from(n in Node, where: n.graph_id == ^graph.id))
    Repo.delete_all(from(r in Relationship, where: r.graph_id == ^graph.id))

    :ok
  end

  # The homogeneity rule for the declared flavor: a "forms" flow never holds
  # subflow steps, a "subflows" flow never holds form steps. Start/End are
  # structural and pass. The editor is the primary guard — this is the belt
  # for callers bypassing it.
  defp validate_flavor(graph, nodes_attrs) do
    error =
      case graph.label do
        "forms" ->
          if Enum.any?(nodes_attrs, &subflow_step?/1),
            do: "a forms flow cannot contain subflow steps"

        "subflows" ->
          if Enum.any?(nodes_attrs, &form_step?/1),
            do: "a subflows flow cannot contain form steps"
      end

    if error do
      changeset =
        graph
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.add_error(:nodes, error)

      {:error, changeset}
    else
      :ok
    end
  end

  defp subflow_step?(attrs) do
    properties = node_properties(attrs)

    properties["type"] == "subflow" or
      properties["subflow_id"] != nil or
      attrs[:subflow_id] != nil
  end

  defp form_step?(attrs) do
    get_in(node_properties(attrs), ["data", "kind"]) == "form"
  end

  defp node_properties(attrs), do: attrs[:properties] || attrs["properties"] || %{}

  # Save-time child creation: every subflow node declared its child's flavor
  # when it was added in the editor (data.subflow_label), so missing children
  # can be created without asking anyone — owned by the root, universally
  # seeded, named from the canvas label.
  defp create_missing_subflows(graph, nodes) do
    root_id = graph.owner_graph_id || graph.id

    nodes
    |> Enum.filter(fn node ->
      node.properties["type"] == "subflow" and is_nil(node.subflow_id)
    end)
    |> Enum.reduce_while({:ok, []}, fn node, {:ok, created} ->
      child_attrs = %{
        name: get_in(node.properties, ["data", "label"]) || "Untitled subflow",
        label: get_in(node.properties, ["data", "subflow_label"]) || "forms",
        owner_graph_id: root_id,
        nodes: starter_nodes(),
        relationships: []
      }

      with {:ok, child} <- create(child_attrs),
           {:ok, _node} <- Repo.update(Node.changeset(node, %{subflow_id: child.id})) do
        {:cont, {:ok, [child | created]}}
      else
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
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
  # their contents — and owned forms no longer referenced by any node in the
  # domain go with them. Multi-level removal comes for free — a removed
  # subflow's own children stop being reachable too.
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

    sweep_unreferenced_forms(graph, root_id, [root_id | reachable])

    :ok
  end

  # Owned forms whose form nodes were all removed. Deletion goes through the
  # context (the node FK is :nothing by design), which refuses while fill
  # data exists — and then so does this save: fill data is never orphaned
  # silently, the user is told the removed step still has submissions.
  defp sweep_unreferenced_forms(graph, root_id, graph_ids) do
    referenced =
      Repo.all(
        from(n in Node,
          where: n.graph_id in ^graph_ids and not is_nil(n.form_id),
          distinct: true,
          select: n.form_id
        )
      )

    doomed =
      Repo.all(
        from(f in Templates.Form,
          where: f.owner_graph_id == ^root_id and f.id not in ^referenced
        )
      )

    Enum.each(doomed, fn form ->
      case Templates.Forms.delete(form) do
        {:ok, _form} ->
          :ok

        {:error, :has_instances} ->
          graph
          |> Ecto.Changeset.change()
          |> Ecto.Changeset.add_error(
            :nodes,
            "the removed form \"#{form.name}\" still has submitted data — " <>
              "delete its instances first, or keep the step"
          )
          |> Repo.rollback()

        {:error, other} ->
          Repo.rollback(other)
      end
    end)
  end

  # The owned forms a flow deletion will take with it, or a friendly refusal
  # when any of them still holds fill data. The actual deletion happens after
  # the graph tree (nodes first — their form FK enforces even as :nothing).
  defp owned_forms_deletable(graph) do
    forms = Repo.all(from(f in Templates.Form, where: f.owner_graph_id == ^graph.id))

    case Enum.find(forms, fn form -> form_has_instances?(form.id) end) do
      nil ->
        {:ok, forms}

      form ->
        changeset =
          graph
          |> Ecto.Changeset.change()
          |> Ecto.Changeset.add_error(
            :id,
            "cannot be deleted: its form \"#{form.name}\" still has submitted data"
          )

        {:error, changeset}
    end
  end

  defp form_has_instances?(form_id) do
    Repo.exists?(
      from(i in FormFlow.Data.Instances.Form,
        join: v in Templates.Form.Version,
        on: i.template_form_version_id == v.id,
        where: v.template_form_id == ^form_id
      )
    )
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
          # Explicit, even when unchanged: the source properties still carry
          # the OLD form id, and the changeset's adopt-from-properties path
          # would re-point the copy at the original if the column arrived nil
          form_id: copy_form_reference(node.form_id, domain_id),
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

  # The same boundary for forms: owned lineages are copied (with provenance),
  # catalog forms stay shared references — sharing is for forms whose
  # consumers want lockstep updates (archive/form-versioning.md, Decision 6)
  defp copy_form_reference(nil, _domain_id), do: nil

  defp copy_form_reference(form_id, domain_id) do
    case Repo.get(Templates.Form, form_id) do
      %Templates.Form{owner_graph_id: nil} ->
        form_id

      %Templates.Form{} = form ->
        {:ok, copy} = Templates.Forms.copy(form, owner_graph_id: domain_id)
        copy.id

      nil ->
        nil
    end
  end

  # Save-time form creation, the form-node mirror of create_missing_subflows:
  # a form node without a form gets a fresh owned lineage (with one blank
  # draft), named from the canvas label, owned by the ownership root
  defp create_missing_forms(graph, nodes) do
    root_id = graph.owner_graph_id || graph.id

    nodes
    |> Enum.filter(fn node ->
      get_in(node.properties, ["data", "kind"]) == "form" and is_nil(node.form_id)
    end)
    |> Enum.reduce_while({:ok, []}, fn node, {:ok, created} ->
      form_attrs = %{
        name: get_in(node.properties, ["data", "label"]) || "Untitled form",
        owner_graph_id: root_id
      }

      with {:ok, form} <- Templates.Forms.create(form_attrs),
           {:ok, _node} <- Repo.update(Node.changeset(node, %{form_id: form.id})) do
        {:cont, {:ok, [form | created]}}
      else
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end
end
