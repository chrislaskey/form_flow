defmodule FormFlow.Web.Components.Config.Default do
  @moduledoc """
  `FormFlow.Config`'s defaults — what a host gets without a config module,
  and what a custom module inherits for every callback it doesn't override.
  """

  @behaviour FormFlow.Config

  # A "forms" flow chooses how its forms are presented; a "subflows" flow
  # has no type of its own — its form subflows each carry one. First is the
  # fallback for a flow that never chose (FormFlow.Web.Instances.Forms.Shared.flow_type/2).
  @impl true
  def enabled_flow_types(%{subflow: %{label: "forms"}}, _config_data) do
    [
      %FormFlow.Config.Flows.Type{
        id: "wizard_in_order",
        module: FormFlow.Web.Components.Flows.Types.WizardInOrder,
        name: "Wizard (in order)",
        description: "Form wizard. Users must complete in order."
      },
      %FormFlow.Config.Flows.Type{
        id: "wizard_any_order",
        module: FormFlow.Web.Components.Flows.Types.WizardAnyOrder,
        name: "Wizard (any order)",
        description: "Form wizard. Users can jump ahead and complete in any order."
      }
    ]
  end

  def enabled_flow_types(_context, _config_data), do: []

  # First is the fallback for a form that never chose: the form as designed.
  @impl true
  def enabled_form_types(_context, _config_data) do
    [
      %FormFlow.Config.Forms.Type{
        id: "default",
        module: FormFlow.Config.Forms.Type.Default,
        name: "Default",
        description: "The form as designed, nothing more."
      },
      %FormFlow.Config.Forms.Type{
        id: "review",
        module: FormFlow.Web.Components.Forms.Types.Review,
        name: "Review",
        description: "Shows an earlier form's answers beside this one, for checking them.",
        properties: FormFlow.Web.Components.Forms.Types.Review.properties()
      }
    ]
  end
end
