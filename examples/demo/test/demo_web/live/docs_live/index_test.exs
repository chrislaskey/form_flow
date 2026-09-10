defmodule DemoWeb.DocsLive.IndexTest do
  use DemoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias DemoWeb.DocsComponents

  test "lists every docs page, linked", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/docs")

    listed =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#docs-index a")
      |> LazyHTML.attribute("href")

    assert listed == Enum.map(DocsComponents.pages(), & &1.path)
  end

  test "says what each page is about", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/docs")

    for page <- DocsComponents.pages() do
      assert html =~ page.title
      assert html =~ page.description
    end
  end

  test "the header marks Docs as the section being read", %{conn: conn} do
    for path <- ["/docs" | Enum.map(DocsComponents.pages(), & &1.path)] do
      {:ok, _view, html} = live(conn, path)

      current =
        html
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("header nav a.font-semibold")
        |> LazyHTML.text()
        |> String.trim()

      assert current == "Docs"
    end
  end
end
