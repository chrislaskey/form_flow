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

  # Every page renders for every user until a host says otherwise
  @impl true
  def handle_instance_mount(_context, _config_data), do: {:ok, %{}}

  # The listing shows the user's own flow instances until a host says otherwise
  @impl true
  def flow_instances_query(context, _config_data) do
    FormFlow.Data.Instances.Flows.list_query(user_id: context.user_id)
  end

  # The listing offers every root flow of the tenant until a host says otherwise
  @impl true
  def enabled_instance_flows(context, _config_data) do
    FormFlow.Data.Templates.Flows.list(tenant_id: context.tenant_id)
    |> Enum.reject(& &1.made_reusable_at)
  end
end
