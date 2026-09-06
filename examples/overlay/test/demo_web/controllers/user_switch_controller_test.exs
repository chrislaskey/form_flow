defmodule DemoWeb.UserSwitchControllerTest do
  use DemoWeb.ConnCase

  alias Demo.Users

  test "stores the user in the session and returns to the referring page", %{conn: conn} do
    conn =
      conn
      |> put_req_header("referer", "http://localhost:4001/users?page=2")
      |> post(~p"/switch-user/cat_owner")

    assert redirected_to(conn) == "/users?page=2"
    assert get_session(conn, Users.session_key()) == "cat_owner"
  end

  test "returns to the index without a referer", %{conn: conn} do
    conn = post(conn, ~p"/switch-user/dog_owner")

    assert redirected_to(conn) == "/"
  end

  test "keeps only the path of a referer on another host", %{conn: conn} do
    conn =
      conn
      |> put_req_header("referer", "https://example.com/somewhere")
      |> post(~p"/switch-user/dog_owner")

    assert redirected_to(conn) == "/somewhere"
  end

  test "an unknown user leaves the session alone and flashes an error", %{conn: conn} do
    conn = post(conn, ~p"/switch-user/nobody")

    assert redirected_to(conn) == "/"
    refute get_session(conn, Users.session_key())
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "does not exist"
  end
end
