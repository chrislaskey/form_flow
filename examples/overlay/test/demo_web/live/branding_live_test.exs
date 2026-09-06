defmodule DemoWeb.BrandingLiveTest do
  use DemoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias DemoWeb.BrandingLive.UserSwitchers

  test "renders every user switcher direction in the header and in content", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/branding")

    for %{id: id} <- UserSwitchers.directions() do
      assert has_element?(view, "##{id}-header"), "missing #{id} in the header"
      assert has_element?(view, "##{id}-content"), "missing #{id} in content"
    end
  end

  test "selecting a user updates both renderings of that direction only", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/branding")

    view
    |> element("#avatar_pill-header button", "Cat Owner")
    |> render_click()

    assert render(element(view, "#avatar_pill-header summary")) =~ "Cat Owner"
    assert render(element(view, "#avatar_pill-content summary")) =~ "Cat Owner"
    assert render(element(view, "#viewing_as-header summary")) =~ "Dog Owner"
  end

  test "?menus=open renders the header dropdowns open", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/branding?menus=open")

    assert has_element?(view, "details#avatar_pill-header[open]")
    refute has_element?(view, "details#avatar_pill-content[open]")
  end
end
