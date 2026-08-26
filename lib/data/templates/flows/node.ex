defmodule FormFlow.Data.Templates.Flow.Node do
  @moduledoc """
  `FormFlow.Data.Templates.Flow.Node` Ecto Schema for a node in a flow.

  Follows Neo4j's property graph model: a node has `labels` (a set of strings —
  nodes can carry several) and `properties` (an open map of domain data). What a
  node *means* lives entirely in those two fields; the only structural columns
  are its identity and which flow it belongs to.

  `labels` is derived, not editor-supplied: the changeset sets it from the
  ReactFlow `kind`/`type` already sitting in `properties` (`"start"`, `"form"`,
  `"end"`, or a subflow) whenever it isn't already set explicitly. FormFlow's
  editor shows it under a node's title.

  `flow_id` is written to both locations: the dedicated column, so the
  database can index membership and cascade deletes, and a `"flow_id"` key
  inside `properties`, which is the copy that carries over to Neo4j, where
  there is no column. The changeset keeps the copy in sync — the column is
  authoritative, and a stale `"flow_id"` arriving in `properties` is
  overwritten.

  ## Subflows and forms

  A node that embeds another flow carries that flow's id in `subflow_id` —
  the reference behind `FormFlow.Data.Templates.Flows`' subflow operations. A form
  node carries its form's *lineage* id in `form_id` — never a version id:
  which version to show is a read-time and instance-pin concern (see
  `archive/form-versioning.md`, Decision 3), and a node inside a shared
  reusable subflow has one pointer but many consumers. Both references follow
  the same dual-write rule as `flow_id`, with one addition: when only the
  `properties` copy arrives (the editor round-trips properties untouched), the
  column adopts it, so a subflow or form node surviving an editor save keeps
  its reference. In Neo4j the subflow reference becomes an `EMBEDS`
  relationship — see the Neo4j guide (`guides/neo4j.md`).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias FormFlow.Data.Templates
  alias FormFlow.Data.Templates.Flow

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "form_flow_nodes" do
    field(:labels, {:array, :string}, default: [])
    field(:properties, :map, default: %{})

    belongs_to(:flow, Flow)
    belongs_to(:subflow, Flow, foreign_key: :subflow_id)
    belongs_to(:form, Templates.Form, foreign_key: :form_id)

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Builds a changeset for a node.

  `:id` is castable so callers can supply their own UUIDs — that is how ids
  stay stable when `FormFlow.Data.Templates.Flows.update/2` replaces a flow's
  contents.
  """
  def changeset(node, attrs) do
    node
    |> cast(attrs, [:id, :flow_id, :subflow_id, :form_id, :labels, :properties])
    |> validate_required([:flow_id])
    |> adopt_from_properties(:subflow_id, "subflow_id")
    |> adopt_from_properties(:form_id, "form_id")
    |> derive_labels_from_kind()
    |> copy_into_properties(:flow_id, "flow_id")
    |> copy_into_properties(:subflow_id, "subflow_id")
    |> copy_into_properties(:form_id, "form_id")
    |> foreign_key_constraint(:flow_id)
    |> foreign_key_constraint(:subflow_id)
    |> foreign_key_constraint(:form_id)
  end

  # The editor round-trips properties untouched, so a saved subflow or form
  # node arrives with only the properties copy — the column adopts it. An
  # explicit reference in the attributes wins over the copy (copy_flow relies
  # on this: it passes the *new* id so a stale property copy can't re-point a
  # copied node at the original).
  defp adopt_from_properties(changeset, field, key) do
    properties = get_field(changeset, :properties) || %{}

    case {get_field(changeset, field), properties[key]} do
      {nil, id} when is_binary(id) ->
        case Ecto.UUID.cast(id) do
          {:ok, id} -> put_change(changeset, field, id)
          :error -> add_error(changeset, field, "is invalid")
        end

      _other ->
        changeset
    end
  end

  # Labels categorize what a node *is*, Neo4j-style. The editor never sets
  # them — they are derived from the ReactFlow `kind`/`type` already in
  # properties, so every node gets one without the client needing to know the
  # mapping. Only kicks in when nothing already set labels explicitly (e.g.
  # copy_flow, which carries a source node's labels forward as-is).
  defp derive_labels_from_kind(changeset) do
    case get_field(changeset, :labels) do
      [] ->
        properties = get_field(changeset, :properties) || %{}

        case label_for_kind(properties) do
          nil -> changeset
          label -> put_change(changeset, :labels, [label])
        end

      _labels ->
        changeset
    end
  end

  defp label_for_kind(%{"type" => "subflow"}), do: "Subflow"

  defp label_for_kind(properties) do
    case get_in(properties, ["data", "kind"]) do
      "start" -> "Start"
      "form" -> "Form"
      "end" -> "End"
      _other -> nil
    end
  end

  # The dual-write: properties carry a copy of the column, for Neo4j
  defp copy_into_properties(changeset, field, key) do
    case get_field(changeset, field) do
      nil ->
        changeset

      value ->
        properties = get_field(changeset, :properties) || %{}

        put_change(changeset, :properties, Map.put(properties, key, value))
    end
  end
end
