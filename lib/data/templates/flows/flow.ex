defmodule FormFlow.Data.Templates.Flow do
  @moduledoc """
  `FormFlow.Data.Templates.Flow` Ecto Schema for a flow — the aggregate root
  the nodes and relationships of one flow diagram hang off.

  The row is the flow's identity and what is said about it as a whole —
  name, flavor (`label`), tenant, slug, status; the substance lives in the associated
  `FormFlow.Data.Templates.Flow.Node` and
  `FormFlow.Data.Templates.Flow.Relationship` records, following Neo4j's
  property graph vocabulary. `FormFlow.Data.Templates.Flows.get/1` returns the
  whole aggregate with both associations loaded.

  Contents are written by `FormFlow.Data.Templates.Flows.create/1` and
  `FormFlow.Data.Templates.Flows.update/2`, which insert nodes before the
  relationships that reference them — an ordering `cast_assoc` cannot
  guarantee between sibling associations, which is why the changeset below
  casts no contents.

  ## Status

  What users may do with the flow — start, continue, see — is one column,
  `status`, born `draft`. The table of statuses and what each allows is the
  comment on `@statuses`; `FormFlow.Data.Templates.Flows.update_status/3`
  moves it and logs the move (`FormFlow.Data.Templates.Flow.Event`).

  ## Ownership

  `owner_flow_id` records whose private property this flow is. It points at
  the **ownership root** — everything private in one root flow's tree carries
  the same owner, so deleting the domain is one indexed operation. `nil` means
  the flow is a root flow. Every subflow — a flow another flow embeds through
  `FormFlow.Data.Templates.Flow.Node`'s `subflow_id` — is owned by the root of
  the tree it sits in; a subflow wanted in a second tree is copied there by
  pasting its step (`FormFlow.Data.Templates.Flows`, "Pasting a step"),
  never shared. Sharing by reference is for forms alone
  (`FormFlow.Data.Templates.Form`).

  ## Tenancy

  `tenant_id` is the host tenant the flow belongs to — an opaque host
  identity, `nil` for a host with no tenants — stamped at creation and
  immutable afterwards. Owned children, save-time or copied, take their
  root's. Like a node's `flow_id` it is written to both locations: the
  dedicated column, so the database can index and narrow by it, and a
  `"tenant_id"` key inside `properties`, the copy that carries over to
  Neo4j. The changeset keeps the copy in sync — the column is authoritative,
  and a stale `"tenant_id"` arriving in `properties` is overwritten.

  ## Slug

  `slug` is a root flow's secondary identifier — see
  `FormFlow.Data.Templates.Slug`: optional, unique per tenant, editable, never
  following a rename, and dual-written into `properties["slug"]` the same
  way. `FormFlow.Data.Templates.Flows.create/1` fills one in from the name
  when none is given. An owned subflow has none: the step that embeds it
  (`FormFlow.Data.Templates.Flow.Node`) carries the slug.

  This row maps wholesale to a `:Flow` node when the Neo4j dual-write lands —
  ownership becomes an `OWNED_BY` relationship. See the Neo4j guide
  (`guides/neo4j.md`).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias FormFlow.Data.Templates.Flow.Node
  alias FormFlow.Data.Templates.Flow.Relationship
  alias FormFlow.Data.Templates.Slug

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "form_flow_flows" do
    field(:name, :string)

    # The declared flavor: "forms" or "subflows", never mixed (see
    # FormFlow.Data.Templates.Flows). Named `label` to mirror Neo4j, where it
    # becomes the second label on the :Flow node — :Flow:Forms / :Flow:Subflows.
    field(:label, :string, default: "forms")

    field(:tenant_id, :string)
    field(:slug, :string)

    # What users may do with the flow — see `statuses/0`. A flow is born a
    # draft; `FormFlow.Data.Templates.Flows.update_status/3` moves it.
    field(:status, :string, default: "draft")

    # Open domain data in the Neo4j property-graph style, like a node's
    # properties. Carries "form_flow_type" for "forms" flows — the id of the
    # `FormFlow.Config.Flows.Type` deciding how the flow's forms are presented
    # to a user filling them out; absent means the default applies.
    field(:properties, :map, default: %{})

    # In the order they were stored: what "canvas order" means to
    # `FormFlow.Data.Templates.Flows` — which of two same-named steps takes
    # the bare slug, which position of a twice-embedded subflow a pasted
    # path is rebased to — and what a bare preload would not promise
    has_many(:nodes, Node, preload_order: [asc: :inserted_at, asc: :id])
    has_many(:relationships, Relationship, preload_order: [asc: :inserted_at, asc: :id])

    belongs_to(:owner_flow, __MODULE__, foreign_key: :owner_flow_id)

    # Summary counts for listings, filled by FormFlow.Data.Templates.Flows.list/0
    field(:nodes_count, :integer, virtual: true)
    field(:relationships_count, :integer, virtual: true)

    timestamps(type: :utc_datetime_usec)
  end

  # The statuses a root flow can have, and what each lets a user do. Three
  # facts per status — may a user START a new instance, CONTINUE one already
  # started (the form edit page), SEE their instances at all (the listing,
  # the instance and form pages, Download and Print) — and a status is the
  # set of those it allows. The table, built and planned
  # (`archive/plans/flow-status.md` §3):
  #
  #   status        start  continue  see   meaning
  #   draft           –       –       –    being built; not offered, and nobody
  #                                        sees it — a flow pulled back to draft
  #                                        disappears from its users until it
  #                                        reopens
  #   pre_release     ✓*      ✓*       ✓*   open to the pre-release users a page
  #                                        names (`pre_release_user_ids` on
  #                                        `FormFlow.Web.router/1`), a draft to
  #                                        everyone else. *The data layer allows
  #                                        it for anyone; the pages are the gate
  #                                        (the render is gated, not the write —
  #                                        a host's own route decides for itself)
  #   open            ✓       ✓       ✓    taking starts; the normal state
  #   winding_down    –       ✓       ✓    no new starts; anyone in it finishes
  #   read_only       –       –       ✓    nothing changes; users can still look
  #                                        at their own
  #   archived        –       –       –    users see nothing; admins keep the
  #                                        flow, its instances, its log
  #
  # Draft and archived allow the same nothing; they differ in meaning — never
  # opened, and put away — and in what the admin's badge says. Transitions
  # are any-to-any — real
  # programs go sideways and get fixed in unexpected ways, and the event log
  # (`FormFlow.Data.Templates.Flow.Event`) is what makes trusting the admin
  # safe. The admin side is not decided by status: the canvas is editable at
  # every one. An owned subflow carries the default and is never read — status
  # is the root's, as health is.
  @statuses ~w(draft pre_release open winding_down read_only archived)
  @allowed %{
    "draft" => [],
    "pre_release" => [:start, :continue, :see],
    "open" => [:start, :continue, :see],
    "winding_down" => [:continue, :see],
    "read_only" => [:see],
    "archived" => []
  }

  @doc "The statuses a flow can have, in the order the dropdown offers them."
  def statuses, do: @statuses

  @doc """
  Whether a flow's status lets a user `:start` a new instance, `:continue`
  one already started, or `:see` their instances at all. Takes the flow or
  its status.
  """
  def allows?(%__MODULE__{status: status}, action), do: allows?(status, action)
  def allows?(status, action) when is_binary(status), do: action in Map.get(@allowed, status, [])

  @doc "The statuses that allow `action` — for a query's `where status in`."
  def statuses_allowing(action), do: Enum.filter(@statuses, &allows?(&1, action))

  @doc """
  Builds a changeset for a flow.

  `:name`, `:slug`, `:properties`, and `:owner_flow_id` are castable;
  `:label`, `:tenant_id`, and `:status` are castable at creation and
  immutable afterwards — the declared flavor is a commitment (the escape
  hatch is wrapping in a new parent flow, not converting), a template never
  changes tenants, and a status moves only through
  `FormFlow.Data.Templates.Flows.update_status/3`, which writes the event
  that goes with it (`status_changeset/2`). A status at creation is for
  seeds and tests; the pages create drafts.
  """
  def changeset(flow, attrs \\ %{}) do
    flow
    |> cast(attrs, [:name, :label, :tenant_id, :slug, :properties, :owner_flow_id, :status])
    |> validate_inclusion(:label, ~w(forms subflows))
    |> validate_inclusion(:status, @statuses)
    |> validate_immutable(:label)
    |> validate_immutable(:tenant_id)
    |> validate_immutable(:status)
    |> Slug.validate_slug(:form_flow_flows_slug_tenant_index)
    |> copy_into_properties(:tenant_id, "tenant_id")
    |> copy_into_properties(:slug, "slug")
    |> foreign_key_constraint(:owner_flow_id)
  end

  @doc """
  The one changeset that moves `status` on a persisted flow. Callers go
  through `FormFlow.Data.Templates.Flows.update_status/3`, which pairs the
  write with its `status_changed` event.
  """
  def status_changeset(flow, status) do
    flow
    |> cast(%{status: status}, [:status])
    |> validate_required([:status])
    |> validate_inclusion(:status, @statuses)
  end

  defp validate_immutable(changeset, field) do
    if changeset.data.__meta__.state == :loaded and get_change(changeset, field) do
      add_error(changeset, field, "cannot be changed after creation")
    else
      changeset
    end
  end

  # The dual-write: properties carry a copy of the column, for Neo4j — and
  # none when the column is empty
  defp copy_into_properties(changeset, field, key) do
    properties = get_field(changeset, :properties) || %{}

    properties =
      case get_field(changeset, field) do
        nil -> Map.delete(properties, key)
        value -> Map.put(properties, key, value)
      end

    put_change(changeset, :properties, properties)
  end
end
