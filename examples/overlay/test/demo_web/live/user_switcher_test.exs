defmodule DemoWeb.UserSwitcherTest do
  use DemoWeb.ConnCase

  import Phoenix.LiveViewTest

  test "the header shows the default user before switching", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert render(element(view, "#header-user-switcher summary")) =~ "Docs Reader"
    assert has_element?(view, "#perspective-user-switcher")
  end

  test "switching changes the user every page is viewed as", %{conn: conn} do
    conn = post(conn, ~p"/switch-user/reviewer")

    {:ok, view, _html} = live(conn, ~p"/install-check")

    {:ok, reviewer} = Demo.Users.fetch("reviewer")

    assert render(element(view, "#header-user-switcher summary")) =~ reviewer.name

    assert has_element?(
             view,
             ~s(#header-user-switcher a[data-to="/switch-user/reviewer"][aria-selected="true"])
           )

    assert has_element?(
             view,
             ~s(#header-user-switcher a[data-to="/switch-user/dog_owner"][aria-selected="false"])
           )
  end

  test "menu rows are method=post links, not a form on every page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(
             view,
             ~s(#header-user-switcher a[data-method="post"][data-to="/switch-user/cat_owner"][data-csrf])
           )

    refute has_element?(view, "#header-user-switcher form")
  end
end
