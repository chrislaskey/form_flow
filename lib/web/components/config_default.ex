defmodule FormFlow.Web.Components.Config.Default do
  @moduledoc """
  `FormFlow.Config`'s defaults — what a host gets without a config module,
  and what a custom module inherits for every callback it doesn't override.
  """

  @behaviour FormFlow.Config

  @impl true
  def enabled_flow_types(_context, _config_data) do
    [
      %FormFlow.Config.Flows.Type{
        id: "wizard_any_order",
        module: FormFlow.Web.Components.Flows.Types.WizardAnyOrder,
        name: "Wizard (any order)",
        description: "Form wizard. Users can jump ahead and complete in any order.",
        properties: []
      },
      %FormFlow.Config.Flows.Type{
        id: "wizard_in_order",
        module: FormFlow.Web.Components.Flows.Types.WizardInOrder,
        name: "Wizard (in order)",
        description: "Form wizard. Users must complete in order.",
        properties: []
      }
    ]
  end

  @impl true
  def enabled_form_types(_context, _config_data) do
    []
  end
end
