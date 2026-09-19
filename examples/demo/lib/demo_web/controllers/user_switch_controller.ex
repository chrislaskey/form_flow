defmodule DemoWeb.UserSwitchController do
  @moduledoc """
  Switches the demo's current user: stores the chosen id in the session and
  sends the visitor to that user's landing page (`Demo.Users`), the page the
  new perspective is for. `POST /switch-user/:user_id`.

  Landing rather than staying put: the demo is unguided, and the page someone
  switched from is rarely one the new perspective is admitted to, so staying
  put means a refusal on nearly every switch. A refusal still stands for
  anyone who then navigates to a page their perspective is not for.
  """

  use DemoWeb, :controller

  alias Demo.Users

  def create(conn, params) do
    case Users.fetch(params["user_id"]) do
      {:ok, user} ->
        conn
        |> put_session(Users.session_key(), user.id)
        |> redirect(to: user.landing)

      :error ->
        conn
        |> put_flash(:error, "That demo user does not exist.")
        |> redirect(to: return_to(conn))
    end
  end

  # Nothing switched, so a failed switch stays where it was: back to the
  # referring page (path and query only, so an outside referer cannot turn
  # this into an open redirect), or the index without one.
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
