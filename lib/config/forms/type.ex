defmodule FormFlow.Config.Forms.Type do
  @moduledoc """
  Flow type definition
  """

  defstruct [:id, :module, :name, :description, :properties]

  @type t :: %__MODULE__{
          id: String.t(),
          module: module(),
          name: String.t(),
          description: String.t() | nil,
          properties: keyword() | map() | nil
        }

  @callback example() :: :ok

  defmacro __using__(_opts) do
    quote do
      @behaviour FormFlow.Config.Forms.Type

      def example(), do: :ok

      defoverridable example: 0
    end
  end
end
