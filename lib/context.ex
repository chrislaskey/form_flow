defmodule FormFlow.Context do
  @moduledoc """
  The value passed to every `FormFlow.Config` callback, alongside its own
  `config_data` argument.

  One common shape lets high-granularity config callbacks all read the same
  fields instead of each expecting a different payload. Every field is optional
  — a callback firing near the top of the router (before anything has been
      loaded) sees mostly `nil`; one firing deep inside a specific
  LiveComponent sees whatever that call site has in scope.

  ## Fields

    * `:user_id` - the acting user's opaque host-app identity, or `nil` — not
      populated anywhere yet; the web layer has no current-user concept today
    * `:flow` - the root `FormFlow.Data.Templates.Flow` — the top-level
      ancestor, however deep the current view has drilled in
    * `:subflow` - the `FormFlow.Data.Templates.Flow` whose content is
      currently being rendered. Equal to `:flow` when there is no drill-in.
      When viewing a subflow node's embedded flow, this is the *embedded*
      flow (`node.subflow`); when viewing a node's embedded form, this is the
      flow the node itself lives in (`node.flow`), since there is no deeper
      flow to embed
    * `:subflow_node` - the `FormFlow.Data.Templates.Flow.Node` in scope, or `nil`
      when viewing a flow directly with no node drill-in
    * `:form` - the `FormFlow.Data.Templates.Form` lineage in scope, or `nil`
    * `:form_version` - the specific `FormFlow.Data.Templates.Form.Version`
      in scope, or `nil`

  On the user-facing side — someone working through a flow instance — three
  more fields carry the live state a `FormFlow.Config.Flows.Type` reasons
  about; template-side callbacks see them as `nil`:

    * `:flow_instance` - the `FormFlow.Data.Instances.Flow` being worked
    * `:form_instance` - the `FormFlow.Data.Instances.Form` at the form in
      question, or `nil` until the user starts it
    * `:form_progress` - the `FormFlow.Data.Instances.FormProgress` of the
      form in question: its position, derived status, and live instance
    * `:flow_progress` - the progress of the "forms" flow that form belongs
      to (`:subflow`): every form of it, in the order they are worked, as
      `FormProgress` structs — what `FormFlow.Data.Instances.FlowProgress.forms_in_flow/2`
      returns

  `:config_data` is deliberately not a field here — it is passed to callbacks
  as its own argument, since it is caller-supplied and unrelated to what
  FormFlow itself knows about the current request.
  """

  defstruct [
    :user_id,
    :flow,
    :subflow,
    :subflow_node,
    :form,
    :form_version,
    :flow_instance,
    :form_instance,
    :form_progress,
    :flow_progress
  ]

  @type t :: %__MODULE__{
          user_id: String.t() | nil,
          flow: FormFlow.Data.Templates.Flow.t() | nil,
          subflow: FormFlow.Data.Templates.Flow.t() | nil,
          subflow_node: FormFlow.Data.Templates.Flow.Node.t() | nil,
          form: FormFlow.Data.Templates.Form.t() | nil,
          form_version: FormFlow.Data.Templates.Form.Version.t() | nil,
          flow_instance: FormFlow.Data.Instances.Flow.t() | nil,
          form_instance: FormFlow.Data.Instances.Form.t() | nil,
          form_progress: FormFlow.Data.Instances.FormProgress.t() | nil,
          flow_progress: [FormFlow.Data.Instances.FormProgress.t()] | nil
        }
end
