defmodule FormFlow.Data.Instances.FormProgress do
  @moduledoc """
  One form's place and state within a whole root flow instance — a journey:
  where the form is, what it is called, how far along it is, and which
  "forms" flow it belongs to.

  Built by `FormFlow.Data.Instances.FlowProgress.forms/2` and the shape the
  user-facing pages render. Nothing here is persisted: it is the live
  template joined with the journey's derived progress.

  ## Fields

    * `:path` - the position, as `FormFlow.Data.Instances.Form`'s `path`
      records it: the node ids from the root flow down to this form node
    * `:node` - the form node itself — the step, whose `slug` is the handle
      a host names it by (`FormFlow.Data.Templates.Flow.Node`). Set for
      every form `FormFlow.Data.Instances.FlowProgress.forms/2` returns;
      `nil` only in a struct built by hand
    * `:label` - the form node's canvas label
    * `:ancestors` - the subflow nodes drilled through to reach it,
      outermost first; `[]` for a form in the root flow. `List.last/1` is
      the node whose embedded flow this form belongs to, and their labels
      are what `FormFlow.Data.Instances.FlowProgress.qualified_label/1`
      prefixes
    * `:status` - the derived `FormFlow.Data.Instances.FlowProgress` status
    * `:instance` - the position's live (not superseded)
      `FormFlow.Data.Instances.Form`, or `nil` until it is first started
    * `:flow` - the "forms" flow this form lives in, whose
      `properties["form_flow_type"]` names its `FormFlow.Config.Flows.Type`
  """

  defstruct [:path, :node, :label, :ancestors, :status, :instance, :flow]

  @type t :: %__MODULE__{
          path: [binary()],
          node: FormFlow.Data.Templates.Flow.Node.t() | nil,
          label: String.t(),
          ancestors: [FormFlow.Data.Templates.Flow.Node.t()],
          status: FormFlow.Data.Instances.FlowProgress.status(),
          instance: FormFlow.Data.Instances.Form.t() | nil,
          flow: FormFlow.Data.Templates.Flow.t()
        }
end
