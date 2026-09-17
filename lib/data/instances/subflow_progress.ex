defmodule FormFlow.Data.Instances.SubflowProgress do
  @moduledoc """
  One subflow step of a journey with its derived status - the step-level
  counterpart of `FormFlow.Data.Instances.FormProgress`, and what a
  "subflows" flow's `FormFlow.Config.Flows.Type` reasons about.

    * `path` - the step's position: the chain of subflow node ids from the
      root down to and including this step
    * `node` - the step's `FormFlow.Data.Templates.Flow.Node`; its
      `subflow_id` is the flow the step embeds
    * `label` - the step's name
    * `ancestors` - the subflow nodes drilled through to reach it, root
      first, this step excluded
    * `status` - `FormFlow.Data.Instances.FlowProgress.derive/2`'s answer for
      the step: `:available` when every predecessor step is complete,
      `:in_progress` once anything under it is started, `:completed` when
      its interior End is reached
    * `flow` - the complex flow the step is *in* (not the one it embeds):
      the flow whose type decides whether the step may be entered
  """

  defstruct [:path, :node, :label, :ancestors, :status, :flow]

  @type t :: %__MODULE__{
          path: [binary()],
          node: FormFlow.Data.Templates.Flow.Node.t() | nil,
          label: String.t(),
          ancestors: [FormFlow.Data.Templates.Flow.Node.t()],
          status: FormFlow.Data.Instances.FlowProgress.status(),
          flow: FormFlow.Data.Templates.Flow.t()
        }
end
