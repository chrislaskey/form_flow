defmodule FormFlow.Web.Instances do
  @moduledoc """
  `FormFlow.Web.Instances` namespace for the user-facing side of FormFlow —
  people going through journeys and filling out form instances, as opposed
  to `FormFlow.Web.Templates`, where admins design the flows and forms.

  Served by `FormFlow.Web.Router` when `type="instances"` (the default):

    * `FormFlow.Web.Instances.Flows.Index` — the user's journeys, and
      starting new ones
    * `FormFlow.Web.Instances.Flows.Show` — one journey's forms with
      derived progress
    * `FormFlow.Web.Instances.Forms.Show` — one form instance, rendered with
      `DynamicForm`

  plus two pieces both pages share:
  `FormFlow.Web.Instances.Components.FlowProgress` (a flow's forms and their
  state, drawn) and `FormFlow.Web.Instances.Positions` (opening one).

  Which forms a filler may navigate to, and where submitting takes them, is
  the `FormFlow.Flows.Types` module a flow's `form_flow_type` resolves to —
  the pages ask, they don't decide.

  The namespaces mirror the data side (`FormFlow.Data.Instances.Flows` /
  `.Forms`), the same way `FormFlow.Web.Templates` mirrors
  `FormFlow.Data.Templates`.
  """
end
