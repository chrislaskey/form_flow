defmodule FormFlow.Web.Router do
  @moduledoc """
  `FormFlow.Web.Router` module contains an optional path-based router that
  works with Phoenix `*path` catch-all routes and the default routes.

  Using the router simplifies the amount of the parent app has to define.

  Custom installations can skip the router and call the LiveComponents directly
  if that's easier.
  """

  @doc """
  Optional component to route using the `*path` helper concept in Phoenix
  Routers. Will automaticlaly redirect to the LiveComponents using the path value.

  Users can opt to directly call LiveComponents instead.
  """

  use Phoenix.Component

  attr(:type, :string, values: ["instances", "templates"], required: true)
  attr(:path, :string, required: true)

  attr(:app, :string, default: "default")

  def router(assigns) do
    ~H"""
    <div>
      <h1>Hello from {@app} showing {@type}</h1>
      <%= if @type == "templates" do %>
        <.live_component
          :if={matches?("/forms", @path)}
          module={FormFlow.Web.Templates.Forms.Index}
          id="forms-index"
          app={@app}
        />

        <.live_component
          :if={matches?("/forms/1", @path)}
          module={FormFlow.Web.Templates.Forms.Show}
          id="forms-show"
          app={@app}
        />
      <% end %>
    </div>
    """
  end

  defp matches?(pattern, path_parts) when is_list(path_parts) do
    matches?(pattern, "/#{Enum.join(path_parts, "/")}")
  end

  defp matches?(pattern, path) when is_bitstring(path) do
    pattern == path
  end
end
