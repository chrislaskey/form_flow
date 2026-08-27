defmodule FormFlow.Data.Templates.Flow do
  @moduledoc """
  `FormFlow.Data.Templates.Flow` Ecto Schema for a flow — the aggregate root
  the nodes and relationships of one flow diagram hang off.

  The row itself is just an identity (`form_flow_flows` has only an id and
  timestamps for now); the substance lives in the associated
  `FormFlow.Data.Templates.Flow.Node` and
  `FormFlow.Data.Templates.Flow.Relationship` records, following Neo4j's
  property graph vocabulary. `FormFlow.Data.Templates.Flows.get/1` returns the
  whole aggregate with both associations loaded.

  Contents are written by `FormFlow.Data.Templates.Flows.create/1` and
  `FormFlow.Data.Templates.Flows.update/2`, which insert nodes before the
  relationships that reference them — an ordering `cast_assoc` cannot
  guarantee between sibling associations, which is why the changeset below
  casts no contents.

  ## Ownership and reuse

  `owner_flow_id` records whose private property this flow is. It points at
  the **ownership root** — everything private in one root flow's tree carries
  the same owner, so deleting the domain is one indexed operation. `nil` means
  nobody owns it: the flow is a root flow, or a reusable subflow other flows
  reference through `FormFlow.Data.Templates.Flow.Node`'s `subflow_id`.
  Structurally those are the same thing —
  `FormFlow.Data.Templates.Flows.make_reusable/1` just detaches a flow from
  its owner and stamps `made_reusable_at`, which is what lists it in the
  reusable catalog (`FormFlow.Data.Templates.Flows.list_reusable/0`).

  An owned flow is never in the catalog: the changeset rejects setting an
  owner on a flow that has `made_reusable_at`.

  This row maps wholesale to a `:Flow` node when the Neo4j dual-write lands —
  ownership becomes an `OWNED_BY` relationship. See the Neo4j guide
  (`guides/neo4j.md`).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias FormFlow.Data.Templates.Flow.Node
  alias FormFlow.Data.Templates.Flow.Relationship

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "form_flow_flows" do
    field(:name, :string)

    # The declared flavor: "forms" or "subflows", never mixed (see
    # FormFlow.Data.Templates.Flows). Named `label` to mirror Neo4j, where it
    # becomes the second label on the :Flow node — :Flow:Forms / :Flow:Subflows.
    field(:label, :string, default: "forms")

    # Open domain data in the Neo4j property-graph style, like a node's
    # properties. Carries "form_flow_type" for "forms" flows — how the flow's
    # forms are presented to a user filling them out, and which of them that
    # user may open (see `FormFlow.Flows.Types`); absent means the
    # `FormFlow.Config` default decides.
    field(:properties, :map, default: %{})

    has_many(:nodes, Node)
    has_many(:relationships, Relationship)

    belongs_to(:owner_flow, __MODULE__, foreign_key: :owner_flow_id)

    field(:made_reusable_at, :utc_datetime_usec)

    # Summary counts for listings, filled by FormFlow.Data.Templates.Flows.list/0
    field(:nodes_count, :integer, virtual: true)
    field(:relationships_count, :integer, virtual: true)

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Builds a changeset for a flow.

  `:name`, `:properties`, and `:owner_flow_id` are castable; `:label` is
  castable at creation and immutable afterwards — the declared flavor is a commitment, and the
  escape hatch is wrapping in a new parent flow, not converting.
  `:made_reusable_at` is deliberately not castable — it is only stamped by
  `FormFlow.Data.Templates.Flows.make_reusable/1`.
  """
  def changeset(flow, attrs \\ %{}) do
    flow
    |> cast(attrs, [:name, :label, :properties, :owner_flow_id])
    |> validate_inclusion(:label, ~w(forms subflows))
    |> validate_label_immutable()
    |> validate_owned_flows_are_not_reusable()
    |> foreign_key_constraint(:owner_flow_id)
  end

  defp validate_label_immutable(changeset) do
    if changeset.data.__meta__.state == :loaded and get_change(changeset, :label) do
      add_error(changeset, :label, "cannot be changed after creation")
    else
      changeset
    end
  end

  defp validate_owned_flows_are_not_reusable(changeset) do
    if get_field(changeset, :owner_flow_id) && get_field(changeset, :made_reusable_at) do
      add_error(changeset, :owner_flow_id, "an owned flow cannot be reusable")
    else
      changeset
    end
  end
end
