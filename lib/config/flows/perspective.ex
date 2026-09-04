defmodule FormFlow.Config.Flows.Perspective do
  @moduledoc """
  Perspective definition: one kind of user a "forms" flow is for — the
  applicant, the regional reviewer, the final approver.

  A flow type declares them: `FormFlow.Config.Flows.Type`'s `:perspectives`
  is a list of these, beside its `:properties`. The struct is what the
  host describes — `:id`, `:name`, `:description`, and whatever else the
  host wants to carry along in `:metadata` — and the admin building a
  template picks from the chosen type's, on the identity form of each
  "forms" flow, which perspectives that flow is for. The picked ids are
  stored on the flow under `properties["perspectives"]`; `for_flow/2`
  resolves them back to the structs at run time, through the flow's type, so
  a type's callbacks see everything the host declared, not just the id.

  Roles belong with the type that gives them meaning: a review type declares
  its reviewers and approvers, and a plain wizard declares none — its flows
  are for everyone. The host sets the list when it builds the type structs it
  passes as `flow_types`, the library's built-in wizards included, so the
  vocabulary is per type and per use at once.

  A perspective is set on a flow of forms, and only there: the forms inside
  read their flow's, and a "subflows" root has none of its own. When one
  flow's forms belong to different perspectives, the flow is split into
  subflows — one place to look, no overrides.

  The property *states* which perspectives a flow is for; what that means is
  the flow type's to implement, in `FormFlow.Config.Flows.Type`'s
  `visible?/2` and `editable?/2`. The library's defaults read it as
  `visible?/1` here: a flow is for everyone when it names no perspective, a
  viewer with no perspective sees everything, and otherwise the flow shows
  for a viewer sharing at least one of its perspectives. Perspective is
  routing and hiding, not authorization — the router's `on_mount` is the
  gate.

  The viewer's perspectives arrive through the `perspectives` attr of
  `FormFlow.Web.router/1` and the instance LiveComponents — a string or a
  list of strings — and land on `FormFlow.Context` as `:perspectives`.
  """

  alias FormFlow.Context
  alias FormFlow.Data.Templates.Flow

  @key "perspectives"

  defstruct [:id, :name, :description, metadata: %{}]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          description: String.t() | nil,
          metadata: map()
        }

  @doc "The key the picked ids are stored under in a flow's `properties`."
  def key, do: @key

  @doc "The perspective ids a flow is for — stored on it by the admin; `[]` for everyone."
  @spec ids(Flow.t() | nil) :: [String.t()]
  def ids(%Flow{properties: properties}), do: List.wrap(Map.get(properties || %{}, @key, []))
  def ids(nil), do: []

  @doc """
  The perspectives a flow is for, as structs, in the order its type declares
  them — `declared` being the type's `:perspectives`. A stored id the type
  does not declare is dropped here — `stale_ids/2` is where the editor
  learns about it.
  """
  @spec for_flow(Flow.t() | nil, [t()]) :: [t()]
  def for_flow(flow, declared) do
    stored = ids(flow)
    Enum.filter(declared, &(&1.id in stored))
  end

  @doc "The stored ids the type does not declare — a vocabulary the host changed under the template."
  @spec stale_ids(Flow.t() | nil, [t()]) :: [String.t()]
  def stale_ids(flow, declared) do
    known = MapSet.new(declared, & &1.id)
    Enum.reject(ids(flow), &MapSet.member?(known, &1))
  end

  @doc "`properties` with `ids` stored — or the key removed, when there are none."
  @spec put_ids(map(), [String.t()]) :: map()
  def put_ids(properties, []), do: Map.delete(properties, @key)
  def put_ids(properties, ids), do: Map.put(properties, @key, ids)

  @doc """
  The viewer's perspectives as the pages hold them: the attr accepts a
  string or a list of strings; `nil` is no perspective.
  """
  @spec normalize(nil | String.t() | [String.t()]) :: [String.t()]
  def normalize(nil), do: []
  def normalize(list) when is_list(list), do: Enum.map(list, &to_string/1)
  def normalize(one), do: [to_string(one)]

  @doc """
  Whether the context's `:subflow` is for one of the viewer's `:perspectives`
  — the library's default reading of the property (see the moduledoc). A
  flow naming no perspective is for everyone; a viewer with none sees
  everything.
  """
  @spec visible?(Context.t()) :: boolean()
  def visible?(%Context{subflow: flow, perspectives: viewer}) do
    flow_ids = ids(flow)
    viewer = normalize(viewer)

    flow_ids == [] or viewer == [] or Enum.any?(flow_ids, &(&1 in viewer))
  end
end
