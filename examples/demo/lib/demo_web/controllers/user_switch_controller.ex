defmodule DemoWeb.UserSwitchController do
  @moduledoc """
  Switches the demo's current user: stores the chosen id in the session and
  sends the visitor back to the page they were on, which reloads it as the new
  user. `POST /switch-user/:user_id`.
  """

  use DemoWeb, :controller

  alias Demo.Users

  def create(conn, params) do
    case Users.fetch(params["user_id"]) do
      {:ok, user} ->
        conn
        |> put_session(Users.session_key(), user.id)
        |> redirect(to: return_to(conn))

      :error ->
        conn
        |> put_flash(:error, "That demo user does not exist.")
        |> redirect(to: return_to(conn))
    end
  end

  # Back to the referring page (path and query only, so an outside referer
  # cannot turn this into an open redirect), or the index without one.
  defp return_to(conn) do
    with [referer | _] <- get_req_header(conn, "referer"),
         %URI{path: path, query: query} when is_binary(path) <- URI.parse(referer),
         false <- String.starts_with?(path, "/switch-user") do
      if query, do: path <> "?" <> query, else: path
    else
      _ -> "/"
    end
  end
end
