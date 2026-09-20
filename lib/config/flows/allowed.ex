defmodule FormFlow.Config.Flows.Allowed do
  @moduledoc """
  One flow a page is about, and what that page lets a user do with it:
  begin a new journey of it (`:start`), and work inside a journey of it
  (`:continue`).

  This is **per page**, which is what sets it apart from everything else in
  `FormFlow.Config.Flows`. A `FormFlow.Config.Flows.Type` is global
  behaviour of a kind of flow - every flow of that type behaves that way
  wherever it is drawn. An `Allowed` is one page's answer about one flow:
  the same Dog License is startable on the applications page and not on the
  reviews page, because those two pages say so.

  It is what the `flows` attr of `FormFlow.Web.router/1` takes:

      alias FormFlow.Config.Flows.Allowed

      <FormFlow.Web.router
        flows={[
          Allowed.new(flow_slug: "dog-license", start: false),
          Allowed.new(flow_slug: "cat-license", start: false)
        ]}
        ...
      />

  Leaving the attr unset is the other value it takes: every root flow of
  the tenant, everything allowed. A list names exactly the flows the page
  is about, so a flow authored tomorrow does not appear on the page until
  the host says so.

  ## Naming the flow

  Exactly one of three fields, so the value is never read two ways:

    * `flow` - a loaded `FormFlow.Data.Templates.Flow`
    * `flow_id` - its id
    * `flow_slug` - its slug, which is unique **per tenant**, so it is
      paired with the router's `tenant_id`

  `new/1` refuses none of them and refuses more than one.

  ## The two answers

  `start` and `continue`, both `true` by default, so
  `Allowed.new(flow_slug: "dog-license")` is a fully enabled flow. They are
  named for the action atoms `FormFlow.Data.Templates.Flow.allows?/2`
  takes, because the page's answer and the flow's status are asked in one
  vocabulary and the effective rule is one sentence: **a page allows an
  action when its own answer and the flow's status both allow it.** A
  `winding_down` flow with `start: true` is still not offered.

  Setting `start: true, continue: false` is refused by `new/1`: it says the
  page will begin a journey and then refuse to let anyone work in it, which
  writes a row to the database and lands the user on a refusal. The three
  states that are left say everything a page needs:

  | Written | Effect |
  |---|---|
  | absent from the list | not on this page; its instance pages refuse it |
  | `start: false, continue: false` | listed; journeys open read-only |
  | `start: false, continue: true` | listed; journeys workable; no Start button |
  | the defaults | everything |

  ## There is no `see` field

  Membership already answers `:see`. A flow in the list may be looked at
  here; a flow absent from it may not, which is what the instance pages do
  with the attr. `see: true` would be the default and say nothing new, and
  `see: false` is either a contradiction of `continue` or the same thing as
  leaving the flow out of the list.

  ## Not access control

  Like every listing attr on the router, this is a convenience for drawing
  a page, not a gate. A host authorizes with the router's `on_mount`.
  `new/1` is the way in - a hand-written `%Allowed{}` skips its checks, as
  any struct in Elixir does.
  """

  alias FormFlow.Data.Templates

  defstruct [:flow, :flow_id, :flow_slug, start: true, continue: true]

  @type t :: %__MODULE__{
          flow: Templates.Flow.t() | nil,
          flow_id: String.t() | nil,
          flow_slug: String.t() | nil,
          start: boolean(),
          continue: boolean()
        }

  @handles [:flow, :flow_id, :flow_slug]

  @doc """
  Builds an `Allowed`, refusing the two things a host can write that cannot
  mean anything: no flow named or several named, and `start: true` beside
  `continue: false`.

  Not `new!/1`, though it raises: the bang marks the raising member of a
  pair, and there is no non-raising sibling. Every refusal here is a
  programmer error in a template, not a condition a host would handle.
  """
  @spec new(keyword() | map()) :: t()
  def new(attrs) do
    allowed = struct!(__MODULE__, attrs)

    allowed
    |> validate_handle()
    |> validate_chain()
  end

  @doc """
  Whether this page allows `action` on this flow: `:start` and `:continue`
  read their fields, and `:see` is `true` - membership in the page's
  `flows` is what answers it.

  The flow's status is the other half of the rule and is asked separately
  (`FormFlow.Web.Instances.Shared.status_allows?/3`); an action needs both.
  """
  @spec allows?(t(), :start | :continue | :see) :: boolean()
  def allows?(%__MODULE__{start: start}, :start), do: start
  def allows?(%__MODULE__{continue: continue}, :continue), do: continue
  def allows?(%__MODULE__{}, :see), do: true

  @doc """
  Whether this is the flow the struct names - by loaded struct, by id, or
  by slug, whichever handle is set. The flow is taken as given, so a caller
  that cares about the tenant checks it itself.
  """
  @spec names?(t(), Templates.Flow.t()) :: boolean()
  def names?(%__MODULE__{flow: %Templates.Flow{id: id}}, %Templates.Flow{id: id}), do: true
  def names?(%__MODULE__{flow_id: id}, %Templates.Flow{id: id}) when is_binary(id), do: true

  def names?(%__MODULE__{flow_slug: slug}, %Templates.Flow{slug: slug}) when is_binary(slug),
    do: true

  def names?(%__MODULE__{}, %Templates.Flow{}), do: false

  @doc """
  The handle that is set, as `{:flow, flow}`, `{:flow_id, id}` or
  `{:flow_slug, slug}`, raising when none or several are - the check
  `new/1` runs, exposed for the pages that resolve a struct they did not
  build.
  """
  @spec handle(t()) :: {:flow | :flow_id | :flow_slug, term()}
  def handle(%__MODULE__{} = allowed) do
    allowed = validate_handle(allowed)
    field = Enum.find(@handles, &(not is_nil(Map.fetch!(allowed, &1))))

    {field, Map.fetch!(allowed, field)}
  end

  defp validate_handle(%__MODULE__{} = allowed) do
    case Enum.filter(@handles, &(not is_nil(Map.fetch!(allowed, &1)))) do
      [_one] ->
        allowed

      [] ->
        raise ArgumentError,
              "a flow must be named by exactly one of :flow, :flow_id or :flow_slug; none was given"

      several ->
        raise ArgumentError,
              "a flow must be named by exactly one of :flow, :flow_id or :flow_slug; " <>
                "got #{inspect(several)}"
    end
  end

  defp validate_chain(%__MODULE__{start: true, continue: false}) do
    raise ArgumentError,
          "a flow cannot be startable and not continuable: starting one lands the " <>
            "user in a journey this page would then refuse to open"
  end

  defp validate_chain(%__MODULE__{} = allowed), do: allowed
end
