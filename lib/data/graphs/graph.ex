defmodule FormFlow.Data.Graph do
  @moduledoc """
  `FormFlow.Data.Graph` Ecto Schema for a graph — the aggregate root the nodes
  and relationships of one flow diagram hang off.

  The row itself is just an identity (`form_flow_graphs` has only an id and
  timestamps for now); the substance lives in the associated
  `FormFlow.Data.Graph.Node` and `FormFlow.Data.Graph.Relationship` records,
  following Neo4j's property graph vocabulary. `FormFlow.Data.Graphs.get/1`
  returns the whole aggregate with both associations loaded.

  Contents are written by `FormFlow.Data.Graphs.create/1` and
  `FormFlow.Data.Graphs.update/2`, which insert nodes before the relationships
  that reference them — an ordering `cast_assoc` cannot guarantee between
  sibling associations, which is why the changeset below casts no contents.

  ## Ownership and reuse

  `owner_graph_id` records whose private property this graph is. It points at
  the **ownership root** — everything private in one root flow's tree carries
  the same owner, so deleting the domain is one indexed operation. `nil` means
  nobody owns it: the graph is a root flow, or a reusable subflow other flows
  reference through `FormFlow.Data.Graph.Node`'s `subflow_id`. Structurally
  those are the same thing — `FormFlow.Data.Graphs.make_reusable/1` just
  detaches a graph from its owner and stamps `made_reusable_at`, which is what
  lists it in the reusable catalog (`FormFlow.Data.Graphs.list_reusable/0`).

  An owned graph is never in the catalog: the changeset rejects setting an
  owner on a graph that has `made_reusable_at`.

  This row maps wholesale to a `:Graph` node when the Neo4j dual-write lands —
  ownership becomes an `OWNED_BY` relationship. See the Neo4j guide
  (`guides/neo4j.md`).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias FormFlow.Data.Graph.Node
  alias FormFlow.Data.Graph.Relationship

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "form_flow_graphs" do
    field(:name, :string)

    # The declared flavor: "forms" or "subflows", never mixed (see
    # FormFlow.Data.Graphs). Named `label` to mirror Neo4j, where it becomes
    # the second label on the :Graph node — :Graph:Forms / :Graph:Subflows.
    field(:label, :string, default: "forms")

    has_many(:nodes, Node)
    has_many(:relationships, Relationship)

    belongs_to(:owner_graph, __MODULE__, foreign_key: :owner_graph_id)

    field(:made_reusable_at, :utc_datetime_usec)

    # Summary counts for listings, filled by FormFlow.Data.Graphs.list/0
    field(:nodes_count, :integer, virtual: true)
    field(:relationships_count, :integer, virtual: true)

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Builds a changeset for a graph.

  `:name` and `:owner_graph_id` are castable; `:label` is castable at creation
  and immutable afterwards — the declared flavor is a commitment, and the
  escape hatch is wrapping in a new parent flow, not converting.
  `:made_reusable_at` is deliberately not castable — it is only stamped by
  `FormFlow.Data.Graphs.make_reusable/1`.
  """
  def changeset(graph, attrs \\ %{}) do
    graph
    |> cast(attrs, [:name, :label, :owner_graph_id])
    |> validate_inclusion(:label, ~w(forms subflows))
    |> validate_label_immutable()
    |> validate_owned_graphs_are_not_reusable()
    |> foreign_key_constraint(:owner_graph_id)
  end

  defp validate_label_immutable(changeset) do
    if changeset.data.__meta__.state == :loaded and get_change(changeset, :label) do
      add_error(changeset, :label, "cannot be changed after creation")
    else
      changeset
    end
  end

  defp validate_owned_graphs_are_not_reusable(changeset) do
    if get_field(changeset, :owner_graph_id) && get_field(changeset, :made_reusable_at) do
      add_error(changeset, :owner_graph_id, "an owned graph cannot be reusable")
    else
      changeset
    end
  end
end
