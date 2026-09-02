defmodule FormFlow.Web.Components.Forms.Types.Default do
  @moduledoc """
  `FormFlow.Config.Forms.Type`'s defaults — what every form type inherits for
  the callbacks it doesn't override: the form renders whatever the user has
  answered so far, and nothing else.
  """

  use FormFlow.Config.Forms.Type

  alias FormFlow.Context

  @impl true
  def initial_data(%Context{form_instance: %{data: data}}, _config_data), do: data
  def initial_data(%Context{form_instance: nil}, _config_data), do: %{}
end
