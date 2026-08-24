defmodule Demo.FormFlowFlowsCrudTest do
  @moduledoc """
  Drives the flows CRUD pages end-to-end through the dedicated
  `live "/flows/*path", FlowsLive` route: `/flows/new` chooses a flavor and
  creates a seeded graph, `/flows/:id/edit` is the canvas, `/flows/:id` shows
  it read-only, subflows drill in at `/flows/:root/nodes/:node_id`, and
  delete removes everything a flow owns.

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

  test "the new page asks the flavor up front and creates a seeded flow", %{conn: conn} do
    {:ok, view, html} = live(conn, "/flows/new")

    assert html =~ "New flow"
    assert html =~ "A single flow with one or more forms"
    assert html =~ "A complex flow with one or more subflows"

    view
    |> element("form")
    |> render_submit(%{"name" => "Enrollment", "label" => "forms"})

    {path, _flash} = assert_redirect(view)
    assert "/flows/" <> rest = path
    assert [id, "edit"] = String.split(rest, "/")

    graph = Graphs.get(id)
    assert graph.name == "Enrollment"
    assert graph.label == "forms"

    # The universal starter: a pinned Start and End, nothing else
    assert graph.nodes |> Enum.map(&get_in(&1.properties, ["data", "label"])) |> Enum.sort() ==
             ["End", "Start"]

    assert Enum.all?(graph.nodes, &(&1.properties["deletable"] == false))
    assert graph.relationships == []
  end

  test "the index starts empty and lists flows with names, kinds, and actions", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/flows")
    assert html =~ "No flows yet"

    id = create_flow(conn, "Enrollment", "subflows")

    {:ok, view, html} = live(conn, "/flows")

    assert html =~ "Enrollment"
    assert html =~ "Complex"
    assert has_element?(view, "a", "New flow")
    assert has_element?(view, ~s(a[href="/flows/#{id}"]), "Show")
    assert has_element?(view, ~s(a[href="/flows/#{id}/edit"]), "Edit")
  end

  test "editing a flow replaces its contents", %{conn: conn} do
    id = create_flow(conn)

    {:ok, view, html} = live(conn, "/flows/#{id}/edit")
    assert html =~ "Simple flow"

    view
    |> element("#flows-edit-editor")
    |> render_hook("form_flow:graph_changed", %{
      "nodes" => [
        %{
          "id" => "1",
          "type" => "step",
          "position" => %{"x" => 0, "y" => 0},
          "data" => %{"label" => "Renamed step", "kind" => "form"}
        }
      ],
      "edges" => []
    })

    view |> element("button", "Save") |> render_click()
    assert_redirect(view, "/flows/#{id}")

    graph = Graphs.get(id)
    assert [node] = graph.nodes
    assert node.properties["data"]["label"] == "Renamed step"
  end

  test "renaming from the edit header persists", %{conn: conn} do
    id = create_flow(conn)

    {:ok, view, _html} = live(conn, "/flows/#{id}/edit")

    view |> element(~s(input[phx-blur="rename"])) |> render_blur(%{"value" => "Better name"})

    assert Graphs.get(id).name == "Better name"
  end

  test "the show canvas is read-only; the edit canvas is not", %{conn: conn} do
    id = create_flow(conn)

    {:ok, view, _html} = live(conn, "/flows/#{id}")
    assert view |> element("#flows-show-editor") |> render() =~ ~s(data-editable="false")

    {:ok, view, _html} = live(conn, "/flows/#{id}/edit")
    assert view |> element("#flows-edit-editor") |> render() =~ ~s(data-editable="true")
  end

  test "saving a complex flow creates subflow children; drill-in shows them", %{conn: conn} do
    root_id = create_flow(conn, "Onboarding", "subflows")

    {:ok, view, _html} = live(conn, "/flows/#{root_id}/edit")

    view
    |> element("#flows-edit-editor")
    |> render_hook("form_flow:graph_changed", %{
      "nodes" => [
        %{
          "id" => "1",
          "type" => "subflow",
          "position" => %{"x" => 0, "y" => 0},
          "data" => %{"label" => "Collect address", "subflow_label" => "forms"}
        }
      ],
      "edges" => []
    })

    view |> element("button", "Save") |> render_click()
    assert_redirect(view, "/flows/#{root_id}")

    assert [node] = Graphs.get(root_id).nodes
    child = Graphs.get(node.subflow_id)
    assert child.name == "Collect address"
    assert child.label == "forms"
    assert child.owner_graph_id == root_id

    # Drill-in show: breadcrumb back to the root, read-only child canvas
    {:ok, view, html} = live(conn, "/flows/#{root_id}/nodes/#{node.id}")

    assert html =~ "Onboarding"
    assert html =~ "Collect address"
    assert has_element?(view, ~s(a[href="/flows/#{root_id}"]), "Onboarding")
    assert view |> element("#flows-show-editor") |> render() =~ ~s(data-editable="false")

    # Drill-in edit works on the same node URL, with a breadcrumb that stays
    # in edit mode — backing out lands on the parent's editor
    {:ok, view, html} = live(conn, "/flows/#{root_id}/nodes/#{node.id}/edit")
    assert html =~ "Collect address"
    assert has_element?(view, ~s(a[href="/flows/#{root_id}/edit"]), "Onboarding")
    assert has_element?(view, ~s(a[href="/flows"]), "Flows")
  end

  test "the index lists roots but not their owned subflow children", %{conn: conn} do
    root_id = create_flow(conn, "Onboarding", "subflows")
    save_subflow_node(conn, root_id)

    {:ok, view, html} = live(conn, "/flows")

    assert html =~ "Onboarding"
    refute html =~ "Subflow 1"
    assert view |> render() |> String.split("<tr") |> length() == 3
  end

  test "deleting a subflow another flow still uses is refused with an explanation", %{conn: conn} do
    root_id = create_flow(conn, "Onboarding", "subflows")
    save_subflow_node(conn, root_id)
    [node] = Graphs.get(root_id).nodes

    # Visiting the owned child directly and trying to delete it
    {:ok, view, _html} = live(conn, "/flows/#{node.subflow_id}")

    view |> element("button", "Delete") |> render_click()

    assert render(view) =~ "another flow still uses it as a subflow"
    assert Graphs.get(node.subflow_id) != nil
  end

  test "opening a subflow node navigates by node id", %{conn: conn} do
    root_id = create_flow(conn, "Onboarding", "subflows")
    save_subflow_node(conn, root_id)

    [node] = Graphs.get(root_id).nodes

    {:ok, view, _html} = live(conn, "/flows/#{root_id}")

    view
    |> element("#flows-show-editor")
    |> render_hook("form_flow:open_subflow", %{"node_id" => node.id})

    assert_redirect(view, "/flows/#{root_id}/nodes/#{node.id}")
  end

  test "opening an unsaved subflow node explains instead of crashing", %{conn: conn} do
    root_id = create_flow(conn, "Onboarding", "subflows")

    {:ok, view, _html} = live(conn, "/flows/#{root_id}/edit")

    view
    |> element("#flows-edit-editor")
    |> render_hook("form_flow:open_subflow", %{"node_id" => "3"})

    assert render(view) =~ "Save the flow before opening a new subflow."
  end

  test "deleting a flow from the show page removes it and its children", %{conn: conn} do
    root_id = create_flow(conn, "Onboarding", "subflows")
    save_subflow_node(conn, root_id)
    [node] = Graphs.get(root_id).nodes

    {:ok, view, _html} = live(conn, "/flows/#{root_id}")

    view |> element("button", "Delete") |> render_click()
    assert_redirect(view, "/flows")

    assert Graphs.get(root_id) == nil
    assert Graphs.get(node.subflow_id) == nil
  end

  test "show and edit handle a flow that does not exist", %{conn: conn} do
    for path <- [
          "/flows/#{Ecto.UUID.generate()}",
          "/flows/not-a-uuid/edit",
          "/flows/#{Ecto.UUID.generate()}/nodes/#{Ecto.UUID.generate()}"
        ] do
      {:ok, _view, html} = live(conn, path)

      assert html =~ "Flow not found"
    end
  end

  # Creates a flow the way a user would: through the new page's chooser
  defp create_flow(conn, name \\ "Untitled flow", label \\ "forms") do
    {:ok, view, _html} = live(conn, "/flows/new")

    view |> element("form") |> render_submit(%{"name" => name, "label" => label})

    {path, _flash} = assert_redirect(view)
    ["", "flows", id, "edit"] = String.split(path, "/")

    id
  end

  # Adds one subflow node to a complex flow and saves, creating its child
  defp save_subflow_node(conn, root_id) do
    {:ok, view, _html} = live(conn, "/flows/#{root_id}/edit")

    view
    |> element("#flows-edit-editor")
    |> render_hook("form_flow:graph_changed", %{
      "nodes" => [
        %{
          "id" => "1",
          "type" => "subflow",
          "position" => %{"x" => 0, "y" => 0},
          "data" => %{"label" => "Subflow 1", "subflow_label" => "forms"}
        }
      ],
      "edges" => []
    })

    view |> element("button", "Save") |> render_click()
    assert_redirect(view)
  end
end
