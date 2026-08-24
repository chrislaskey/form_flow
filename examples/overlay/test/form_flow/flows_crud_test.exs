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

    # Edit mode is sticky: no redirect, a Saved notice, and the canvas is
    # re-synced with persisted UUIDs in place of the editor's temporary ids
    assert render(view) =~ "Saved."
    assert_push_event(view, "form_flow:set_graph", %{graph: %{nodes: [pushed]}})
    assert {:ok, _} = Ecto.UUID.cast(pushed["id"])

    graph = Graphs.get(id)
    assert [node] = graph.nodes
    assert node.properties["data"]["label"] == "Renamed step"

    # The notice clears on the next edit
    view
    |> element("#flows-edit-editor")
    |> render_hook("form_flow:graph_changed", %{"nodes" => [], "edges" => []})

    refute render(view) =~ "Saved."
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
    assert render(view) =~ "Saved."

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
    # in edit mode — backing out lands on the parent's editor. Edit-page
    # breadcrumbs are buttons, not plain links, so unsaved changes can gate
    # them the same way Open is gated.
    {:ok, view, html} = live(conn, "/flows/#{root_id}/nodes/#{node.id}/edit")
    assert html =~ "Collect address"
    assert has_element?(view, "button", "Onboarding")
    assert has_element?(view, "button", "Flows")
  end

  test "the index lists roots but not their owned subflow children", %{conn: conn} do
    root_id = create_flow(conn, "Onboarding", "subflows")
    save_subflow_node(conn, root_id)

    {:ok, view, html} = live(conn, "/flows")

    assert html =~ "Onboarding"
    refute html =~ "Subflow 1"
    assert view |> render() |> String.split("<tr") |> length() == 3
  end

  test "the index name links to the show page", %{conn: conn} do
    id = create_flow(conn, "Enrollment")

    {:ok, view, _html} = live(conn, "/flows")

    assert view |> element(~s(td a[href="/flows/#{id}"]), "Enrollment") |> has_element?()
  end

  test "deleting from a drill-in page removes the step and returns to the parent's editor", %{
    conn: conn
  } do
    root_id = create_flow(conn, "Onboarding", "subflows")
    save_subflow_node(conn, root_id)
    [node] = Graphs.get(root_id).nodes

    {:ok, view, _html} = live(conn, "/flows/#{root_id}/nodes/#{node.id}")

    view |> element("button", "Delete") |> render_click()
    assert_redirect(view, "/flows/#{root_id}/edit")

    assert Graphs.get(root_id).nodes == []
    assert Graphs.get(node.subflow_id) == nil
  end

  test "deleting two levels deep returns to the containing subflow's editor", %{conn: conn} do
    {:ok, root} = Graphs.create(%{name: "Root", label: "subflows"})

    {:ok, _} =
      Graphs.update(root, %{
        nodes: [
          %{
            properties: %{
              "type" => "subflow",
              "data" => %{"label" => "Middle", "subflow_label" => "subflows"}
            }
          }
        ],
        relationships: []
      })

    [x] = Graphs.get(root.id).nodes
    middle = Graphs.get(x.subflow_id)

    {:ok, _} =
      Graphs.update(middle, %{
        nodes: [
          %{
            properties: %{
              "type" => "subflow",
              "data" => %{"label" => "Leaf", "subflow_label" => "forms"}
            }
          }
        ],
        relationships: []
      })

    [y] = Enum.filter(Graphs.get(middle.id).nodes, &(&1.properties["type"] == "subflow"))

    # The page shows Leaf; deleting removes node y from Middle, so the
    # destination is Middle's editor — addressed by the node embedding Middle
    {:ok, view, _html} = live(conn, "/flows/#{root.id}/nodes/#{y.id}")

    view |> element("button", "Delete") |> render_click()
    assert_redirect(view, "/flows/#{root.id}/nodes/#{x.id}/edit")

    assert Graphs.get(y.subflow_id) == nil
    assert Graphs.get(middle.id) != nil
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

  test "opening a subflow node the canvas never reported prompts instead of crashing",
       %{conn: conn} do
    root_id = create_flow(conn, "Onboarding", "subflows")

    {:ok, view, _html} = live(conn, "/flows/#{root_id}/edit")

    view
    |> element("#flows-edit-editor")
    |> render_hook("form_flow:open_subflow", %{"node_id" => "3"})

    assert render(view) =~ "unsaved changes"
  end

  test "opening a brand-new subflow node saves it and navigates to the node it became",
       %{conn: conn} do
    root_id = create_flow(conn, "Onboarding", "subflows")

    {:ok, view, _html} = live(conn, "/flows/#{root_id}/edit")

    # Added but never saved — Graphs.get_node/1 can't find it under its
    # editor-temporary id yet
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

    view
    |> element("#flows-edit-editor")
    |> render_hook("form_flow:open_subflow", %{"node_id" => "1"})

    assert render(view) =~ "unsaved changes"

    view |> element("button", "Save & Continue") |> render_click()

    [node] = Graphs.get(root_id).nodes
    assert {:ok, _} = Ecto.UUID.cast(node.id)
    assert node.subflow_id != nil

    # Not just "back to the root" — the specific node the temp id resolved to
    assert_redirect(view, "/flows/#{root_id}/nodes/#{node.id}/edit")
  end

  test "opening a subflow from the edit canvas navigates directly when nothing changed since save",
       %{conn: conn} do
    root_id = create_flow(conn, "Onboarding", "subflows")
    save_subflow_node(conn, root_id)
    [node] = Graphs.get(root_id).nodes

    {:ok, view, _html} = live(conn, "/flows/#{root_id}/edit")

    view
    |> element("#flows-edit-editor")
    |> render_hook("form_flow:open_subflow", %{"node_id" => node.id})

    assert_redirect(view, "/flows/#{root_id}/nodes/#{node.id}/edit")
  end

  test "opening a subflow from the edit canvas with unsaved changes prompts instead of navigating",
       %{conn: conn} do
    root_id = create_flow(conn, "Onboarding", "subflows")
    save_subflow_node(conn, root_id)
    [node] = Graphs.get(root_id).nodes

    {:ok, view, _html} = live(conn, "/flows/#{root_id}/edit")

    move_subflow_node(view, node.id)

    view
    |> element("#flows-edit-editor")
    |> render_hook("form_flow:open_subflow", %{"node_id" => node.id})

    # Still on the edit page — no redirect fired — with the prompt showing
    assert render(view) =~ "unsaved changes"
    assert has_element?(view, "button", "Save & Continue")
  end

  test "confirming the unsaved-changes prompt saves before navigating", %{conn: conn} do
    root_id = create_flow(conn, "Onboarding", "subflows")
    save_subflow_node(conn, root_id)
    [node] = Graphs.get(root_id).nodes

    {:ok, view, _html} = live(conn, "/flows/#{root_id}/edit")

    move_subflow_node(view, node.id)

    view
    |> element("#flows-edit-editor")
    |> render_hook("form_flow:open_subflow", %{"node_id" => node.id})

    view |> element("button", "Save & Continue") |> render_click()

    assert_redirect(view, "/flows/#{root_id}/nodes/#{node.id}/edit")

    [saved_node] = Graphs.get(root_id).nodes
    assert saved_node.properties["position"] == %{"x" => 40, "y" => 40}
  end

  test "cancelling the unsaved-changes prompt keeps editing without discarding changes",
       %{conn: conn} do
    root_id = create_flow(conn, "Onboarding", "subflows")
    save_subflow_node(conn, root_id)
    [node] = Graphs.get(root_id).nodes

    {:ok, view, _html} = live(conn, "/flows/#{root_id}/edit")

    move_subflow_node(view, node.id)

    view
    |> element("#flows-edit-editor")
    |> render_hook("form_flow:open_subflow", %{"node_id" => node.id})

    view |> element("button", "Keep editing") |> render_click()

    refute render(view) =~ "unsaved changes"

    # Nothing was persisted, and nothing navigated away
    [unmoved_node] = Graphs.get(root_id).nodes
    assert unmoved_node.properties["position"] == %{"x" => 0, "y" => 0}

    # The pending edit is still live on the canvas and can still be saved
    view |> element("button", "Save") |> render_click()
    assert render(view) =~ "Saved."

    [saved_node] = Graphs.get(root_id).nodes
    assert saved_node.properties["position"] == %{"x" => 40, "y" => 40}
  end

  test "show navigates directly to the show page when nothing changed since save",
       %{conn: conn} do
    id = create_flow(conn)

    {:ok, view, _html} = live(conn, "/flows/#{id}/edit")

    view |> element("button", "Show") |> render_click()

    assert_redirect(view, "/flows/#{id}")
  end

  test "show with unsaved changes prompts to save before leaving", %{conn: conn} do
    id = create_flow(conn)

    {:ok, view, _html} = live(conn, "/flows/#{id}/edit")

    edit_step(view)

    view |> element("button", "Show") |> render_click()

    # Still on the edit page — no redirect fired — with the prompt showing
    assert render(view) =~ "unsaved changes"

    view |> element("button", "Save & Continue") |> render_click()

    assert_redirect(view, "/flows/#{id}")

    assert [node] = Graphs.get(id).nodes
    assert node.properties["data"]["label"] == "Renamed step"
  end

  test "the unsaved-guard flag tracks unsaved changes for the beforeunload hook",
       %{conn: conn} do
    id = create_flow(conn)

    {:ok, view, html} = live(conn, "/flows/#{id}/edit")
    assert html =~ ~s(id="flows-edit-unsaved-guard")
    assert has_element?(view, ~s(#flows-edit-unsaved-guard[data-unsaved="false"]))

    edit_step(view)

    assert has_element?(view, ~s(#flows-edit-unsaved-guard[data-unsaved="true"]))

    view |> element("button", "Save") |> render_click()

    assert has_element?(view, ~s(#flows-edit-unsaved-guard[data-unsaved="false"]))
  end

  test "discard changes is hidden when the canvas is clean", %{conn: conn} do
    id = create_flow(conn)

    {:ok, view, _html} = live(conn, "/flows/#{id}/edit")

    refute has_element?(view, "button", "Discard changes")
  end

  test "discarding changes reloads the edit page and drops the unsaved edit", %{conn: conn} do
    id = create_flow(conn)

    {:ok, view, _html} = live(conn, "/flows/#{id}/edit")

    edit_step(view)

    assert has_element?(view, "button", "Discard changes")

    # Selected by phx-click, not text: the modal's confirm button also reads
    # "Discard", a substring of the trigger's "Discard changes"
    view |> element(~s(button[phx-click="request_discard"])) |> render_click()

    assert render(view) =~ "Discard changes?"

    view |> element(~s(button[phx-click="confirm_discard"])) |> render_click()

    assert_redirect(view, "/flows/#{id}/edit")

    # Nothing was persisted — the edit never went through save
    assert length(Graphs.get(id).nodes) == 2
  end

  test "cancelling the discard prompt keeps the unsaved edit live", %{conn: conn} do
    id = create_flow(conn)

    {:ok, view, _html} = live(conn, "/flows/#{id}/edit")

    edit_step(view)

    view |> element(~s(button[phx-click="request_discard"])) |> render_click()
    view |> element(~s(button[phx-click="cancel_discard"])) |> render_click()

    refute render(view) =~ "Discard changes?"

    # The pending edit is still live on the canvas and can still be saved
    view |> element("button", "Save") |> render_click()
    assert render(view) =~ "Saved."

    assert [node] = Graphs.get(id).nodes
    assert node.properties["data"]["label"] == "Renamed step"
  end

  test "a breadcrumb navigates directly when nothing changed since save", %{conn: conn} do
    id = create_flow(conn)

    {:ok, view, _html} = live(conn, "/flows/#{id}/edit")

    view |> element("button", "Flows") |> render_click()

    assert_redirect(view, "/flows")
  end

  test "a breadcrumb with unsaved changes prompts to save before leaving", %{conn: conn} do
    id = create_flow(conn)

    {:ok, view, _html} = live(conn, "/flows/#{id}/edit")

    edit_step(view)

    view |> element("button", "Flows") |> render_click()

    # Still on the edit page — no redirect fired — with the prompt showing
    assert render(view) =~ "unsaved changes"

    view |> element("button", "Save & Continue") |> render_click()

    assert_redirect(view, "/flows")

    assert [node] = Graphs.get(id).nodes
    assert node.properties["data"]["label"] == "Renamed step"
  end

  test "keep editing on a leave prompt discards nothing and stays on the canvas",
       %{conn: conn} do
    id = create_flow(conn)

    {:ok, view, _html} = live(conn, "/flows/#{id}/edit")

    edit_step(view)

    view |> element("button", "Flows") |> render_click()
    view |> element("button", "Keep editing") |> render_click()

    refute render(view) =~ "unsaved changes"

    # Nothing was persisted, and nothing navigated away
    assert length(Graphs.get(id).nodes) == 2

    # The pending edit is still live on the canvas and can still be saved
    view |> element("button", "Save") |> render_click()
    assert render(view) =~ "Saved."

    assert [node] = Graphs.get(id).nodes
    assert node.properties["data"]["label"] == "Renamed step"
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
  end

  # Reports a moved node without saving — the canvas ends up with unsaved
  # changes relative to whatever was last persisted
  defp move_subflow_node(view, node_id) do
    view
    |> element("#flows-edit-editor")
    |> render_hook("form_flow:graph_changed", %{
      "nodes" => [
        %{
          "id" => node_id,
          "type" => "subflow",
          "position" => %{"x" => 40, "y" => 40},
          "data" => %{"label" => "Subflow 1", "subflow_label" => "forms"}
        }
      ],
      "edges" => []
    })
  end

  # Reports a "forms" flow's starter nodes collapsed down to one renamed step
  # — an unsaved change relative to whatever was last persisted
  defp edit_step(view) do
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
  end
end
