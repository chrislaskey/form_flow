defmodule FormFlow.Config.Forms.Type do
  defstruct [:id, :module, :name, :description, :properties]

  @callback example() :: :ok

  defmacro __using__(_opts) do
    quote do
      @behaviour FormFlow.Config.Flows.Type

      def example(), do: :ok

      def overridable [example: 1]
    end
  end
end
