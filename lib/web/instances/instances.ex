defmodule FormFlow.Web.Instances do
  @moduledoc """
  `FormFlow.Web.Instances` namespace for the user-facing side of FormFlow —
  people going through journeys and filling out form instances, as opposed
  to `FormFlow.Web.Templates`, where admins design the flows and forms.

  Served by `FormFlow.Web.Router` when `type="instances"` (the default):

    * `FormFlow.Web.Instances.Flows.Index` — the user's journeys, and
      starting new ones
    * `FormFlow.Web.Instances.Flows.Show` — one journey's positions with
      derived progress
    * `FormFlow.Web.Instances.Forms.Show` — one form instance, rendered with
      `DynamicForm`

  The namespaces mirror the data side (`FormFlow.Data.Instances.Flows` /
  `.Forms`), the same way `FormFlow.Web.Templates` mirrors
  `FormFlow.Data.Templates`.
  """
end
