defmodule Demo.FormFlowEditorTest do
  @moduledoc """
  Covers the two halves of how the flow editor reaches the browser: the route
  that serves the prebuilt bundle, and the hook container that fetches it.

  What can't be covered here is React itself — LiveViewTest has no JavaScript
  engine, so mounting the editor is a manual check at
  http://localhost:4000/forms.
  """

  use DemoWeb.ConnCase

  import Phoenix.LiveViewTest

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
    test "renders on the templates route with the bundle's URL", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/flows")

      assert has_element?(view, ~s(#flows-index-editor[phx-update="ignore"]))
      assert render(element(view, "#flows-index-editor")) =~ Assets.editor_path()
    end

    test "reports the graph the editor pushes back", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/flows")

      assert render(view) =~ "Loading the editor…"

      # Stands in for the hook, which pushes to the LiveComponent by element
      view
      |> element("#flows-index-editor")
      |> render_hook("form_flow:editor_mounted", %{})

      view
      |> element("#flows-index-editor")
      |> render_hook("form_flow:graph_changed", %{
        "nodes" => [
          %{"id" => "1", "data" => %{"label" => "Start"}},
          %{"id" => "2", "data" => %{"label" => "Contact details"}}
        ],
        "edges" => [%{"id" => "e1-2"}]
      })

      html = render(view)

      assert html =~ "2 steps, 1 connections"
      assert html =~ "Start, Contact details"
    end

    test "carries the Elixir-defined data as JSON for the hook to parse", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/flows")

      graph =
        view
        |> element("#flows-index-editor")
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.attribute("data-graph")
        |> hd()
        |> Jason.decode!()

      assert Enum.map(graph["nodes"], & &1["data"]["label"]) == ["Start", "Form", "End"]
      assert Enum.map(graph["nodes"], & &1["data"]["kind"]) == ["start", "form", "end"]
      assert Enum.map(graph["edges"], & &1["id"]) == ["e1-2", "e2-3"]

      # Positions and arrowheads come from ReactFlow.data/2, not from the JS
      assert Enum.map(graph["nodes"], & &1["position"]["y"]) == [0, 140, 280]
      assert Enum.map(graph["edges"], & &1["markerEnd"]["type"]) == ["arrowclosed", "arrowclosed"]
    end

    test "pins the start and end steps as non-deletable", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/flows")

      nodes =
        view
        |> element("#flows-index-editor")
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.attribute("data-graph")
        |> hd()
        |> Jason.decode!()
        |> Map.fetch!("nodes")

      # ReactFlow's own flag, passed straight through: false pins a node
      assert Enum.map(nodes, &{&1["data"]["label"], &1["deletable"]}) == [
               {"Start", false},
               {"Form", nil},
               {"End", false}
             ]
    end

    test "pushes the Elixir definition back on reset", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/flows")

      view |> element("#flows-index-editor") |> render_hook("form_flow:editor_mounted", %{})

      view |> element("button", "Reset to the Elixir definition") |> render_click()

      assert_push_event(view, "form_flow:set_graph", %{graph: graph})
      assert Enum.map(graph.nodes, & &1.data.label) == ["Start", "Form", "End"]
    end

    test "does not render the editor on other paths", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      refute has_element?(view, "#flows-index-editor")
    end
  end
end
