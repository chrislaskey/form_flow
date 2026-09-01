defmodule FormFlow.Web.Components.Config.Default do
  @behaviour FormFlow.Config

  def enabled_flow_types(_formflow_context, _config_data) do
    [
      %FormFlow.Config.Flows.Type{
        id: "wizard_any_order",
        module: FormFlow.Web.Instances.Components.Flows.Types.WizardAnyOrder,
        name: "Wizard (any order)",
        description: "Form wizard. Users can jump ahead and complete in any order.",
        properties: []
      },
      %FormFlow.Config.Flows.Type{
        id: "wizard_in_order",
        module: FormFlow.Web.Instances.Components.Flows.Types.WizardInOrder,
        name: "Wizard (in order)",
        description: "Form wizard. Users must complete in in order.",
        properties: []
      }
    ]
  end

  def enabled_form_types(_formflow_context, _config_data) do
    []
  end
end
