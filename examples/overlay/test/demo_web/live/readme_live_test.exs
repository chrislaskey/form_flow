defmodule DemoWeb.ReadmeLiveTest do
  use DemoWeb.ConnCase

  import Phoenix.LiveViewTest

  test "renders the demo index", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#form-flow-version")
    assert has_element?(view, "#form-flow-modules")
    assert has_element?(view, "#install-requirements")
  end

  test "reports the compiled form_flow version", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    version = to_string(Application.spec(:form_flow, :vsn))

    assert version != ""
    assert render(element(view, "#form-flow-version")) =~ version
  end

  test "renders FormFlow's router on the catch-all route", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#form-flow-router")

    {:ok, nested_view, _html} = live(conn, "/forms")

    assert has_element?(nested_view, "#form-flow-router")
  end
end
