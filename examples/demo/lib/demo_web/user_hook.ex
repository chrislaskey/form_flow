defmodule DemoWeb.UserHook do
  @moduledoc """
  `on_mount` hook that assigns `:current_user` from the session so every
  LiveView can hand it to `Layouts.app` and the user switcher.
  """

  import Phoenix.Component

  def on_mount(:default, _params, session, socket) do
    {:cont, assign(socket, :current_user, Demo.Users.from_session(session))}
  end
end
