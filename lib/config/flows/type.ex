defmodule FormFlow.Config.Flows.Type do
  defstruct [:id, :module, :name, :description, :properties]

  @callback form_progress_component(map()) :: any()

  defmacro __using__(_opts) do
    quote do
      @behaviour FormFlow.Config.Flows.Type

      @doc "Form progress component, return `nil` to not show"
      def form_progress_component(assigns) do
        FormFlow.Web.Instances.Components.Flows.Types.Default.form_progress_component(assigns)
      end

      def overridable [form_progress_component: 1]
    end
  end
end
