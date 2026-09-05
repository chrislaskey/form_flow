defmodule FormFlow.Data.Templates.Flows do
  @moduledoc """
  `FormFlow.Data.Templates.Flows` context module for
  `FormFlow.Data.Templates.Flow` records.

  A flow is the aggregate: the `form_flow_flows` row plus its
  `FormFlow.Data.Templates.Flow.Node` and
  `FormFlow.Data.Templates.Flow.Relationship` children.
  `create/1` and `update/2` accept the whole aggregate — pass `:nodes` and
  `:relationships` in the attributes and the contents are written alongside the
  row, in one transaction, nodes before the relationships that reference them.

  `list/0` deliberately does not load nodes and relationships; `get/1` does.

  ## Subflows and ownership

  A node whose `subflow_id` is set embeds another flow. By default such
  flows are private: their `owner_flow_id` points at the root flow they
  belong to (the ownership root — flat, not the immediate parent), and they
  are cleaned up automatically when they stop being referenced (see
  `update/2`) or when their root is deleted.

  `make_reusable/1` detaches a flow from its owner and stamps
  `made_reusable_at`, putting it in the catalog `list_reusable/0` returns.
  Reusable flows can be referenced by many flows — edits show up everywhere —
  or copied with `duplicate/2` for a private point-in-time copy.

  ## Declared flavor

  Every flow declares its flavor at creation in `label`: `"forms"` flows
  contain form steps, `"subflows"` flows contain subflow steps — never mixed
  (structural Start/End nodes are exempt). Saves validate the rule, and the
  label is immutable: converting means wrapping in a new parent flow.

  Saving a `"subflows"` flow also creates the children: any subflow node
  without a `subflow_id` gets a fresh flow — owned by the root, seeded with
  `starter_nodes/0`, named from the node's canvas label, its own label taken
  from the node's `data.subflow_label` (declared when the node was added in
  the editor) — and the node is pointed at it.

  ## Canvas write-throughs

  Some of what a canvas edits on a node really belongs to the entity behind
  the node, and `update/2` writes those edits through rather than storing a
  second copy. Loading goes the other way:
  `FormFlow.Web.Helpers.ReactFlow.to_data/1` projects the entity's current
  values back into the node's `data` for display. Writing through to a
  *reusable* child (or a shared catalog form) changes it for every consumer,
  like any other edit to a shared entity. Three write-throughs exist:

    * `data.form_flow_type` on a subflow node — the embedded flow's
      presentation type, stored only in that flow's
      `properties["form_flow_type"]` (see `FormFlow.Data.Templates.Flow`).
      Popped from the node's properties at save; an absent key clears the
      child's property, so picking "default" un-pins rather than freezing a
      value. A type that changes takes the old type's property values with
      it — they belonged to that type — while the canvas itself never edits
      property values; those are set on the flow's own page.
    * `data.form_type` on a form node — the collected form's type, stored only
      in the form lineage's `properties["form_type"]`
      (see `FormFlow.Data.Templates.Form`), with the same rules.
    * `data.label` on a subflow or form node — renaming the node renames the
      embedded flow or the collected form, the same value the entity's own
      pages edit. Unlike `form_flow_type` the label *stays* on the node too:
      entity-less nodes (Start/End, fresh nodes) have no other home for it,
      and save-time child creation names fresh children from it. A blank or
      missing label renames nothing — names are never blanked from the
      canvas.

  See the Neo4j guide (`guides/neo4j.md`) for how all of this maps onto a
  graph database when the dual-write extension lands.
  """

  import Ecto.Query

  alias FormFlow.Data.Instances
  alias FormFlow.Data.Repo
  alias FormFlow.Data.Templates
  alias FormFlow.Data.Templates.Flow
  alias FormFlow.Data.Templates.Flow.Node
  alias FormFlow.Data.Templates.Flow.Relationship
  alias FormFlow.Data.Templates.Slug

  @doc """
  Returns the top-level flows — root flows and reusable subflows — oldest
  first, without their nodes and relationships; just the counts, in the
  `:nodes_count` and `:relationships_count` virtual fields, as summary data
  for listings.

  Owned subflow children are deliberately excluded: they live inside their
  root and are reached by drill-in, not listed beside it. `opts[:tenant_id]`
  narrows to one tenant — a listing convenience, not access control.
  """
  def list(opts \\ []) do
    Repo.all(from(f in roots_query(opts), order_by: [asc: f.inserted_at]))
  end

  @doc """
  The root-flows listing as a composable query: every non-owned flow with
  its node and relationship counts, unordered.

  The counts come from grouped subqueries joined 1:1 rather than a `group_by`
  on the flows themselves, so callers (like Slab's table in query mode) can
  layer `order_by`, `limit`/`offset`, and `Repo.aggregate(:count)` on top
  without fighting the grouping. `opts[:tenant_id]` narrows as in `list/1`.
  """
  def roots_query(opts \\ []) do
    node_counts =
      from(n in Node, group_by: n.flow_id, select: %{flow_id: n.flow_id, count: count(n.id)})

    relationship_counts =
      from(r in Relationship,
        group_by: r.flow_id,
        select: %{flow_id: r.flow_id, count: count(r.id)}
      )

    from(f in Flow,
      where: is_nil(f.owner_flow_id),
      left_join: nc in subquery(node_counts),
      on: nc.flow_id == f.id,
      left_join: rc in subquery(relationship_counts),
      on: rc.flow_id == f.id,
      select: %{
        f
        | nodes_count: coalesce(nc.count, 0),
          relationships_count: coalesce(rc.count, 0)
      }
    )
    |> narrow_tenant(Keyword.get(opts, :tenant_id))
  end

  @doc """
  Returns the reusable catalog: flows made reusable, newest first.
  `opts[:tenant_id]` narrows to one tenant.

  Backed by a partial index on `made_reusable_at`, so this is a real-time
  query — no caching needed.
  """
  def list_reusable(opts \\ []) do
    Repo.all(
      from(f in Flow,
        where: not is_nil(f.made_reusable_at),
        order_by: [desc: f.made_reusable_at]
      )
      |> narrow_tenant(Keyword.get(opts, :tenant_id))
    )
  end

  defp narrow_tenant(query, nil), do: query
  defp narrow_tenant(query, tenant_id), do: from(f in query, where: f.tenant_id == ^tenant_id)

  @doc """
  Fetches one flow by id with its nodes and relationships loaded, or `nil`.

  Ids often arrive from URLs, so anything that is not a UUID is `nil` rather
  than an `Ecto.Query.CastError`.
  """
  def get(id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Flow{} = flow <- Repo.get(Flow, id) do
      preload_contents(flow)
    else
      _other -> nil
    end
  end

  @doc """
  Fetches one flow by its slug (`FormFlow.Data.Templates.Slug`), loaded like
  `get/1`, or `nil`. `opts[:tenant_id]` scopes the lookup to one tenant —
  slugs are unique per tenant, so a multitenant host passes it; a host with
  no tenants needs nothing more than the slug.

      FormFlow.Data.Templates.Flows.get_by_slug("dla2026")
      FormFlow.Data.Templates.Flows.get_by_slug("dla2026", tenant_id: "acme")
  """
  def get_by_slug(slug, opts \\ []) when is_binary(slug) do
    from(f in Flow, where: f.slug == ^slug)
    |> narrow_tenant(Keyword.get(opts, :tenant_id))
    |> Repo.one()
    |> case do
      nil -> nil
      flow -> preload_contents(flow)
    end
  end

  # Each node's entity comes along so ReactFlow.to_data/1 can project the
  # embedded flow's form_flow_type and name (or the form's name) into the
  # node's data
  defp preload_contents(flow) do
    Repo.preload(flow, [:relationships, nodes: [:subflow, :form]])
  end

  @doc """
  Fetches one node by id, or `nil`. Drill-in URLs carry node ids — the node's
  `subflow_id` is the flow they open.
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
  The node within an ownership domain that embeds the given flow, or `nil`.

  Used to build the drill-in URL of a flow's *containing* page: the node's id
  is the `/flows/:root/nodes/:node_id` segment. Scoped to the domain because a
  reusable flow can be embedded by many flows — only the usage under this
  root is wanted.
  """
  def embedding_node(flow_id, root_id) do
    case Ecto.UUID.cast(root_id) do
      {:ok, root_id} ->
        Repo.one(
          from(n in Node,
            join: f in Flow,
            on: f.id == n.flow_id,
            where:
              n.subflow_id == ^flow_id and
                (f.id == ^root_id or f.owner_flow_id == ^root_id),
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

  Laid out left to right, matching the editor's horizontal orientation, with
  `End` listed (and so inserted) first — `FormFlow.Data.Templates.Flows.get/1`
  loads a flow's nodes in insertion order, and the editor's add actions place
  a new node to the right of the *last* one, so `Start` inserted last is what
  puts the first node someone adds to the right of `Start` rather than `End`.
  """
  def starter_nodes do
    [
      %{
        labels: [],
        properties: %{
          "type" => "step",
          "position" => %{"x" => 900, "y" => 0},
          "deletable" => false,
          "data" => %{"label" => "End", "kind" => "end"}
        }
      },
      %{
        labels: [],
        properties: %{
          "type" => "step",
          "position" => %{"x" => 0, "y" => 0},
          "deletable" => false,
          "data" => %{"label" => "Start", "kind" => "start"}
        }
      }
    ]
  end

  @doc """
  Whether the flow is some root flow's private property.

  Unowned flows are root flows or reusable subflows — structurally the same
  thing; `made_reusable_at` is what lists a flow in the reusable catalog.
  """
  def owned?(%Flow{owner_flow_id: nil}), do: false
  def owned?(%Flow{}), do: true

  @doc """
  Creates a flow, along with any nodes and relationships in the attributes.

      {:ok, flow} = FormFlow.Data.Templates.Flows.create()

      {:ok, flow} =
        FormFlow.Data.Templates.Flows.create(%{nodes: [...], relationships: [...]})

  Pass `:owner_flow_id` to create a flow owned by a root flow — the default
  for subflows. A missing `:slug` is generated from the name
  (`FormFlow.Data.Templates.Slug`).
  """
  def create(attrs \\ %{}) do
    attrs = Slug.put_default(attrs, default_slug(attrs))

    save(Flow.changeset(%Flow{}, attrs), attrs, &Repo.insert/1, sweep?: false)
  end

  defp default_slug(attrs) do
    Slug.available(
      Flow,
      Slug.segment(Slug.get(attrs, :name), "flow"),
      Slug.get(attrs, :tenant_id)
    )
  end

  @doc """
  Updates a flow.

  When `attrs` include `:nodes` or `:relationships`, the flow's contents are
  replaced to match — existing rows are deleted and the given ones written.
  Attributes without contents leave the contents untouched.

  Replacing contents also garbage-collects: owned flows in the same ownership
  domain that are no longer reachable through subflow references are deleted,
  with everything under them. Removing a subflow node from the canvas is how
  an owned subflow (and its whole private subtree) goes away.
  """
  def update(%Flow{} = flow, attrs) do
    save(Flow.changeset(flow, attrs), attrs, &Repo.update/1, sweep?: true)
  end

  @doc """
  Deletes a flow, everything it owns, and their nodes and relationships.

  Refused with an error changeset while other flows still reference the flow
  as a subflow — remove those references (or `duplicate/2` first) and retry —
  or while instances of the whole flow have been started against it —
  journeys, `FormFlow.Data.Instances.Flow` records: they reference their root
  live and can never be orphaned by template deletion (the `:restrict`
  FK on `instance_flows.flow_id` is the database backstop; this guard gives
  the friendly error first). Note the owned-forms guard alone would miss a
  flow built entirely from catalog forms.
  """
  def delete(%Flow{} = flow) do
    Repo.transaction(fn ->
      owned_ids =
        Repo.all(from(f in Flow, where: f.owner_flow_id == ^flow.id, select: f.id))

      tree_ids = [flow.id | owned_ids]

      referenced? =
        Repo.exists?(
          from(n in Node, where: n.subflow_id == ^flow.id and n.flow_id not in ^tree_ids)
        )

      journeys? = Repo.exists?(from(i in Instances.Flow, where: i.flow_id == ^flow.id))

      cond do
        journeys? ->
          flow
          |> Ecto.Changeset.change()
          |> Ecto.Changeset.add_error(
            :id,
            "cannot be deleted: flow instances have been started against it"
          )
          |> Repo.rollback()

        referenced? ->
          flow
          |> Ecto.Changeset.change()
          |> Ecto.Changeset.add_error(:id, "is still used as a subflow by another flow")
          |> Repo.rollback()

        true ->
          delete_tree_with_owned_forms(flow, tree_ids)
      end
    end)
  end

  @doc """
  The flow aggregate with subflow references resolved, recursively — the
  tree `FormFlow.Data.Instances.FlowProgress` derives against. Returns
  `%{flow:, nodes:, relationships:, subflows: %{node_id => tree}}`, or
  `nil` for an unknown id.

  A seen-set guards against reference cycles (a cyclic reference resolves
  to no subtree); a repeated *sibling* reference — the diamond — still
  resolves at each position, as it must: each position is a distinct
  traversal.
  """
  def resolve_tree(flow_id), do: do_resolve_tree(flow_id, MapSet.new())

  defp do_resolve_tree(flow_id, seen) do
    case get(flow_id) do
      nil ->
        nil

      %Flow{} = flow ->
        seen = MapSet.put(seen, flow.id)

        subflows =
          for node <- flow.nodes,
              node.subflow_id,
              not MapSet.member?(seen, node.subflow_id),
              into: %{} do
            {node.id, do_resolve_tree(node.subflow_id, seen)}
          end

        %{flow: flow, nodes: flow.nodes, relationships: flow.relationships, subflows: subflows}
    end
  end

  # Owned forms are deleted explicitly — their owner FK nilifies on flow
  # deletion, and a nil owner is the *definition* of a catalog form, so
  # leaving them to the FK would launder every owned form into /forms.
  # Ordering matters: the instance-data check comes first (refuse before
  # destroying anything), the form rows go last (their node FK, though
  # :nothing, still enforces — nodes must delete first).
  defp delete_tree_with_owned_forms(flow, tree_ids) do
    forms =
      case owned_forms_deletable(flow) do
        {:ok, forms} -> forms
        {:error, changeset} -> Repo.rollback(changeset)
      end

    delete_flows(tree_ids)

    Enum.each(forms, fn form ->
      {:ok, _form} = Templates.Forms.delete(form)
    end)

    flow
  end

  @doc """
  Deletes one node from its flow — the drill-in "delete this subflow".

  The node row goes (its relationships cascade), and the ownership domain is
  swept: an owned subflow the node referenced becomes unreachable and is
  collected with everything under it. A reusable subflow just loses this
  usage and survives.
  """
  def delete_node(%Node{} = node) do
    Repo.transaction(fn ->
      flow = Repo.get(Flow, node.flow_id)

      {:ok, _node} = Repo.delete(node)

      sweep_unreachable(flow)

      node
    end)
  end

  @doc """
  Makes a flow reusable: detaches it from its owner and stamps
  `made_reusable_at`, which lists it in `list_reusable/0`.

  Its private descendants stay private — they are re-homed from the old
  ownership root to this flow, which becomes the root of its own ownership
  domain. Already-reusable flows pass through unchanged.
  """
  def make_reusable(%Flow{made_reusable_at: %DateTime{}} = flow), do: {:ok, flow}

  def make_reusable(%Flow{} = flow) do
    Repo.transaction(fn ->
      old_owner_id = flow.owner_flow_id

      {:ok, flow} =
        flow
        |> Ecto.Changeset.change(owner_flow_id: nil, made_reusable_at: DateTime.utc_now())
        |> Repo.update()

      if old_owner_id do
        rehome_ids = reachable_owned([flow.id], old_owner_id)

        Repo.update_all(
          from(f in Flow, where: f.id in ^rehome_ids),
          set: [owner_flow_id: flow.id]
        )

        # Owned forms referenced from the rehomed tree move with it — left in
        # the old domain, the old root's next sweep would collect them while
        # this flow still references them
        form_ids =
          Repo.all(
            from(n in Node,
              where: n.flow_id in ^[flow.id | rehome_ids] and not is_nil(n.form_id),
              select: n.form_id
            )
          )

        Repo.update_all(
          from(f in Templates.Form,
            where: f.owner_flow_id == ^old_owner_id and f.id in ^form_ids
          ),
          set: [owner_flow_id: flow.id]
        )
      end

      flow
    end)
  end

  @doc """
  Deep-copies a flow: a new flow with new UUIDs throughout — its name, label,
  and properties as they are, its contents copied, relationships re-pointed
  at the copied nodes.

  Subflow references follow the copy boundary: flows the source *owns* are
  deep-copied along with it; *reusable* flows stay shared references. The
  copy is never in the reusable catalog — `made_reusable_at` starts empty.

  The copy's slug is `opts[:slug]`, or the source's with a free `-N` suffix
  (`FormFlow.Data.Templates.Slug.available/3`). Copied children swap the
  source's slug for the copy's in their prefix — `dla2026_user-inform` under a
  copy slugged `dla2027` becomes `dla2027_user-inform`.

      {:ok, copy} = FormFlow.Data.Templates.Flows.duplicate(flow)

      {:ok, copy} =
        FormFlow.Data.Templates.Flows.duplicate(flow, owner_flow_id: root.id, slug: "dla2027")
  """
  def duplicate(%Flow{} = flow, opts \\ []) do
    owner_id = Keyword.get(opts, :owner_flow_id)

    Repo.transaction(fn ->
      slug = Keyword.get(opts, :slug) || Slug.available(Flow, flow.slug, flow.tenant_id)
      copy_id = copy_flow(flow.id, owner_id, nil, slug, {flow.slug, slug})

      Repo.preload(Repo.get(Flow, copy_id), [:nodes, :relationships])
    end)
  end

  # Only updates sweep: replacing existing contents is the one way owned
  # flows become unreachable. Creates must not — a child flow created
  # mid-save of its parent would sweep the domain before the parent's node
  # points at it, collecting itself.
  defp save(changeset, attrs, operation, sweep?: sweep?) do
    Repo.transaction(fn -> do_save(changeset, attrs, operation, sweep?) end)
  end

  defp do_save(changeset, attrs, operation, sweep?) do
    with {:ok, flow} <- operation.(changeset),
         {:ok, flow} <- replace_contents(flow, attrs) do
      if sweep? and contents?(attrs), do: sweep_unreachable(flow)

      flow
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp contents?(attrs) do
    Map.has_key?(attrs, :nodes) or Map.has_key?(attrs, :relationships)
  end

  defp replace_contents(flow, attrs) do
    if contents?(attrs) do
      {nodes_attrs, intents} = pop_canvas_intents(Map.get(attrs, :nodes, []))

      with :ok <- validate_flavor(flow, nodes_attrs),
           :ok <- clear_contents(flow),
           {:ok, nodes} <- insert_contents(flow, Node, nodes_attrs),
           {:ok, _rels} <-
             insert_contents(flow, Relationship, Map.get(attrs, :relationships, [])),
           {:ok, _children} <- create_missing_subflows(flow, nodes),
           {:ok, _forms} <- create_missing_forms(flow, nodes),
           :ok <- apply_canvas_intents(flow, intents) do
        {:ok, flow}
      end
    else
      {:ok, flow}
    end
  end

  # What a canvas save edits *through* a node rather than on it (see "Canvas
  # write-throughs" above), collected per node id. The types are popped from
  # the node's properties so exactly one copy exists — nil intents included,
  # because the editor removes the key when "default" is picked, and that must
  # clear the entity's property. The label is only read: it stays on the node
  # as well, for entity-less nodes and save-time child naming.
  defp pop_canvas_intents(nodes_attrs) do
    Enum.map_reduce(nodes_attrs, %{}, fn attrs, intents ->
      {flow_type, properties} = pop_data_key(node_properties(attrs), "form_flow_type")
      {form_type, properties} = pop_data_key(properties, "form_type")
      # Projected for display only (FormFlow.Web.Helpers.ReactFlow); the
      # subflow's identity form is where perspectives are set
      {_perspectives, properties} = pop_data_key(properties, "perspectives")

      intent = %{
        form_flow_type: flow_type,
        form_type: form_type,
        label: get_in(properties, ["data", "label"])
      }

      intents =
        case attrs[:id] || attrs["id"] do
          nil -> intents
          id -> Map.put(intents, id, intent)
        end

      {put_node_properties(attrs, properties), intents}
    end)
  end

  defp pop_data_key(%{"data" => %{} = data} = properties, key) do
    {value, data} = Map.pop(data, key)

    {value, Map.put(properties, "data", data)}
  end

  defp pop_data_key(properties, _key), do: {nil, properties}

  defp put_node_properties(%{properties: _properties} = attrs, properties) do
    %{attrs | properties: properties}
  end

  defp put_node_properties(%{"properties" => _properties} = attrs, properties) do
    %{attrs | "properties" => properties}
  end

  defp put_node_properties(attrs, _properties), do: attrs

  # The write-throughs, last so save-time entity creation has run and every
  # subflow or form node has its entity. Two nodes referencing the same shared
  # entity apply in turn — last write wins. No-ops skip the update, so routine
  # saves don't touch every entity's timestamps.
  defp apply_canvas_intents(flow, intents) do
    nodes =
      Repo.all(
        from(n in Node,
          where:
            n.flow_id == ^flow.id and
              (not is_nil(n.subflow_id) or not is_nil(n.form_id))
        )
      )

    Enum.reduce_while(nodes, :ok, fn node, :ok ->
      case apply_canvas_intent(node, Map.get(intents, node.id)) do
        {:error, changeset} -> {:halt, {:error, changeset}}
        _applied_or_unchanged -> {:cont, :ok}
      end
    end)
  end

  # An id-less programmatic node recorded no intent — nothing to apply
  defp apply_canvas_intent(_node, nil), do: :unchanged

  defp apply_canvas_intent(%{subflow_id: subflow_id}, intent)
       when not is_nil(subflow_id) do
    child = Repo.get(Flow, subflow_id)
    properties = put_type(child.properties, "form_flow_type", intent.form_flow_type)
    changes = rename_change(child.name, intent.label)

    changes =
      if properties == child.properties,
        do: changes,
        else: Map.put(changes, :properties, properties)

    if changes == %{} do
      :unchanged
    else
      Repo.update(Flow.changeset(child, changes))
    end
  end

  defp apply_canvas_intent(%{form_id: form_id}, intent) when not is_nil(form_id) do
    form = Repo.get(Templates.Form, form_id)
    properties = put_type(form.properties, "form_type", intent.form_type)
    changes = rename_change(form.name, intent.label)

    changes =
      if properties == form.properties,
        do: changes,
        else: Map.put(changes, :properties, properties)

    if changes == %{} do
      :unchanged
    else
      # The schema changeset, for its unique_constraint mapping: renaming a
      # shared catalog form into a taken name must be a refused save, not a
      # raised ConstraintError
      Repo.update(Templates.Form.changeset(form, changes))
    end
  end

  # The entity's properties with the canvas's type applied under `key`. A type
  # that changes — to another or to none — drops the property values entered
  # for the old one (under `key <> "_property_values"`), which belonged to it;
  # the same type again keeps them.
  defp put_type(properties, key, type) do
    cond do
      properties[key] == type -> properties
      is_nil(type) -> properties |> Map.delete(key) |> Map.delete(key <> "_property_values")
      true -> properties |> Map.put(key, type) |> Map.delete(key <> "_property_values")
    end
  end

  # A rename only when the canvas holds a real name that differs — a blank or
  # missing label never blanks an entity's name
  defp rename_change(current, label) do
    if is_binary(label) and label != "" and label != current do
      %{name: label}
    else
      %{}
    end
  end

  # Deleting the nodes cascades to any relationships that referenced them
  defp clear_contents(flow) do
    Repo.delete_all(from(n in Node, where: n.flow_id == ^flow.id))
    Repo.delete_all(from(r in Relationship, where: r.flow_id == ^flow.id))

    :ok
  end

  # The homogeneity rule for the declared flavor: a "forms" flow never holds
  # subflow steps, a "subflows" flow never holds form steps. Start/End are
  # structural and pass. The editor is the primary guard — this is the belt
  # for callers bypassing it.
  defp validate_flavor(flow, nodes_attrs) do
    error =
      case flow.label do
        "forms" ->
          if Enum.any?(nodes_attrs, &subflow_step?/1),
            do: "a forms flow cannot contain subflow steps"

        "subflows" ->
          if Enum.any?(nodes_attrs, &form_step?/1),
            do: "a subflows flow cannot contain form steps"
      end

    if error do
      changeset =
        flow
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
  defp create_missing_subflows(flow, nodes) do
    root_id = flow.owner_flow_id || flow.id

    nodes
    |> Enum.filter(fn node ->
      node.properties["type"] == "subflow" and is_nil(node.subflow_id)
    end)
    |> Enum.reduce_while({:ok, []}, fn node, {:ok, created} ->
      name = get_in(node.properties, ["data", "label"]) || "Untitled subflow"

      child_attrs = %{
        name: name,
        label: get_in(node.properties, ["data", "subflow_label"]) || "forms",
        tenant_id: flow.tenant_id,
        slug: child_slug(Flow, flow, name, "subflow"),
        owner_flow_id: root_id,
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

  defp insert_contents(flow, schema, attrs_list) do
    Enum.reduce_while(attrs_list, {:ok, []}, fn attrs, {:ok, inserted} ->
      changeset = schema.changeset(struct(schema), Map.put(attrs, :flow_id, flow.id))

      case Repo.insert(changeset) do
        {:ok, record} -> {:cont, {:ok, [record | inserted]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  # Garbage collection after a save: owned flows in this ownership domain
  # that are no longer reachable through subflow references get deleted, with
  # their contents — and owned forms no longer referenced by any node in the
  # domain go with them. Multi-level removal comes for free — a removed
  # subflow's own children stop being reachable too.
  defp sweep_unreachable(flow) do
    root_id = flow.owner_flow_id || flow.id
    reachable = reachable_owned([root_id], root_id)

    doomed =
      Repo.all(
        from(f in Flow,
          where: f.owner_flow_id == ^root_id and f.id not in ^reachable,
          select: f.id
        )
      )

    if doomed != [], do: delete_flows(doomed)

    sweep_unreferenced_forms(flow, root_id, [root_id | reachable])

    :ok
  end

  # Owned forms whose form nodes were all removed. Deletion goes through the
  # context (the node FK is :nothing by design), which refuses while instance
  # data exists — and then so does this save: instance data is never orphaned
  # silently, the user is told the removed step still has submissions.
  defp sweep_unreferenced_forms(flow, root_id, flow_ids) do
    referenced =
      Repo.all(
        from(n in Node,
          where: n.flow_id in ^flow_ids and not is_nil(n.form_id),
          distinct: true,
          select: n.form_id
        )
      )

    doomed =
      Repo.all(
        from(f in Templates.Form,
          where: f.owner_flow_id == ^root_id and f.id not in ^referenced
        )
      )

    Enum.each(doomed, fn form ->
      case Templates.Forms.delete(form) do
        {:ok, _form} ->
          :ok

        {:error, :has_instances} ->
          flow
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
  # when any of them still holds instance data. The actual deletion happens after
  # the flow tree (nodes first — their form FK enforces even as :nothing).
  defp owned_forms_deletable(flow) do
    forms = Repo.all(from(f in Templates.Form, where: f.owner_flow_id == ^flow.id))

    case Enum.find(forms, fn form -> form_has_instances?(form.id) end) do
      nil ->
        {:ok, forms}

      form ->
        changeset =
          flow
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

  # Flows owned by `owner_id` reachable by following subflow references out
  # of `frontier`. Within one ownership domain the reference structure is a
  # tree, but the seen-set guards against cycles regardless.
  defp reachable_owned(frontier, owner_id), do: reachable_owned(frontier, owner_id, MapSet.new())

  defp reachable_owned([], _owner_id, seen), do: MapSet.to_list(seen)

  defp reachable_owned(frontier, owner_id, seen) do
    children =
      Repo.all(
        from(n in Node,
          join: f in Flow,
          on: f.id == n.subflow_id,
          where: n.flow_id in ^frontier and f.owner_flow_id == ^owner_id,
          distinct: true,
          select: f.id
        )
      )

    new = Enum.reject(children, &MapSet.member?(seen, &1))

    reachable_owned(new, owner_id, Enum.into(new, seen))
  end

  # Deletes flows in an order that never trips the subflow foreign key:
  # nodes first (removing every subflow reference; their relationships cascade),
  # then the flow rows themselves.
  defp delete_flows(ids) do
    Repo.delete_all(from(n in Node, where: n.flow_id in ^ids))
    Repo.delete_all(from(f in Flow, where: f.id in ^ids))

    :ok
  end

  # Copies one flow and, recursively, everything it owns. `domain_id` is the
  # ownership root of the new tree: the requested owner, or the top copy
  # itself once it exists. `rewrite` is the {old, new} root slug pair every
  # copied child's prefix is swapped by.
  defp copy_flow(source_id, owner_id, domain_id, slug, rewrite) do
    source = get(source_id)
    copy_id = Ecto.UUID.generate()
    domain_id = domain_id || owner_id || copy_id

    {:ok, _flow} =
      %Flow{id: copy_id}
      |> Flow.changeset(%{
        name: source.name,
        label: source.label,
        properties: source.properties,
        tenant_id: source.tenant_id,
        slug: slug,
        owner_flow_id: owner_id
      })
      |> Repo.insert()

    node_ids = Map.new(source.nodes, fn node -> {node.id, Ecto.UUID.generate()} end)

    Enum.each(source.nodes, fn node ->
      {:ok, _node} =
        %Node{}
        |> Node.changeset(%{
          id: node_ids[node.id],
          flow_id: copy_id,
          subflow_id: copy_subflow_reference(node.subflow_id, domain_id, rewrite),
          # Explicit, even when unchanged: the source properties still carry
          # the OLD form id, and the changeset's adopt-from-properties path
          # would re-point the copy at the original if the column arrived nil
          form_id: copy_form_reference(node.form_id, domain_id, rewrite),
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
          flow_id: copy_id,
          source_id: node_ids[relationship.source_id],
          target_id: node_ids[relationship.target_id],
          label: relationship.label,
          properties: relationship.properties
        })
        |> Repo.insert()
    end)

    copy_id
  end

  defp copy_subflow_reference(nil, _domain_id, _rewrite), do: nil

  defp copy_subflow_reference(subflow_id, domain_id, rewrite) do
    # The copy boundary: owned flows are copied into the new domain,
    # reusable flows stay shared references
    case Repo.get(Flow, subflow_id) do
      %Flow{owner_flow_id: nil} ->
        subflow_id

      %Flow{} = child ->
        slug = Slug.available(Flow, rewritten(child.slug, rewrite), child.tenant_id)
        copy_flow(subflow_id, domain_id, domain_id, slug, rewrite)

      nil ->
        nil
    end
  end

  defp rewritten(slug, {old_prefix, new_prefix}), do: Slug.rewrite(slug, old_prefix, new_prefix)

  # The same boundary for forms: owned lineages are copied (with provenance),
  # catalog forms stay shared references — sharing is for forms whose
  # consumers want lockstep updates (archive/form-versioning.md, Decision 6)
  defp copy_form_reference(nil, _domain_id, _rewrite), do: nil

  defp copy_form_reference(form_id, domain_id, rewrite) do
    case Repo.get(Templates.Form, form_id) do
      %Templates.Form{owner_flow_id: nil} ->
        form_id

      %Templates.Form{} = form ->
        slug = Slug.available(Templates.Form, rewritten(form.slug, rewrite), form.tenant_id)
        {:ok, copy} = Templates.Forms.copy(form, owner_flow_id: domain_id, slug: slug)
        copy.id

      nil ->
        nil
    end
  end

  # Save-time form creation, the form-node mirror of create_missing_subflows:
  # a form node without a form gets a fresh owned lineage (with one blank
  # draft), named from the canvas label, owned by the ownership root
  # An owned child's slug: its own segment under the containing flow's slug,
  # so nested children carry the whole chain (FormFlow.Data.Templates.Slug)
  defp child_slug(schema, flow, name, fallback) do
    Slug.available(schema, Slug.join(flow.slug, Slug.segment(name, fallback)), flow.tenant_id)
  end

  defp create_missing_forms(flow, nodes) do
    root_id = flow.owner_flow_id || flow.id

    nodes
    |> Enum.filter(fn node ->
      get_in(node.properties, ["data", "kind"]) == "form" and is_nil(node.form_id)
    end)
    |> Enum.reduce_while({:ok, []}, fn node, {:ok, created} ->
      name = get_in(node.properties, ["data", "label"]) || "Untitled form"

      form_attrs = %{
        name: name,
        tenant_id: flow.tenant_id,
        slug: child_slug(Templates.Form, flow, name, "form"),
        owner_flow_id: root_id
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
