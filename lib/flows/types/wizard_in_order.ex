defmodule FormFlow.Flows.Types.WizardInOrder do
  @moduledoc """
  `form_flow_type` `"wizard_in_order"`: a "forms" flow's forms are completed
  front to back. Completing one moves the filler to the next place the flow
  allows work, and the flow's progress is shown but not navigable — there is
  no jumping ahead.

  The baseline type, so it overrides nothing: every callback is
  `FormFlow.Flows.Types`' default. An unset or unrecognized `form_flow_type`
  resolves here too (see `FormFlow.Config.form_flow_type_module/3`).
  """

  use FormFlow.Flows.Types
end
