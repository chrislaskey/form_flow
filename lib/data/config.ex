defmodule FormFlow.Config do
  @moduledoc "use FormFlow.Config behaviour"

  @callback example(map()) :: map()
  @callback properties(map(), map()) :: map()

  defmacro __using__(_opts) do
    quote do
      @behaviour FormFlow.Config

      def example(value), do: value

      def properties(default, _config_data), do: default

      defoverridable example: 1, properties: 2
    end
  end
end
