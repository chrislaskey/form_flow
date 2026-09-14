defmodule DemoWeb.DocsLive.IntroductionLiveTest do
  use DemoWeb.ConnCase

  import Phoenix.LiveViewTest

  test "renders the README's introduction", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/docs/introduction")

    assert html =~ "Introduction"
    assert html =~ "forms as data"
    assert has_element?(view, "#why-form-flow")
    assert has_element?(view, "#how-do-i-use-it")
  end

  test "the nav jumps to every section the page renders", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/docs/introduction")

    document = LazyHTML.from_fragment(html)

    anchors =
      document
      |> LazyHTML.query("#docs-nav a[href^='#']")
      |> LazyHTML.attribute("href")

    assert anchors == ["#why-form-flow", "#how-do-i-use-it"]

    for anchor <- anchors do
      assert LazyHTML.query(document, anchor) != []
    end
  end

  test "opens with the same words as the demo index", %{conn: conn} do
    {:ok, _view, docs} = live(conn, ~p"/docs/introduction")
    {:ok, _view, index} = live(conn, ~p"/")

    for line <- ["Batteries included library", "FormFlow solves this problem"] do
      assert docs =~ line
      assert index =~ line
    end
  end
end
