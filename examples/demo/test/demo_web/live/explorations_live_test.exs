defmodule DemoWeb.ExplorationsLiveTest do
  use DemoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias DemoWeb.ExplorationsLive
  alias DemoWeb.ExplorationsLive.UserSwitchers

  test "the index links to every exploration, and each one renders", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/explorations")

    for %{path: path, title: title} <- ExplorationsLive.explorations() do
      assert has_element?(view, "a[href='#{path}']", title)

      assert {:ok, _view, html} = live(conn, path)
      assert html =~ "← Explorations"
    end
  end

  test "the flow instance page redraws every frame at each scenario", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/explorations/flow-instance")
    assert html =~ "Your turn"

    for {id, status} <- [
          waiting: "With the reviewer",
          reopened: "Needs your attention",
          decided: "Approved",
          started: "Your turn"
        ] do
      html =
        view
        |> element("input[type=radio][value=#{id}]")
        |> render_click()

      assert html =~ status, "scenario #{id} did not draw #{status}"
      assert html =~ "What would need building"
    end
  end

  test "renders every user switcher direction in the header and in content", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/explorations/user-switchers")

    for %{id: id} <- UserSwitchers.directions() do
      assert has_element?(view, "##{id}-header"), "missing #{id} in the header"
      assert has_element?(view, "##{id}-content"), "missing #{id} in content"
    end
  end

  test "selecting a user updates both renderings of that direction only", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/explorations/user-switchers")

    view
    |> element("#avatar_pill-header button", "Cat Owner")
    |> render_click()

    assert render(element(view, "#avatar_pill-header summary")) =~ "Cat Owner"
    assert render(element(view, "#avatar_pill-content summary")) =~ "Cat Owner"
    assert render(element(view, "#viewing_as-header summary")) =~ "Dog Owner"
  end

  test "?menus=open renders the header dropdowns open", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/explorations/user-switchers?menus=open")

    assert has_element?(view, "details#avatar_pill-header[open]")
    refute has_element?(view, "details#avatar_pill-content[open]")
  end
end
