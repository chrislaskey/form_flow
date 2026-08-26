defmodule FormFlow.Config do
  @moduledoc """
  `use FormFlow.Config` behaviour for customizing FormFlow's behavior.

  Every callback takes the value it's customizing, a `FormFlow.Config.Context`
  — one common shape every callback shares, so adding a new callback never
  means learning a new payload — and `config_data` (passed through unmodified
  from wherever `use`s this — see `FormFlow.Web.Router`'s `:config_data`
  attr).
  """

  alias FormFlow.Config.Context

  @callback example(map(), Context.t(), map()) :: map()
  @callback properties(map(), Context.t(), map()) :: map()

  defmacro __using__(_opts) do
    quote do
      @behaviour FormFlow.Config

      def example(value, _context, _config_data), do: value

      def properties(default, _context, _config_data), do: default

      defoverridable example: 3, properties: 3
    end
  end
end
