defmodule DemoWeb.FormFlowLive.Admin.Config do
  use FormFlow.Config

  @doc """
  Example of definine a custom config value, maybe modifying data, and then calling
  the original implementation.
  """
  @impl true
  def form_flow_type_module(value, context, config_data) do
    FormFlow.Config.form_flow_type_module(value, context, config_data)
  end
end
