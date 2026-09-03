defmodule FormFlow.Config.Default do
  @moduledoc """
  The public face of `FormFlow.Config`'s defaults — what a host gets without
  a config module, and what a custom module reaches for when its override
  wants to extend the defaults rather than replace them:

      def enabled_flow_types(context, config_data) do
        FormFlow.Config.Default.enabled_flow_types(context, config_data) ++ [my_type()]
      end

  Delegates to the private internal implementation in
  `FormFlow.Web.Components.Config.Default`
  """

  @behaviour FormFlow.Config

  alias FormFlow.Web.Components.Config

  defdelegate enabled_flow_types(context, config_data), to: Config.Default
  defdelegate enabled_form_types(context, config_data), to: Config.Default
  defdelegate enabled_perspectives(context, config_data), to: Config.Default
  defdelegate handle_instance_mount(context, config_data), to: Config.Default
  defdelegate flow_instances_query(context, config_data), to: Config.Default
  defdelegate enabled_instance_flows(context, config_data), to: Config.Default
end
