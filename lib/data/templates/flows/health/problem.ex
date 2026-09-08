defmodule FormFlow.Data.Templates.Flows.Health.Problem do
  @moduledoc """
  One thing `FormFlow.Data.Templates.Flows.Health` found wrong, or worth
  knowing, about a root flow.

  ## Fields

    * `:level` — how much it matters, one of `@levels`, worst first.
      `:error` means a user cannot work the flow as it stands — Start does
      not reach End, a step's form has no published version. `:warning`
      means the flow works but something in it does not take part — a step
      no Start reaches, a step nothing follows. `:info` is something an
      admin may want to act on that changes nothing for users — a draft
      with unpublished changes. The three names are the ones the pages'
      alerts and badges already use for their `kind`.
    * `:code` — a stable atom naming the check that failed, for a caller
      that acts on one kind of problem (`:end_unreachable`,
      `:form_not_published`, …). The full list is in
      `FormFlow.Data.Templates.Flows.Health`'s moduledoc.
    * `:message` — one sentence for an admin, complete on its own: it
      names the step or flow, qualified by the subflows on the way down
      the way the user-facing pages do ("Review / Check pet details").
    * `:flow_id` — the flow the problem is in: the root, or the owned
      subflow the step sits in.
    * `:node_id` — the node the problem is about, or `nil` for a problem
      with the flow itself (no End, Start does not reach End).
    * `:path` — where in the tree: the node ids from the root flow down,
      the same path `FormFlow.Data.Instances.FormProgress` addresses a
      position by. For a flow-level problem it is the path of the subflow
      node embedding that flow — `[]` for the root. `:code` and `:path`
      together are what identifies a problem from one check to the next.
    * `:ignored` — `nil`, or who set this problem aside and when
      (`FormFlow.Data.Templates.Flows.Health.ignore/3`): `%{user_id:,
      ignored_at:}`. An ignored problem is listed but not counted.
  """

  @levels [:error, :warning, :info]

  @enforce_keys [:level, :code, :message, :flow_id]
  defstruct [:level, :code, :message, :flow_id, :node_id, :ignored, path: []]

  @type level :: :error | :warning | :info

  @type t :: %__MODULE__{
          level: level(),
          code: atom(),
          message: String.t(),
          flow_id: Ecto.UUID.t(),
          node_id: Ecto.UUID.t() | nil,
          path: [Ecto.UUID.t()],
          ignored: %{user_id: String.t() | nil, ignored_at: DateTime.t() | nil} | nil
        }

  @doc "Every level, worst first."
  @spec levels() :: [level()]
  def levels, do: @levels

  @doc "A level's rank for sorting: `0` for the worst."
  @spec rank(level()) :: non_neg_integer()
  def rank(level), do: Enum.find_index(@levels, &(&1 == level))
end
