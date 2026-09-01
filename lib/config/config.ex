defmodule FormFlow.Config do
  @callback enabled_flow_types(FormFlow.Context.t(), map()) :: list(FormFlow.Config.Flows.Type.t())
  @callback enabled_form_types(FormFlow.Context.t(), map()) :: list(FormFlow.Config.Forms.Type.t())

  defmacro __using__(_opts) do
    quote do
      @behaviour FormFlow.Config

      def enabled_flow_types(context, config_data) do
        FormFlow.Web.Components.Config.Default.enabled_flow_types(context, config_data)
      end

      def enabled_form_types(context, config_data) do
        FormFlow.Web.Components.Config.Default.enabled_form_types(context, config_data)
      end

      def overridable [enabled_flow_types: 1, enabled_form_types: 1]
    end
  end
end
