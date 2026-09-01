defmodule FormFlow.Web.Instances do
  @moduledoc """
  `FormFlow.Web.Instances` namespace for the user-facing side of FormFlow —
  people working through flow instances and filling out the forms in them, as
  opposed to `FormFlow.Web.Templates`, where admins design the flows and
  forms.

  Served by `FormFlow.Web.Router` when `type="instances"` (the default):

    * `FormFlow.Web.Instances.Flows.Index` — the user's flow instances, and
      starting new ones
    * `FormFlow.Web.Instances.Flows.Show` — one instance's forms with
      derived progress
    * `FormFlow.Web.Instances.Forms.Show` — one form of an instance, rendered
      with `DynamicForm`, read-only or fillable

  plus `FormFlow.Web.Instances.Components.Flows.Progress` (a flow's forms and
  their state, drawn) and `FormFlow.Web.Instances.Paths` (every URL these
  pages link to).

  Which forms a user may navigate to, and where submitting takes them, is
  the `FormFlow.Config.Flows.Type` a flow's `form_flow_type` resolves to
  (`FormFlow.Web.Instances.Forms.Shared.flow_type/2`) — the pages ask, they
  don't decide.

  The namespaces mirror the data side (`FormFlow.Data.Instances.Flows` /
  `.Forms`) and, page for page, the template side — same modules, same URL
  nouns, because `/admin/flows/:id` and `/users/flows/:id` are the template
  and the instance of the same thing.
  """
end
