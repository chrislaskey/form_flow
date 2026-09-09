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

  A node whose `subflow_id` is set embeds another flow. Every such flow is
  private: its `owner_flow_id` points at the root flow it belongs to (the
  ownership root — flat, not the immediate parent), it is cleaned up
  automatically when it stops being referenced (see `update/2`) or when its
  root is deleted, and a save refuses a subflow step pointing at a flow the
  tree does not own. A subflow wanted elsewhere is copied there with
  `duplicate/2`. Sharing by reference is for forms alone (see "Reusing a
  catalog form"): a form is a leaf, one lineage and one version pin per
  instance, while a subflow is a subtree — its own forms, the paths through
  it, its perspectives and type — and sharing one across trees makes every
  operation on it ambiguous about which tree it is happening to.

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
  second copy. For the two types, loading goes the other way:
  `FormFlow.Web.Helpers.ReactFlow.to_data/1` projects the entity's current
  type back into the node's `data` for display. Three write-throughs exist:

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
      (see `FormFlow.Data.Templates.Form`), with the same rules — **when
      this flow tree owns the form**. A catalog form is typed on its own
      page, once for every flow that reuses it (`reuse_form/3`); a type
      picked for it on one flow's canvas is not written, and the canvas
      shows the form's true type again on its next load.
    * `data.label` on a subflow or form node — the step's name, what the
      instance pages show users. Unlike the types the label *stays* on the
      node: it is the stored value, never projected from the entity. Renaming
      the node also renames the embedded flow or the collected form **when
      this flow tree owns it** — always, for a subflow; for a form, unless
      it is the catalog's — so an owned entity's `name` and its step's label
      are one value, and a catalog form keeps its own name for every
      consumer. The entity's own edit pages keep the same
      pair in step from the other side (`update_node/2`). A blank or missing
      label renames nothing — names are never blanked from the canvas.

  ## Step slugs

  A step — a form or subflow node — carries a `slug`, the handle a host
  names it by (`FormFlow.Data.Templates.Slug`), and the canvas never writes
  it. A save carries each surviving node's slug across by id, ignoring the
  properties copy the canvas round-trips, and gives every new step a
  default: its label's segment under the root flow's slug, `-N` when taken
  among the tenant's steps. The subflow or form a save creates for a step
  gets no slug of its own — the step's is the handle, and the entity is
  reached through the step. A seed names its steps by passing `slug:` in a
  node's attributes; an admin, from the step's page (`update_node/2`); a
  host looks one up with `get_node_by_slug/2`.

  ## Reusing a catalog form

  A form step points at a form *lineage* (`FormFlow.Data.Templates.Flow.Node`'s
  `form_id`), and saving a flow gives every new form step a blank owned
  lineage of its own (`create_missing_forms/2`). `reuse_form/3` points the
  step at a catalog form instead — one lineage, shared by every flow whose
  steps point at it, so an edit or a publish reaches them all at once — and
  deletes the owned lineage the step abandons. A step leaves a catalog form
  the way it leaves any form: removed from the canvas and added again, it
  is a new step with a fresh owned form and the chooser, where Copy form
  makes a private copy of the catalog form. `form_usages/1` lists the steps
  pointing at a lineage, with their flows, for every page that has to say
  where a shared form is used.
  """

  import Ecto.Query

  alias FormFlow.Data.Instances
  alias FormFlow.Data.Repo
  alias FormFlow.Data.Templates
  alias FormFlow.Data.Templates.Flow
  alias FormFlow.Data.Templates.Flow.Node
  alias FormFlow.Data.Templates.Flow.Relationship
  alias FormFlow.Data.Templates.Flows.Health
  alias FormFlow.Data.Templates.Slug

  @doc """
  Returns the root flows, oldest first, without their nodes and
  relationships; just the counts, in the
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
  `get/1`, or `nil`. `opts[:tenant_id]` scopes the lookup to one tenant; a
  host with no tenants needs nothing more than the slug. Slugs are unique per
  tenant, not across them, so without `tenant_id:` a slug that several
  tenants hold raises `Ecto.MultipleResultsError` — a multitenant host
  always passes it.

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
  Fetches one step by its slug (`FormFlow.Data.Templates.Slug`), or `nil` —
  the node, with `flow_id`, `subflow_id`, and `form_id` for the caller to
  follow. `opts[:tenant_id]` scopes the lookup to one tenant, as
  `get_by_slug/2` does, and matters more here: every step has a generated
  default, so two tenants seeding the same flow hold the same step slugs,
  and an untenanted lookup of one raises `Ecto.MultipleResultsError`. The
  owned subflow or form behind a step has no slug of its own; this is how
  it is reached.

      FormFlow.Data.Templates.Flows.get_node_by_slug("dog-license_owner-conta")
      FormFlow.Data.Templates.Flows.get_node_by_slug("owner-contact", tenant_id: "acme")
  """
  def get_node_by_slug(slug, opts \\ []) when is_binary(slug) do
    from(n in Node, where: n.slug == ^slug)
    |> narrow_tenant(Keyword.get(opts, :tenant_id))
    |> Repo.one()
  end

  @doc """
  Updates a step — what the step's page edits on the node itself:

    * `:label` — the step's name, written as the node's `data.label`, the
      name the instance pages show for the position
      (`FormFlow.Data.Instances.FlowProgress`). A blank or missing label
      renames nothing — names are never blanked.
    * `:slug` — the step's handle (`FormFlow.Data.Templates.Slug`). A blank
      clears it; absent leaves it. A slug another step in the tenant holds
      is refused with an error on `:slug`.

  The entity behind the step is the caller's concern, the same split the
  canvas save makes (see "Canvas write-throughs"): the form and flow edit
  pages rename an owned form or subflow alongside, and leave a catalog form
  alone. Nothing here touches the entity.
  """
  def update_node(%Node{} = node, attrs) do
    changes =
      %{}
      |> put_label_change(node, attrs[:label])
      |> put_slug_change(attrs)

    Repo.update(Node.changeset(node, changes))
  end

  defp put_label_change(changes, node, label) when is_binary(label) and label != "" do
    properties =
      Map.update(node.properties, "data", %{"label" => label}, &Map.put(&1, "label", label))

    Map.put(changes, :properties, properties)
  end

  defp put_label_change(changes, _node, _blank), do: changes

  defp put_slug_change(changes, %{slug: slug}), do: Map.put(changes, :slug, slug)
  defp put_slug_change(changes, _attrs), do: changes

  @doc """
  Every step that points at the form lineage `form_id`, as
  `%{node:, flow:, root:}` — the step, the flow it is in, and that flow's
  ownership root (the flow itself when it is a root), so a caller can say
  "Dog License / Application". Oldest root first, then oldest flow, then
  step. Empty for a form no step uses.

  This is what a catalog form's pages show as "Used in", what the publish
  dialog attributes counts by, and what `FormFlow.Data.Templates.Forms.delete/1`
  refuses on. An owned form has exactly one usage, in its own tree, unless
  the canvas duplicated its step.
  """
  def form_usages(form_id) do
    case Ecto.UUID.cast(form_id) do
      {:ok, form_id} ->
        rows =
          Repo.all(
            from(n in Node,
              join: f in Flow,
              on: f.id == n.flow_id,
              left_join: r in Flow,
              on: r.id == f.owner_flow_id,
              where: n.form_id == ^form_id,
              order_by: [
                asc: coalesce(r.inserted_at, f.inserted_at),
                asc: f.inserted_at,
                asc: n.inserted_at
              ],
              select: {n, f, r}
            )
          )

        for {node, flow, root} <- rows, do: %{node: node, flow: flow, root: root || flow}

      :error ->
        []
    end
  end

  @doc """
  Points a form step at a catalog form: the step *becomes* that form, and
  from then on shares it with every other flow whose steps point at it — an
  edit through any of them is an edit for all, and a publish migrates the
  instances of all of them (`FormFlow.Data.Templates.Forms.update_status/3`).
  The owned form the step pointed at is deleted; a catalog form the step
  pointed at before is left alone — it belongs to the catalog, not the step.
  The step itself — its id, its label, its slug — is untouched: nothing
  about the node changes but `form_id`. In one transaction; returns the
  repointed node.

  Refused as:

    * `{:error, :owned_form}` — `form` belongs to a flow tree. Only catalog
      forms (`owner_flow_id` nil) can be shared: an owned form is deleted
      with its tree, out from under any other flow pointing at it.
    * `{:error, :other_tenant}` — `form` belongs to another tenant than the
      step's flow.
    * `{:error, :related_form}` — `form`'s type declares a `:related_form`
      property (`FormFlow.Config.Forms.Type.related_form_property/2` over
      `opts[:form_types]`, the host's types; the library's by default). Its
      value is a step path in one flow, so the form cannot serve two.
    * `{:error, :step_form_published}` — the step's own form has a published
      version. A published form may have instances, which the repoint
      would strand and the delete refuse; a never-published one cannot.

  Instances already started at the step, in any flow, keep the version
  they pinned: nothing here re-resolves a pin.

  A step leaves a catalog form by being removed from the canvas and added
  again; the new step has a new id, so users who had started the old one
  are stranded there (`FormFlow.Data.Instances.Flows.list_stranded/2`), as
  after any removed step.
  """
  def reuse_form(%Node{} = node, %Templates.Form{} = form, opts \\ []) do
    form_types = Keyword.get(opts, :form_types, FormFlow.Config.Forms.Type.defaults())

    Repo.transaction(fn ->
      flow = Repo.get(Flow, node.flow_id)
      current = node.form_id && Repo.get(Templates.Form, node.form_id)

      with :ok <- reusable(form, flow, form_types),
           :ok <- abandonable(current),
           {:ok, node} <- Repo.update(Node.changeset(node, %{form_id: form.id})),
           :ok <- abandon_form(current) do
        node
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp reusable(form, flow, form_types) do
    cond do
      form.owner_flow_id != nil ->
        {:error, :owned_form}

      form.tenant_id != flow.tenant_id ->
        {:error, :other_tenant}

      FormFlow.Config.Forms.Type.related_form_property(form_types, form) ->
        {:error, :related_form}

      true ->
        :ok
    end
  end

  # What the step leaves behind: nothing, a catalog form (left where it is),
  # or an owned form — which goes, so it must never have been published
  defp abandonable(nil), do: :ok
  defp abandonable(%Templates.Form{owner_flow_id: nil}), do: :ok

  defp abandonable(%Templates.Form{} = owned) do
    if Templates.Forms.ever_published?(owned.id), do: {:error, :step_form_published}, else: :ok
  end

  # The abandoned owned form is deleted now rather than at the tree's next
  # sweep — unless another step of the tree still points at it (a duplicated
  # node), in which case it is theirs
  defp abandon_form(nil), do: :ok
  defp abandon_form(%Templates.Form{owner_flow_id: nil}), do: :ok

  defp abandon_form(%Templates.Form{} = owned) do
    if Repo.exists?(from(n in Node, where: n.form_id == ^owned.id)) do
      :ok
    else
      with {:ok, _form} <- Templates.Forms.delete(owned), do: :ok
    end
  end

  @doc """
  The node within an ownership domain that embeds the given flow, or `nil`.

  Used to build the drill-in URL of a flow's *containing* page: the node's id
  is the `/flows/:root/nodes/:node_id` segment. Scoped to the domain, which
  is where every embedding of an owned flow lives.
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
  Whether the flow is some root flow's private property. An unowned flow is
  a root flow.
  """
  def owned?(%Flow{owner_flow_id: nil}), do: false
  def owned?(%Flow{}), do: true

  @doc """
  Creates a flow, along with any nodes and relationships in the attributes.

      {:ok, flow} = FormFlow.Data.Templates.Flows.create()

      {:ok, flow} =
        FormFlow.Data.Templates.Flows.create(%{nodes: [...], relationships: [...]})

  Pass `:owner_flow_id` to create a flow owned by a root flow — the default
  for subflows. A missing `:slug` is generated from the name for a root flow
  (`FormFlow.Data.Templates.Slug`); an owned flow gets none unless one is
  given — its step's slug is the handle.
  """
  def create(attrs \\ %{}) do
    attrs = Slug.put_default(attrs, default_slug(attrs))

    save(Flow.changeset(%Flow{}, attrs), attrs, &Repo.insert/1, sweep?: false)
  end

  # An owned flow — a subflow — has no slug of its own; its step's is the handle
  defp default_slug(attrs) do
    if Slug.get(attrs, :owner_flow_id) do
      nil
    else
      Slug.available(
        Flow,
        Slug.segment(Slug.get(attrs, :name), "flow"),
        Slug.get(attrs, :tenant_id)
      )
    end
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
  Deletes a root flow, everything it owns, and their nodes and relationships.

  Refused with an error changeset on `:id` for an owned flow — a subflow is
  deleted by removing its step from the flow that embeds it (`delete_node/1`),
  never on its own, since the embedding node would be left pointing at
  nothing — and while instances of the whole flow have been started against
  it — journeys, `FormFlow.Data.Instances.Flow` records: they reference
  their root live and can never be orphaned by template deletion (the
  `:restrict` FK on `instance_flows.flow_id` is the database backstop; this
  guard gives the friendly error first). Note the owned-forms guard alone
  would miss a flow built entirely from catalog forms.
  """
  def delete(%Flow{} = flow) do
    Repo.transaction(fn ->
      owned_ids =
        Repo.all(from(f in Flow, where: f.owner_flow_id == ^flow.id, select: f.id))

      tree_ids = [flow.id | owned_ids]

      journeys? = Repo.exists?(from(i in Instances.Flow, where: i.flow_id == ^flow.id))

      cond do
        owned?(flow) ->
          refuse_delete(
            flow,
            "cannot be deleted: it is a subflow of another flow — remove its step from that " <>
              "flow's canvas instead"
          )

        journeys? ->
          refuse_delete(flow, "cannot be deleted: flow instances have been started against it")

        true ->
          delete_tree_with_owned_forms(flow, tree_ids)
      end
    end)
  end

  defp refuse_delete(flow, message) do
    flow
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.add_error(:id, message)
    |> Repo.rollback()
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

  @doc """
  Narrows a resolved tree (`resolve_tree/1`) to its connected nodes: at
  every level, the nodes reachable from that flow's Start nodes by following
  relationships forward, and the relationships among them. Nodes a user
  filling the flow in could never reach — a form step nothing points at, a
  fragment wired only to End — are dropped, together with their
  relationships. Subflows are narrowed the same way, recursively; a subflow
  node that is itself unreachable takes its subtree with it.

  This is the same reading of "reachable" `FormFlow.Data.Instances.FlowProgress`
  walks with, so the narrowed tree shows exactly the positions a journey
  can visit. `FormFlow.Web.Templates.Flows.Overview` draws it. `nil` in,
  `nil` out, so a missing flow needs no special casing by the caller.

  Nodes and relationships keep the order they were stored in.
  """
  def connected_tree(nil), do: nil

  def connected_tree(%{nodes: nodes, relationships: relationships, subflows: subflows} = tree) do
    starts = for node <- nodes, "Start" in node.labels, do: node.id
    outgoing = Enum.group_by(relationships, & &1.source_id, & &1.target_id)
    reachable = reachable_nodes(starts, outgoing, MapSet.new())

    %{
      tree
      | nodes: Enum.filter(nodes, &MapSet.member?(reachable, &1.id)),
        relationships:
          Enum.filter(relationships, fn relationship ->
            MapSet.member?(reachable, relationship.source_id) and
              MapSet.member?(reachable, relationship.target_id)
          end),
        subflows:
          Map.new(
            Enum.filter(subflows, fn {node_id, _subtree} -> MapSet.member?(reachable, node_id) end),
            fn {node_id, subtree} -> {node_id, connected_tree(subtree)} end
          )
    }
  end

  defp reachable_nodes([], _outgoing, seen), do: seen

  defp reachable_nodes([id | rest], outgoing, seen) do
    if MapSet.member?(seen, id) do
      reachable_nodes(rest, outgoing, seen)
    else
      reachable_nodes(rest ++ Map.get(outgoing, id, []), outgoing, MapSet.put(seen, id))
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
  swept: the subflow the node referenced becomes unreachable and is
  collected with everything under it.
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
  Deep-copies a flow: a new flow with new UUIDs throughout — its name, label,
  and properties as they are, its contents copied, relationships re-pointed
  at the copied nodes.

  Every subflow of the source is deep-copied along with it — a subflow is
  its tree's own — while a catalog form a step points at stays a shared
  reference (see `copy_form_reference/3`).

  The copy's slug is `opts[:slug]`; otherwise a copy that lands beside the
  source takes the source's with a free `-N` suffix
  (`FormFlow.Data.Templates.Slug.available/3`), and a copy made owned by
  `owner_flow_id:` gets none, as an owned flow created from scratch does.
  Copied steps keep the shape of their slugs: a default under the source
  tree's root slug is rewritten under the copy's — `dla2026_user-inform`
  under a copy slugged `dla2027` becomes `dla2027_user-inform`, and under a
  copy made owned by `cat-license` becomes `cat-license_user-inform`, the
  default a step made in that tree would get — and a hand-set slug gets a
  free suffix. Owned subflows and forms have no slug to copy.

      {:ok, copy} = FormFlow.Data.Templates.Flows.duplicate(flow)

      {:ok, copy} =
        FormFlow.Data.Templates.Flows.duplicate(flow, owner_flow_id: root.id, slug: "dla2027")

  The source's health bookkeeping (`properties["_health_metadata"]` — its
  cached status and ignored records, which name nodes the copy does not
  have) does not come along: the copy starts as a flow never checked. Given
  `flow_types:` and `form_types:` — the host's lists — the copy is checked
  once and its status cached (`FormFlow.Data.Templates.Flows.Health.refresh/2`);
  without them it is not, since a check with the library's default types
  could cache a type warning the host's lists would not raise.
  """
  def duplicate(%Flow{} = flow, opts \\ []) do
    owner_id = Keyword.get(opts, :owner_flow_id)

    result =
      Repo.transaction(fn ->
        slug = Keyword.get(opts, :slug) || copy_slug(flow, owner_id)
        rewrite = {root_flow(flow).slug, rewrite_prefix(owner_id, slug)}
        copy_id = copy_flow(flow.id, owner_id, nil, slug, rewrite)

        Repo.preload(Repo.get(Flow, copy_id), [:nodes, :relationships])
      end)

    with {:ok, copy} <- result do
      case Keyword.take(opts, [:flow_types, :form_types]) do
        [] ->
          {:ok, copy}

        types ->
          Health.refresh(copy, types)
          {:ok, Repo.preload(Repo.get(Flow, copy.id), [:nodes, :relationships])}
      end
    end
  end

  # An owned copy is a subflow of the destination tree, and an owned flow has
  # no slug of its own — the step embedding it carries the handle
  defp copy_slug(_flow, owner_id) when not is_nil(owner_id), do: nil
  defp copy_slug(flow, nil), do: Slug.available(Flow, flow.slug, flow.tenant_id)

  # What copied steps' defaults are rewritten under: the copy's own slug, or,
  # for a copy made owned, the destination root's — the prefix a step created
  # in that tree would get. The old prefix is the source tree's root slug,
  # since an owned source has none of its own.
  defp rewrite_prefix(nil, slug), do: slug
  defp rewrite_prefix(owner_id, _slug), do: Repo.get(Flow, owner_id).slug

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
      kept_slugs = current_slugs(flow)

      with :ok <- validate_flavor(flow, nodes_attrs),
           :ok <- clear_contents(flow),
           {:ok, nodes} <- insert_contents(flow, Node, keep_slugs(nodes_attrs, kept_slugs)),
           {:ok, nodes} <- put_step_slugs(flow, nodes),
           :ok <- validate_subflow_ownership(flow, nodes),
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

  # The slugs the flow's nodes hold now, by id — read before the contents are
  # replaced, so a node the canvas sends back keeps its slug. The properties
  # copy is ignored because slugs are edited on the step's page, never on the
  # canvas, so the copy can be older than the column; were the canvas to edit
  # them, Node.changeset/2's put_new_from_properties/3 would do this instead.
  # An explicit `slug:` in the attributes wins: that is how a seed names steps.
  defp current_slugs(flow) do
    Map.new(Repo.all(from(n in Node, where: n.flow_id == ^flow.id, select: {n.id, n.slug})))
  end

  defp keep_slugs(nodes_attrs, kept_slugs) do
    Enum.map(nodes_attrs, fn attrs ->
      Map.put_new(attrs, :slug, Map.get(kept_slugs, attrs[:id]))
    end)
  end

  # Every step — a form or subflow node — has a slug. The ones that arrived
  # without one (new on the canvas, or created programmatically) get the
  # default: the label's segment under the root flow's slug, made free among
  # the tenant's steps. One update at a time, in canvas order, so two
  # same-named steps in one save see each other and the second takes `-2`.
  # Start and End are not steps and get none. The prefix is the root's, not
  # the containing flow's, because an owned subflow has no slug of its own.
  defp put_step_slugs(flow, nodes) do
    root = root_flow(flow)

    nodes
    |> Enum.reverse()
    |> Enum.reduce_while({:ok, []}, fn node, {:ok, done} ->
      case put_step_slug(node, root, flow.tenant_id) do
        {:ok, node} -> {:cont, {:ok, [node | done]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
    |> case do
      {:ok, nodes} -> {:ok, Enum.reverse(nodes)}
      error -> error
    end
  end

  defp put_step_slug(%Node{slug: nil} = node, root, tenant_id) do
    if step?(node) do
      label = get_in(node.properties, ["data", "label"])
      candidate = Slug.join(root.slug, Slug.segment(label, "step"))

      Repo.update(Node.changeset(node, %{slug: Slug.available(Node, candidate, tenant_id)}))
    else
      {:ok, node}
    end
  end

  defp put_step_slug(node, _root, _tenant_id), do: {:ok, node}

  defp step?(%Node{} = node) do
    node.properties["type"] == "subflow" or node.subflow_id != nil or
      get_in(node.properties, ["data", "kind"]) == "form" or node.form_id != nil
  end

  defp root_flow(%Flow{owner_flow_id: nil} = flow), do: flow
  defp root_flow(%Flow{owner_flow_id: root_id}), do: Repo.get(Flow, root_id)

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
    changes = rename_change(child, intent.label)

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

  # The type and the name both write through only to an owned form: a
  # catalog form is typed and named on its own page, for every consumer
  defp apply_canvas_intent(%{form_id: form_id}, intent) when not is_nil(form_id) do
    form = Repo.get(Templates.Form, form_id)

    properties =
      if form.owner_flow_id,
        do: put_type(form.properties, "form_type", intent.form_type),
        else: form.properties

    changes = rename_change(form, intent.label)

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

  # A rename only for an entity this flow tree owns — a catalog form keeps
  # its own name for every consumer; the step's label is
  # this flow's word for it — and only when the canvas holds a real name that
  # differs: a blank or missing label never blanks an entity's name
  defp rename_change(%{owner_flow_id: nil}, _label), do: %{}

  defp rename_change(%{name: current}, label) do
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

  # Every subflow a step points at belongs to this tree: a flow owned by
  # another root would be deleted out from under this one with its tree, and
  # a root flow is nobody's subflow. A step without a subflow yet gets one at
  # save (create_missing_subflows/2); the way to use a flow from elsewhere is
  # duplicate/2.
  defp validate_subflow_ownership(flow, nodes) do
    root_id = flow.owner_flow_id || flow.id
    referenced = for %{subflow_id: id} <- nodes, is_binary(id), uniq: true, do: id

    foreign? =
      referenced != [] and
        Repo.exists?(
          from(f in Flow,
            where:
              f.id in ^referenced and (is_nil(f.owner_flow_id) or f.owner_flow_id != ^root_id)
          )
        )

    if foreign? do
      changeset =
        flow
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.add_error(
          :nodes,
          "a subflow step must point at a flow this flow owns — copy the flow to use it here"
        )

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

  # Every node and relationship is the flow's, and in the flow's tenant
  defp insert_contents(flow, schema, attrs_list) do
    Enum.reduce_while(attrs_list, {:ok, []}, fn attrs, {:ok, inserted} ->
      attrs = Map.merge(attrs, %{flow_id: flow.id, tenant_id: flow.tenant_id})
      changeset = schema.changeset(struct(schema), attrs)

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
  # copied step's default slug is swapped by; owned children have none.
  defp copy_flow(source_id, owner_id, domain_id, slug, rewrite) do
    source = get(source_id)
    copy_id = Ecto.UUID.generate()
    domain_id = domain_id || owner_id || copy_id

    {:ok, _flow} =
      %Flow{id: copy_id}
      |> Flow.changeset(%{
        name: source.name,
        label: source.label,
        properties: Health.forget(source.properties),
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
          tenant_id: source.tenant_id,
          slug: Slug.available(Node, rewritten(node.slug, rewrite), source.tenant_id),
          subflow_id: copy_subflow_reference(node.subflow_id, domain_id, rewrite),
          # Explicit, even when unchanged: the source properties still carry
          # the OLD form id, and the changeset would take that copy into the
          # column if the column arrived nil, re-pointing the copy at the
          # original
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
          flow_id: copy_id,
          tenant_id: source.tenant_id,
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
    case Repo.get(Flow, subflow_id) do
      %Flow{} -> copy_flow(subflow_id, domain_id, domain_id, nil, rewrite)
      nil -> nil
    end
  end

  defp rewritten(slug, {old_prefix, new_prefix}), do: Slug.rewrite(slug, old_prefix, new_prefix)

  # The same boundary for forms: owned lineages are copied (with provenance),
  # catalog forms stay shared references — sharing is for forms whose
  # consumers want lockstep updates (archive/form-versioning.md, Decision 6)
  defp copy_form_reference(nil, _domain_id), do: nil

  defp copy_form_reference(form_id, domain_id) do
    case Repo.get(Templates.Form, form_id) do
      %Templates.Form{owner_flow_id: nil} ->
        form_id

      %Templates.Form{} = form ->
        {:ok, copy} = Templates.Forms.copy(form, owner_flow_id: domain_id)
        copy.id

      nil ->
        nil
    end
  end

  # Save-time form creation, the form-node mirror of create_missing_subflows:
  # a form node without a form gets a fresh owned lineage (with one blank
  # draft), named from the canvas label, owned by the ownership root. Neither
  # child gets a slug — the step's is the handle.
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
