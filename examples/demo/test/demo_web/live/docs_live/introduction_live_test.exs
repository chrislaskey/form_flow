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

  test "the nav jumps to every section the page renders, in page order", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/docs/introduction")

    document = LazyHTML.from_fragment(html)

    anchors =
      document
      |> LazyHTML.query("#docs-nav a[href^='#']")
      |> LazyHTML.attribute("href")

    headings =
      document
      |> LazyHTML.query("h2[id]")
      |> LazyHTML.attribute("id")
      |> Enum.map(&("#" <> &1))

    assert anchors != []
    assert anchors == headings
  end

  test "shows the README's screenshots, from files the app ships", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/docs/introduction")

    sources =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("img[src*='screenshot']")
      |> LazyHTML.attribute("src")

    assert length(sources) == 2

    for src <- sources do
      file = src |> String.split("?") |> hd() |> Path.basename()
      assert File.exists?(Path.join([:code.priv_dir(:demo), "static", "images", file]))
    end
  end

  test "opens with the same words as the demo index", %{conn: conn} do
    {:ok, _view, docs} = live(conn, ~p"/docs/introduction")
    {:ok, _view, index} = live(conn, ~p"/")

    for line <- [
          "Batteries included library",
          "FormFlow solves this problem",
          "human firmly in the loop"
        ] do
      assert docs =~ line
      assert index =~ line
    end
  end
end
