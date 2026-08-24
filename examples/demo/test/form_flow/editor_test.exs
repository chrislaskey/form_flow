defmodule Demo.FormFlowEditorTest do
  @moduledoc """
  Covers the two halves of how the flow editor reaches the browser: the route
  that serves the prebuilt bundle, and the hook container that fetches it.

  What can't be covered here is React itself — LiveViewTest has no JavaScript
  engine, so mounting the editor is a manual check at
  http://localhost:4000/flows/new.
  """

  use DemoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias FormFlow.Data.Graphs
  alias FormFlow.Web.Assets

  describe "the asset route" do
    test "serves the editor bundle", %{conn: conn} do
      conn = get(conn, Assets.editor_path())

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["text/javascript"]

      # The public surface the hook calls, and the CSS the bundle carries inline
      assert conn.resp_body =~ "injectStyles"
      assert conn.resp_body =~ "ff-node"
    end

    test "is cached immutably, since the path carries a content hash", %{conn: conn} do
      conn = get(conn, Assets.editor_path())

      assert get_resp_header(conn, "cache-control") == [
               "public, max-age=31536000, immutable"
             ]

      assert Assets.editor_path() =~ Assets.hash()
    end

    test "is mounted where the library says it is", %{conn: conn} do
      assert Assets.mount_path() == "/form-flow"

      # The catch-all LiveView route must not swallow the asset path
      assert get(conn, Assets.editor_path()).status == 200
    end
  end

  describe "the editor container" do
    test "renders on the edit page with the bundle's URL", %{conn: conn} do
      {:ok, graph} = create_seeded()
      {:ok, view, _html} = live(conn, "/flows/#{graph.id}/edit")

      assert has_element?(view, ~s(#flows-edit-editor[phx-update="ignore"]))
      assert render(element(view, "#flows-edit-editor")) =~ Assets.editor_path()
    end

    test "carries the graph as JSON for the hook to parse, Start and End pinned", %{conn: conn} do
      {:ok, graph} = create_seeded()
      {:ok, view, _html} = live(conn, "/flows/#{graph.id}/edit")

      data =
        view
        |> element("#flows-edit-editor")
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.attribute("data-graph")
        |> hd()
        |> Jason.decode!()

      # The universal seed: a pinned Start and End, no middle node, no edges —
      # the user connects the dots
      assert Enum.map(data["nodes"], &{&1["data"]["label"], &1["deletable"]}) == [
               {"Start", false},
               {"End", false}
             ]

      assert data["edges"] == []
    end

    test "tells the hook the flow's declared flavor", %{conn: conn} do
      {:ok, simple} = create_seeded(%{label: "forms"})
      {:ok, complex} = create_seeded(%{label: "subflows"})

      {:ok, view, _html} = live(conn, "/flows/#{simple.id}/edit")
      assert view |> element("#flows-edit-editor") |> render() =~ ~s(data-flow-label="forms")

      {:ok, view, _html} = live(conn, "/flows/#{complex.id}/edit")
      assert view |> element("#flows-edit-editor") |> render() =~ ~s(data-flow-label="subflows")
    end

    test "the flows index is a table and never loads the bundle", %{conn: conn} do
      {:ok, view, html} = live(conn, "/flows")

      refute html =~ Assets.editor_path()
      refute has_element?(view, "[data-src]")
    end
  end

  defp create_seeded(attrs \\ %{}) do
    attrs
    |> Map.merge(%{nodes: Graphs.starter_nodes(), relationships: []})
    |> Map.put_new(:name, "Enrollment")
    |> Graphs.create()
  end
end
