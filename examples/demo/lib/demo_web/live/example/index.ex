defmodule DemoWeb.ExampleLive.Index do
  use DemoWeb, :live_view

  @impl true
  def handle_params(params, uri, socket) do
    socket =
      socket
      |> assign(:params, params)
      |> assign(:uri, uri)

    {:noreply, socket}
  end
end
