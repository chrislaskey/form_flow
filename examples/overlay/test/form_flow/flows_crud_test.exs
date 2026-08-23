defmodule Demo.FormFlowFlowsCrudTest do
  @moduledoc """
  Drives the flows CRUD pages end-to-end through the dedicated
  `live "/flows/*path", FlowsLive` route: `/flows/new` saves a graph,
  `/flows/:id` shows it read-only, `/flows/:id/edit` replaces its contents, and
  delete removes it.

  The editor's React side can't run here — LiveViewTest has no JavaScript
  engine — so edits are driven by pushing the events the hook would push.
  """

  use DemoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias FormFlow.Data.Graphs

  test "every flows path renders on the dedicated page", %{conn: conn} do
    for path <- ["/flows", "/flows/new"] do
      {:ok, view, html} = live(conn, path)

      assert html =~ "Flows"
      assert has_element?(view, "#flows-pages")
    end
  end

  test "the show canvas is read-only; the edit canvas is not", %{conn: conn} do
    id = create_flow(conn)

    {:ok, view, _html} = live(conn, "/flows/#{id}")
    assert view |> element("#flows-show-editor") |> render() =~ ~s(data-editable="false")

    {:ok, view, _html} = live(conn, "/flows/#{id}/edit")
    assert view |> element("#flows-edit-editor") |> render() =~ ~s(data-editable="true")
  end

  test "the index starts empty and lists flows with counts and actions", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/flows")
    assert html =~ "No flows yet"

    id = create_flow(conn)

    {:ok, view, html} = live(conn, "/flows")

    assert html =~ id
    assert has_element?(view, "a", "New flow")
    assert has_element?(view, ~s(a[href="/flows/#{id}"]), "Show")
    assert has_element?(view, ~s(a[href="/flows/#{id}/edit"]), "Edit")

    row = view |> element("tbody tr") |> render()

    # The starter graph: three steps, two connections
    assert row =~ ">3</td>"
    assert row =~ ">2</td>"
  end

  test "creating a flow saves the starter graph and lands on its show page", %{conn: conn} do
    {:ok, view, html} = live(conn, "/flows/new")

    assert html =~ "New flow"

    view |> element("button", "Save") |> render_click()

    {path, _flash} = assert_redirect(view)
    assert "/flows/" <> id = path

    graph = Graphs.get(id)
    assert length(graph.nodes) == 3
    assert length(graph.relationships) == 2

    {:ok, _view, html} = live(conn, path)
    assert html =~ "Flow"
    assert html =~ "Start"
    assert html =~ "End"
  end

  test "editing a flow replaces its contents", %{conn: conn} do
    id = create_flow(conn)

    {:ok, view, html} = live(conn, "/flows/#{id}/edit")
    assert html =~ "Edit flow"

    # What the hook would push after the user reduced the flow to one step
    view
    |> element("#flows-edit-editor")
    |> render_hook("form_flow:graph_changed", %{
      "nodes" => [
        %{
          "id" => "1",
          "type" => "step",
          "position" => %{"x" => 0, "y" => 0},
          "data" => %{"label" => "Renamed step"}
        }
      ],
      "edges" => []
    })

    view |> element("button", "Save") |> render_click()
    assert_redirect(view, "/flows/#{id}")

    graph = Graphs.get(id)
    assert [node] = graph.nodes
    assert node.properties["data"]["label"] == "Renamed step"
    assert graph.relationships == []
  end

  test "saving the edit page unchanged keeps the same records", %{conn: conn} do
    id = create_flow(conn)
    %{nodes: nodes_before} = Graphs.get(id)

    {:ok, view, _html} = live(conn, "/flows/#{id}/edit")
    view |> element("button", "Save") |> render_click()
    assert_redirect(view, "/flows/#{id}")

    %{nodes: nodes_after} = Graphs.get(id)

    assert Enum.sort(Enum.map(nodes_after, & &1.id)) ==
             Enum.sort(Enum.map(nodes_before, & &1.id))
  end

  test "deleting a flow from the show page removes it", %{conn: conn} do
    id = create_flow(conn)

    {:ok, view, _html} = live(conn, "/flows/#{id}")

    view |> element("button", "Delete") |> render_click()
    assert_redirect(view, "/flows")

    assert Graphs.get(id) == nil
  end

  test "show and edit handle a flow that does not exist", %{conn: conn} do
    for path <- ["/flows/#{Ecto.UUID.generate()}", "/flows/not-a-uuid/edit"] do
      {:ok, _view, html} = live(conn, path)

      assert html =~ "Flow not found"
    end
  end

  # Creates a flow the way a user would: saving the new page's starter graph
  defp create_flow(conn) do
    {:ok, view, _html} = live(conn, "/flows/new")

    view |> element("button", "Save") |> render_click()

    {"/flows/" <> id, _flash} = assert_redirect(view)

    id
  end
end
