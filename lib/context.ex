defmodule FormFlow.Context do
  @moduledoc """
  The value passed to every callback a host hands FormFlow — a type's
  (`FormFlow.Config.Flows.Type`, `FormFlow.Config.Forms.Type`) and the
  router's `on_mount` — alongside the host's own `callback_data` argument.

  One common shape lets high-granularity callbacks all read the same
  fields instead of each expecting a different payload. Every field is optional
  — a callback firing near the top of the router (before anything has been
      loaded) sees mostly `nil`; one firing deep inside a specific
  LiveComponent sees whatever that call site has in scope.

  ## Fields

    * `:user_id` - the acting user's opaque host-app identity — the router's
      `user_id` attr — or `nil`
    * `:tenant_id` - the acting user's host tenant — the router's optional
      `tenant_id` attr — or `nil`, the value for a host with no tenants
    * `:perspectives` - the kinds of user the viewer is here as — the
      router's optional `perspectives` attr, as a list of
      `FormFlow.Config.Flows.Perspective` ids — or `[]`, a viewer with no
      perspective, who sees everything
    * `:flow_perspectives` - the `FormFlow.Config.Flows.Perspective` structs
      the `:subflow` is for, resolved from its stored ids through its flow
      type's `:perspectives`; `[]` for a flow that is for everyone
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
    * `:flow_type_property_values` - what an admin entered for `:subflow`'s
      flow type's properties (`FormFlow.Config.Flows.Type.property_values/1`)
    * `:form_type_property_values` - the same for `:form`'s form type
      (`FormFlow.Config.Forms.Type.property_values/1`)

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
    * `:flow_instance_progress` - the same for the whole flow instance: every
      form of every flow in it, in order (`FormFlow.Data.Instances.FlowProgress.forms/2`)
      — where a form finds one it relates to (`FormFlow.Config.Forms.Type.related_form/2`)

  `callback_data` is deliberately not a field here — it is passed to every
  callback as its own second argument. The context is FormFlow's view of the
  request; `callback_data` is the host's, filled at the mount from whatever
  the page knows, and keeping them apart is what lets a callback tell them
  apart.
  """

  defstruct [
    :user_id,
    :tenant_id,
    :flow,
    :subflow,
    :subflow_node,
    :form,
    :form_version,
    :flow_type_property_values,
    :form_type_property_values,
    :flow_instance,
    :form_instance,
    :form_progress,
    :flow_progress,
    :flow_instance_progress,
    perspectives: [],
    flow_perspectives: []
  ]

  @type t :: %__MODULE__{
          user_id: String.t() | nil,
          tenant_id: String.t() | nil,
          perspectives: [String.t()],
          flow_perspectives: [FormFlow.Config.Flows.Perspective.t()],
          flow: FormFlow.Data.Templates.Flow.t() | nil,
          subflow: FormFlow.Data.Templates.Flow.t() | nil,
          subflow_node: FormFlow.Data.Templates.Flow.Node.t() | nil,
          form: FormFlow.Data.Templates.Form.t() | nil,
          form_version: FormFlow.Data.Templates.Form.Version.t() | nil,
          flow_type_property_values: map() | nil,
          form_type_property_values: map() | nil,
          flow_instance: FormFlow.Data.Instances.Flow.t() | nil,
          form_instance: FormFlow.Data.Instances.Form.t() | nil,
          form_progress: FormFlow.Data.Instances.FormProgress.t() | nil,
          flow_progress: [FormFlow.Data.Instances.FormProgress.t()] | nil,
          flow_instance_progress: [FormFlow.Data.Instances.FormProgress.t()] | nil
        }
end
