defmodule FormFlow.Web.Instances do
  @moduledoc """
  `FormFlow.Web.Instances` namespace for the user-facing side of FormFlow -
  people working through flow instances and filling out the forms in them, as
  opposed to `FormFlow.Web.Templates`, where admins design the flows and
  forms.

  Served by `FormFlow.Web.Router` when `type="instances"` (the default):

    * `FormFlow.Web.Instances.Flows.Index` - the user's flow instances, and
      starting new ones
    * `FormFlow.Web.Instances.Flows.Show` - one instance's forms with
      derived progress, and where the viewer stands in it
    * `FormFlow.Web.Instances.Flows.History` - what has happened in the
      instance, newest first
    * `FormFlow.Web.Instances.Forms.Show` - the answers at one position,
      read-only
    * `FormFlow.Web.Instances.Forms.Edit` - the same position, editable -
      the page that starts a form
    * `FormFlow.Web.Instances.Forms.History` - what has happened to the
      form there, newest first

  The three form pages are the three views of one form, and the header
  offers them as tabs - Edit, View, History
  (`FormFlow.Web.Instances.Components.Forms.Tabs`) - beside the form's
  status and its last event (`FormFlow.Web.Instances.Components.Forms.Status`).
  The two flow instance pages are likewise its two views - Overview,
  History (`FormFlow.Web.Instances.Components.Flows.Tabs`) - beside the
  instance's status for the viewer - its perspective status
  (`FormFlow.Web.Instances.Components.Flows.Status`).
  What the two share - the instance, its forms, the viewer's rows, the
  trail - is `FormFlow.Web.Instances.Flows.Shared`.

  Plus `FormFlow.Web.Instances.Components.Header` (the breadcrumb and title
  every page puts above its content, the same shape as the templates
  side's; a form page's is sticky), `FormFlow.Web.Instances.Components.Flows.Progress`
  (the card saying where the user is in the flow's forms) and
  `FormFlow.Web.Instances.Paths` (every URL these pages link to).

  Which forms a user may navigate to, and where submitting takes them, is
  the `FormFlow.Config.Flows.Type` a flow's `flow_type` resolves to
  (`FormFlow.Web.Instances.Forms.Shared.flow_type/2`) - the pages ask, they
  don't decide.

  What each page decided, it names once:
  `FormFlow.Web.Instances.Shared.page_state/1` and `form_page_state/1` turn
  a page's assigns into the one state it is in, which every `render/1`
  clause matches on and every event guards on. That module is the sibling of
  `FormFlow.Web.Templates.Shared`; `FormFlow.Web.Instances.Forms.Shared` is
  narrower, and is what the two *form* pages have in common.

  The namespaces mirror the data side (`FormFlow.Data.Instances.Flows` /
  `.Forms`) and, page for page, the template side - same modules, same
  nouns, because `/admin/flows/:id` and `/users/:id` are the template and the
  instance of the same thing. The user-facing side has one section, so its
  mount root is the listing itself (`FormFlow.Web.Instances.Paths`).
  """
end
