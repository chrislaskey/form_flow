defmodule DemoWeb.UserSwitchController do
  @moduledoc """
  Switches the demo's current user: stores the chosen id in the session and
  sends the visitor to that user's landing page (`Demo.Users`), the page the
  new perspective is for. `POST /switch-user/:user_id`.

  Landing rather than staying put: the demo is unguided, and the page someone
  switched from is rarely one the new perspective is admitted to, so staying
  put means a refusal on nearly every switch.

  `GET /view-as/:user_id?return_to=<path>` is the same switch made on
  someone's behalf, by `DemoWeb.ExperienceEntry`, when they open a side of
  the demo their current user is not for. It goes back to `return_to` - the
  page they were opening - rather than to the user's landing page, which is
  the whole point of it: the click said where to go, and only who to be was
  missing.

  A state-changing `GET` is the wrong shape in a real application and the
  right one here. The visitor is mid-navigation, with no form to post and
  no page yet rendered to hold a CSRF token, and what it changes is which
  of five made-up people the demo is pretending to be. `create/2`, the
  switcher a visitor clicks, stays a `POST`.

  `return_to` is taken as a path and never as a URL: it must start with a
  single `/`, so neither `//host` nor `https://host` can turn this into an
  open redirect, and anything else falls back to the user's landing page.
  """

  use DemoWeb, :controller

  alias Demo.Users

  def show(conn, params) do
    case Users.fetch(params["user_id"]) do
      {:ok, user} ->
        conn
        |> put_session(Users.session_key(), user.id)
        |> redirect(to: safe_path(params["return_to"]) || user.landing)

      :error ->
        conn
        |> put_flash(:error, "That demo user does not exist.")
        |> redirect(to: "/demo")
    end
  end

  # A path of this application, or nil. One leading slash and no second one:
  # "//evil.test" and "https://evil.test" are both URLs a browser would
  # follow off this site, and both are what this refuses.
  defp safe_path("/" <> rest = path) when rest != "" do
    if String.starts_with?(rest, "/"), do: nil, else: path
  end

  defp safe_path(_other), do: nil

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
