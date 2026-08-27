defmodule FormFlow.Data.Instances.FormProgress do
  @moduledoc """
  One form's place and state within a whole root flow instance — a journey:
  where the form is, what it is called, how far along it is, and which
  "forms" flow it belongs to.

  Built by `FormFlow.Data.Instances.FlowProgress.forms/2` and the shape every
  `FormFlow.Flows.Types` module reasons about. Nothing here is persisted: it
  is the live template joined with the journey's derived progress.

  ## Fields

    * `:path` - the position, as `FormFlow.Data.Instances.Form`'s `path`
      records it: the node ids from the root flow down to this form node
    * `:label` - the form node's canvas label
    * `:ancestors` - the subflow nodes drilled through to reach it,
      outermost first; `[]` for a form in the root flow. `List.last/1` is
      the node whose embedded flow this form belongs to, and their labels
      are what `FormFlow.Data.Instances.FlowProgress.qualified_label/1`
      prefixes
    * `:status` - the derived `FormFlow.Data.Instances.FlowProgress` status
    * `:instance` - the position's live (not superseded)
      `FormFlow.Data.Instances.Form`, or `nil` until it is first opened
    * `:flow` - the "forms" flow this form lives in, whose
      `properties["form_flow_type"]` decides how the flow's forms are
      presented (see `FormFlow.Flows.Types`)
  """

  defstruct [:path, :label, :ancestors, :status, :instance, :flow]

  @type t :: %__MODULE__{
          path: [binary()],
          label: String.t(),
          ancestors: [FormFlow.Data.Templates.Flow.Node.t()],
          status: FormFlow.Data.Instances.FlowProgress.status(),
          instance: FormFlow.Data.Instances.Form.t() | nil,
          flow: FormFlow.Data.Templates.Flow.t()
        }
end
