defmodule DemoWeb.UserSwitchControllerTest do
  use DemoWeb.ConnCase

  alias Demo.Users

  test "stores the user in the session and lands on that user's page", %{conn: conn} do
    conn =
      conn
      |> put_req_header("referer", "http://localhost:4001/demo/admin/forms?page=2")
      |> post(~p"/switch-user/cat_owner")

    assert redirected_to(conn) == "/demo/pet-licenses/applications"
    assert get_session(conn, Users.session_key()) == "cat_owner"
  end

  test "every user lands on its own page, referer or not", %{conn: conn} do
    for user <- Users.all() do
      switched = post(conn, ~p"/switch-user/#{user.id}")

      assert redirected_to(switched) == user.landing
      assert get_session(switched, Users.session_key()) == user.id
    end
  end

  test "an unknown user leaves the session alone, flashes an error, and stays put", %{conn: conn} do
    conn =
      conn
      |> put_req_header("referer", "http://localhost:4001/demo/admin/forms")
      |> post(~p"/switch-user/nobody")

    assert redirected_to(conn) == "/demo/admin/forms"
    refute get_session(conn, Users.session_key())
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "does not exist"
  end

  test "a failed switch with no referer falls back to the index", %{conn: conn} do
    conn = post(conn, ~p"/switch-user/nobody")

    assert redirected_to(conn) == "/"
  end

  test "a failed switch keeps only the path of a referer on another host", %{conn: conn} do
    conn =
      conn
      |> put_req_header("referer", "https://example.com/somewhere")
      |> post(~p"/switch-user/nobody")

    assert redirected_to(conn) == "/somewhere"
  end
end
