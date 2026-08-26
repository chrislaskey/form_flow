defmodule DemoWeb.FormFlowLive.Users.Config do
  use FormFlow.Config

  @impl true
  def example(map, _context, _config_data), do: map

  @impl true
  def properties(default, _context, config_data) do
    Map.merge(default, Map.get(config_data, :properties, %{}))
  end
end
