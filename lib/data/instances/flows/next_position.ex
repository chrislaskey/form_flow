defmodule FormFlow.Data.Instances.Flow.NextPosition do
  @moduledoc """
  `FormFlow.Data.Instances.Flow.NextPosition` Ecto Schema for one position a
  journey's flow is open at: a row of `form_flow_instance_next_positions`,
  the child table of the cache `FormFlow.Data.Instances.Flows.update_next_positions/2`
  writes.

  A journey has one row here for every position
  `FormFlow.Data.Instances.FlowProgress.derive/2` calls `:available` or
  `:in_progress` - one row for an in-order flow, one per unfinished form
  for a flow worked in any order, none once nothing is actionable. `path`
  is the position, as the instance side addresses one; `node_id` is its
  last segment, the column a listing filters on with `node_id in ^ids`
  (`FormFlow.Data.Instances.Flows.narrow_next_position/2`); `tenant_id` is
  copied from the journey so the `(tenant_id, node_id)` index can carry a
  tenant's filter.

  The journey row's own `next_path` and `next_node_id`
  (`FormFlow.Data.Instances.Flow`) are the **first** of these rows in flow
  order - the one position a page names and links to. The two are written
  by the same refresh in the same transaction, so they cannot disagree:
  neither is ever stale relative to the other, only both relative to the
  live derivation, which `next_computed_at` on the journey dates.

  Nothing here holds a perspective. Whose position a node is comes from the
  flow type's `visible?/2` at read time, so an admin adding a perspective
  moves nothing in this table.

  Rows are written whole by the refresh - deleted and re-inserted for a
  journey, through `insert_all` - and removed ahead of the journey row by
  `FormFlow.Data.Instances.Flows.delete_instance/2`. Nothing else writes
  them, so the schema has no changeset: a validation only the refresh
  would run is the refresh's own code, and the database's `null: false`
  columns and unique `(instance_flow_id, path)` index are the guards that
  actually run.
  """

  use Ecto.Schema

  alias FormFlow.Data.Instances

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "form_flow_instance_next_positions" do
    belongs_to(:instance_flow, Instances.Flow, foreign_key: :instance_flow_id)

    field(:path, {:array, :string})
    field(:node_id, :string)
    field(:tenant_id, :string)

    timestamps(type: :utc_datetime_usec)
  end
end
