defmodule DemoWeb.HomeLiveTest do
  use DemoWeb.ConnCase

  import Phoenix.LiveViewTest

  test "renders the demo index", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "FormFlow demo"
    assert has_element?(view, "#form-flow-version")
    assert has_element?(view, "#perspective")
  end

  test "reports the compiled form_flow version", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    version = to_string(Application.spec(:form_flow, :vsn))

    assert version != ""
    assert render(element(view, "#form-flow-version")) =~ version
  end

  test "is the only route at the root: nothing falls through to it", %{conn: conn} do
    assert get(conn, "/flows").status == 404
  end
end
