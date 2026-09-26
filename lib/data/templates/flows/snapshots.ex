defmodule FormFlow.Data.Templates.Flows.Snapshots do
  @moduledoc """
  `FormFlow.Data.Templates.Flows.Snapshots` context module for template
  flow snapshots (`FormFlow.Data.Templates.Flow.Snapshot`): taking one when
  a journey starts, and reading one back as the struct tree
  `FormFlow.Data.Templates.Flows.resolve_tree/1` returns - so
  `FormFlow.Data.Instances.FlowProgress` and the pages read a journey's
  frozen flow through the same shape they read a live one.

  Two callers own the writes. `FormFlow.Data.Instances.Flows.create/2`
  calls `get_or_create/2` with the tree it resolved for the journey's
  first refresh, and the editor's Move calls it with the tree it just
  saved. Every other caller reads: `tree/1` for a journey or a snapshot,
  `list/1` for a root's snapshots in order.
  """

  import Ecto.Query

  alias FormFlow.Data.Instances
  alias FormFlow.Data.Repo
  alias FormFlow.Data.Templates
  alias FormFlow.Data.Templates.Flow
  alias FormFlow.Data.Templates.Flow.Snapshot

  @doc "Fetches a snapshot by id, or nil."
  def get(id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Snapshot{} = snapshot <- Repo.get(Snapshot, id) do
      snapshot
    else
      _other -> nil
    end
  end

  @doc "A root flow's snapshots, first taken first."
  def list(%Flow{id: root_id}) do
    Repo.all(
      from(s in Snapshot, where: s.template_flow_id == ^root_id, order_by: [asc: s.number])
    )
  end

  @doc """
  Deletes every snapshot of `root` no journey references. Called by
  `FormFlow.Data.Instances.Flows.delete_pre_release/2` once the trial run
  is gone, inside its transaction; an ordinary journey deletion leaves
  snapshots alone, since they are shared and cheap. Returns how many went.
  """
  def delete_unreferenced(%Flow{id: root_id}) do
    referenced =
      from(i in Instances.Flow,
        where: i.template_flow_id == ^root_id,
        select: i.template_flow_snapshot_id
      )

    {deleted, _rows} =
      Repo.delete_all(
        from(s in Snapshot,
          where: s.template_flow_id == ^root_id and s.id not in subquery(referenced)
        )
      )

    deleted
  end

  @doc """
  The snapshots the `in_progress` journeys of `flows` read, each once -
  what a listing of those journeys needs trees for, and nothing more: a
  completed journey has no open position for a listing to name, and a
  snapshot no journey in flight reads is nobody's to draw. `tenant_id`
  keeps to one tenant's journeys, `nil` to every tenant's. One query.

  The cost is the `data` of every row: some tens of kilobytes each, and
  as many rows as there are distinct snapshots with an unfinished journey
  - unbounded by the listing's page size, growing by one per save an
  admin makes that a user then starts against. Measured at 201 snapshots
  of the demo's Dog License flow: 76 ms for this query alone on local
  SQLite, 7 MB selected. Accepted for now; the way out, when a deployment
  shows the number, is to select ids here and keep decoded trees in an
  ETS table keyed by snapshot id - `data` never changes, so nothing
  invalidates - with the live status and form rows filled in by two
  batched queries across every tree rather than two per tree
  (`archive/plans/snapshot-tree-cache.md`, which may not be in git).
  """
  def list_in_progress(flows, tenant_id) when is_list(flows) do
    journeys =
      Instances.Flows.list_query(flow: flows, tenant_id: tenant_id, status: "in_progress")

    in_use = from(i in journeys, select: i.template_flow_snapshot_id)

    Repo.all(from(s in Snapshot, where: s.id in subquery(in_use)))
  end

  @doc """
  The snapshot holding `tree` (`FormFlow.Data.Templates.Flows.resolve_tree/1`
  of `root`): the root's existing row with the same checksum, or a new row
  numbered after the root's last. `{:ok, snapshot}`, or `{:error,
  changeset}` when the insert failed for a reason no retry answers.

  One transaction. On Postgres the root row is locked `FOR UPDATE` first,
  as `FormFlow.Data.Templates.Forms.publish/2` locks the form template, so
  two journeys starting at once take one snapshot between them and the
  numbers never collide. SQLite has no `FOR UPDATE` and one writer at a
  time; there, a start that loses the race to either unique index reads
  the winner's row back instead.
  """
  def get_or_create(%Flow{} = root, tree) when is_map(tree) do
    data = Snapshot.take(tree)
    checksum = Snapshot.checksum(data)

    Repo.transaction(fn ->
      lock_root(root.id)

      case find(root.id, checksum) do
        %Snapshot{} = snapshot -> snapshot
        nil -> insert(root, data, checksum)
      end
    end)
  end

  defp find(root_id, checksum) do
    Repo.one(
      from(s in Snapshot, where: s.template_flow_id == ^root_id and s.checksum == ^checksum)
    )
  end

  defp insert(root, data, checksum) do
    attrs = %{
      template_flow_id: root.id,
      tenant_id: root.tenant_id,
      number: next_number(root.id),
      checksum: checksum,
      data: data
    }

    case Repo.insert(Snapshot.changeset(%Snapshot{}, attrs)) do
      {:ok, snapshot} ->
        snapshot

      {:error, changeset} ->
        # Reached on SQLite alone, where no lock kept a concurrent start
        # out: the row it inserted is the one to reuse. Postgres never gets
        # here - the lock serialised the two - and could not read after a
        # failed insert if it did, its transaction being aborted by then.
        case find(root.id, checksum) do
          %Snapshot{} = snapshot -> snapshot
          nil -> Repo.rollback(changeset)
        end
    end
  end

  # `max + 1`, so a number pruned from the top of a root's list
  # (`delete_unreferenced/1`) is worn again by the next snapshot: a number
  # names a row of the root, not a place in its history
  defp next_number(root_id) do
    max =
      Repo.one(from(s in Snapshot, where: s.template_flow_id == ^root_id, select: max(s.number)))

    (max || 0) + 1
  end

  defp lock_root(root_id) do
    query = from(f in Flow, where: f.id == ^root_id)
    query = if postgres?(), do: lock(query, "FOR UPDATE"), else: query

    Repo.one(query)
  end

  defp postgres?, do: Repo.repo().__adapter__() == Ecto.Adapters.Postgres

  @doc """
  A snapshot's `data` as the struct tree `FormFlow.Data.Templates.Flows.resolve_tree/1`
  returns, back-references included: `%{flow:, nodes:, relationships:,
  subflows:}` where `flow` is a `%FormFlow.Data.Templates.Flow{}` with
  `nodes` and `relationships` set (the same lists), every subflow node has
  `subflow` set to its embedded flow, every form node has `form` set from
  one load of the live form template rows (`nil` when the row is gone),
  and each flow's `status` is the live row's where one exists. Timestamps
  come back as `%DateTime{}`.

  These structs are for reading. They are built from the snapshot, not
  loaded from their tables - `__meta__.state` is `:built` - so they are
  not rows to update or preload through a repo, and a host callback that
  receives one through `FormFlow.Context` should treat it as the picture
  of a flow, not the flow. The form template on a form node is the one
  exception: it is the live row.

  Given a journey, its snapshot's tree; given an id, that snapshot's. `nil`
  for `nil`, and for an id no snapshot has.
  """
  def tree(nil), do: nil
  def tree(%Instances.Flow{template_flow_snapshot_id: snapshot_id}), do: tree(snapshot_id)
  def tree(snapshot_id) when is_binary(snapshot_id), do: snapshot_id |> get() |> tree()

  def tree(%Snapshot{data: data}) do
    form_ids = data |> node_values("form_id") |> Enum.uniq()
    flow_ids = flow_ids(data)

    forms =
      Map.new(Repo.all(from(f in Templates.Form, where: f.id in ^form_ids)), &{&1.id, &1})

    statuses =
      Map.new(Repo.all(from(f in Flow, where: f.id in ^flow_ids, select: {f.id, f.status})))

    build(data, forms, statuses)
  end

  defp build(nil, _forms, _statuses), do: nil

  defp build(%{"flow" => flow_data} = data, forms, statuses) do
    subflows =
      Map.new(data["subflows"], fn {node_id, subtree} ->
        {node_id, build(subtree, forms, statuses)}
      end)

    nodes =
      for node_data <- data["nodes"] do
        %Flow.Node{} = node = row(Flow.Node, node_data)

        %{
          node
          | form: node.form_id && forms[node.form_id],
            subflow: subflow_of(node, subflows)
        }
      end

    relationships = Enum.map(data["relationships"], &row(Flow.Relationship, &1))
    %Flow{} = flow = row(Flow, flow_data)

    flow = %{
      flow
      | status: Map.get(statuses, flow.id, flow.status),
        nodes: nodes,
        relationships: relationships
    }

    %{flow: flow, nodes: nodes, relationships: relationships, subflows: subflows}
  end

  # As `resolve_tree/1` leaves it: the embedded flow on a subflow node, nil
  # on a node that embeds nothing or whose subflow the tree did not hold
  # (a reference cycle)
  defp subflow_of(%Flow.Node{subflow_id: nil}, _subflows), do: nil

  defp subflow_of(%Flow.Node{id: id}, subflows) do
    case subflows[id] do
      %{flow: %Flow{} = flow} -> flow
      _none -> nil
    end
  end

  # A row's map back to its struct, each value cast by the column's own
  # type - which is what turns the ISO 8601 strings back into `%DateTime{}`.
  # A value the type cannot cast is kept as stored rather than raised on:
  # a snapshot outlives the code that wrote it by as long as its journeys
  # live, and a column whose type moved on is a page that still renders,
  # not a crash on a user's flow instance. A key the schema no longer has
  # is simply not read.
  defp row(schema, data) do
    fields =
      for field <- schema.__schema__(:fields),
          {:ok, value} <- [Map.fetch(data, Atom.to_string(field))] do
        case Ecto.Type.cast(schema.__schema__(:type, field), value) do
          {:ok, cast} -> {field, cast}
          :error -> {field, value}
        end
      end

    struct(schema, fields)
  end

  defp node_values(nil, _key), do: []

  defp node_values(%{"nodes" => nodes, "subflows" => subflows}, key) do
    Enum.flat_map(nodes, &List.wrap(&1[key])) ++
      Enum.flat_map(subflows, fn {_node_id, subtree} -> node_values(subtree, key) end)
  end

  defp flow_ids(nil), do: []

  defp flow_ids(%{"flow" => %{"id" => id}, "subflows" => subflows}) do
    [id | Enum.flat_map(subflows, fn {_node_id, subtree} -> flow_ids(subtree) end)]
  end
end
