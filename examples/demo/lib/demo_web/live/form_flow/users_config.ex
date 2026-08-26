defmodule DemoWeb.FormFlowLive.Users.Config do
  use FormFlow.Config

  @impl true
  def example(map), do: map

  @impl true
  def properties(default, config_data) do
    Map.merge(default, Map.get(config_data, :properties, %{}))
  end
end
