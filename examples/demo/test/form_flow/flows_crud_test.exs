defmodule Demo.FormFlowFlowsCrudTest do
  @moduledoc """
  Drives the flows CRUD pages end-to-end through the dedicated
  `live "/admin/*path", FormFlowLive.Admin` route (mounted with `base="/admin"`):
  `/admin/flows/new` chooses a flavor and creates a seeded flow,
  `/admin/flows/:id/edit` is the canvas, `/admin/flows/:id` shows it
  read-only, subflows drill in at `/admin/flows/:root/nodes/:node_id`, and
  delete removes everything a flow owns.

  The editor's React side can't run here — LiveViewTest has no JavaScript
  engine — so edits are driven by pushing the events the hook would push.
  """

  use DemoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias FormFlow.Data.Templates.Flows
  alias FormFlow.Data.Templates.Forms

  test "every flows path renders on the dedicated page", %{conn: conn} do
    for path <- ["/admin/flows", "/admin/flows/new"] do
      {:ok, view, html} = live(conn, path)

      assert html =~ "Flows"
      assert has_element?(view, "#admin-pages")
    end
  end

  test "the new page asks the flavor up front and creates a seeded flow", %{conn: conn} do
    {:ok, view, html} = live(conn, "/admin/flows/new")

    assert html =~ "New flow"
    assert html =~ "A single flow with one or more forms"
    assert html =~ "A complex flow with one or more subflows"

    view
    |> element("form")
    |> render_submit(%{"name" => "Enrollment", "label" => "forms"})

    {path, _flash} = assert_redirect(view)
    assert "/admin/flows/" <> rest = path
    assert [id, "edit"] = String.split(rest, "/")

    flow = Flows.get(id)
    assert flow.name == "Enrollment"
    assert flow.label == "forms"

    # The universal starter: a pinned Start and End, nothing else
    assert flow.nodes |> Enum.map(&get_in(&1.properties, ["data", "label"])) |> Enum.sort() ==
             ["End", "Start"]

    assert Enum.all?(flow.nodes, &(&1.properties["deletable"] == false))
    assert flow.relationships == []
  end

  test "the index starts empty and lists flows with names, kinds, and actions", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/admin/flows")
    assert html =~ "No flows yet"

    id = create_flow(conn, "Enrollment", "subflows")

    {:ok, view, html} = live(conn, "/admin/flows")

    assert html =~ "Enrollment"
    assert html =~ "Complex"
    assert has_element?(view, "a", "New flow")
    assert has_element?(view, ~s(a[href="/admin/flows/#{id}"]), "Show")
    assert has_element?(view, ~s(a[href="/admin/flows/#{id}/edit"]), "Edit")
  end

  test "editing a flow replaces its contents", %{conn: conn} do
    id = create_flow(conn)

    {:ok, view, html} = live(conn, "/admin/flows/#{id}/edit")
    assert html =~ "Simple flow"

    view
    |> element("#flows-edit-editor")
    |> render_hook("form_flow:flow_changed", %{
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
    assert_push_event(view, "form_flow:set_flow", %{flow: %{nodes: [pushed]}})
    assert {:ok, _} = Ecto.UUID.cast(pushed["id"])

    flow = Flows.get(id)
    assert [node] = flow.nodes
    assert node.properties["data"]["label"] == "Renamed step"

    # The notice clears on the next edit
    view
    |> element("#flows-edit-editor")
    |> render_hook("form_flow:flow_changed", %{"nodes" => [], "edges" => []})

    refute render(view) =~ "Saved."
  end

  test "the new page generates a slug, or keeps the one typed", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/admin/flows/new")

    view
    |> element("form")
    |> render_submit(%{"name" => "Dog License Application 2026", "label" => "forms"})

    {path, _flash} = assert_redirect(view)
    assert "/admin/flows/" <> rest = path
    [id, "edit"] = String.split(rest, "/")
    assert Flows.get(id).slug == "dla2026"

    {:ok, view, _html} = live(conn, "/admin/flows/new")

    view
    |> element("form")
    |> render_submit(%{"name" => "Anything", "label" => "forms", "slug" => "Chosen"})

    {path, _flash} = assert_redirect(view)
    assert "/admin/flows/" <> rest = path
    [id, "edit"] = String.split(rest, "/")
    assert Flows.get(id).slug == "chosen"
  end

  test "the slug is edited from the edit header and saved with the rest", %{conn: conn} do
    id = create_flow(conn, "Dog License Application 2026")
    assert Flows.get(id).slug == "dla2026"

    {:ok, view, html} = live(conn, "/admin/flows/#{id}/edit")
    assert html =~ "dla2026"

    view
    |> element("#flows-edit-flow-form-form")
    |> render_change(%{"dynamic_form" => %{"slug" => "dla2027"}})

    assert Flows.get(id).slug == "dla2026"
    assert has_element?(view, "button", "Discard changes")

    view |> element("button", "Save") |> render_click()

    assert Flows.get(id).slug == "dla2027"
    refute has_element?(view, "button", "Discard changes")
  end

  test "a taken slug is a refused save that names the field", %{conn: conn} do
    {:ok, _other} = Flows.create(%{name: "Other", slug: "taken"})
    id = create_flow(conn, "Mine")

    {:ok, view, _html} = live(conn, "/admin/flows/#{id}/edit")

    view
    |> element("#flows-edit-flow-form-form")
    |> render_change(%{"dynamic_form" => %{"slug" => "taken"}})

    view |> element("button", "Save") |> render_click()

    assert render(view) =~ "The slug has already been taken."
    assert Flows.get(id).slug == "mine"
  end

  test "renaming from the edit header persists", %{conn: conn} do
    id = create_flow(conn)

    {:ok, view, _html} = live(conn, "/admin/flows/#{id}/edit")

    view
    |> element("#flows-edit-flow-form-form")
    |> render_change(%{"dynamic_form" => %{"name" => "Better name"}})

    # Nothing persists until Save — a pending name is an unsaved change,
    # riding the same guard as canvas edits
    assert Flows.get(id).name != "Better name"
    assert has_element?(view, "button", "Discard changes")

    view |> element("button", "Save") |> render_click()

    assert Flows.get(id).name == "Better name"
    refute has_element?(view, "button", "Discard changes")
  end

  test "picking a form_flow_type persists it into the flow's properties", %{conn: conn} do
    id = create_flow(conn)

    {:ok, view, html} = live(conn, "/admin/flows/#{id}/edit")

    # The dropdown carries the FormFlow.Config defaults plus the option the
    # demo's Config adds — proof the router's config attr reaches the
    # page
    assert html =~ "Form flow type"
    assert html =~ "Wizard (any order)"
    assert html =~ "Wizard (in order)"
    assert html =~ "Demo checklist"

    view
    |> element("#flows-edit-flow-form-form")
    |> render_change(%{"dynamic_form" => %{"form_flow_type" => "wizard_any_order"}})

    # Nothing persists until Save — a pending type is an unsaved change
    assert Flows.get(id).properties == %{"slug" => "untitledfl"}
    assert has_element?(view, "button", "Discard changes")

    view |> element("button", "Save") |> render_click()

    assert Flows.get(id).properties == %{
             "form_flow_type" => "wizard_any_order",
             "slug" => "untitledfl"
           }

    refute has_element?(view, "button", "Discard changes")

    # Show mode renders the stored type as a string, not a dropdown
    {:ok, _view, html} = live(conn, "/admin/flows/#{id}")
    assert html =~ "Wizard (any order)"

    # Picking "default" again removes the key rather than pinning a value
    {:ok, view, _html} = live(conn, "/admin/flows/#{id}/edit")

    view
    |> element("#flows-edit-flow-form-form")
    |> render_change(%{"dynamic_form" => %{"form_flow_type" => ""}})

    view |> element("button", "Save") |> render_click()

    assert Flows.get(id).properties == %{"slug" => "untitledfl"}
  end

  test "a complex flow has no type dropdown of its own", %{conn: conn} do
    id = create_flow(conn, "Onboarding", "subflows")

    {:ok, _view, html} = live(conn, "/admin/flows/#{id}/edit")

    refute html =~ "Form flow type"
  end

  test "a form node's form_type writes through to the collected form", %{conn: conn} do
    id = create_flow(conn, "Application", "forms")
    save_form_node(conn, id)
    [node] = Flows.get(id).nodes

    {:ok, view, _html} = live(conn, "/admin/flows/#{id}/edit")

    view
    |> element("#flows-edit-editor")
    |> render_hook("form_flow:flow_changed", %{
      "nodes" => [form_node_attrs(node, %{"form_type" => "review"})],
      "edges" => []
    })

    view |> element("button", "Save") |> render_click()
    assert render(view) =~ "Saved."

    # One stored copy — the form lineage's properties; the node keeps none
    [saved_node] = Flows.get(id).nodes

    assert Forms.get(node.form_id).properties == %{
             "form_type" => "review",
             "slug" => "applicatio_intake"
           }

    refute Map.has_key?(saved_node.properties["data"], "form_type")

    # Loading projects the stored type back into the node's data, so the
    # canvas dropdown (and show mode's label) reflect it
    {:ok, view, _html} = live(conn, "/admin/flows/#{id}")
    assert view |> element("#flows-show-editor") |> render() =~ "review"

    # The canvas offers the configured form types, the library's and the
    # demo's — and a node reported without a type clears it, which is what an
    # unset type is resolved from anyway
    {:ok, view, html} = live(conn, "/admin/flows/#{id}/edit")
    assert html =~ "Demo prefill"

    view
    |> element("#flows-edit-editor")
    |> render_hook("form_flow:flow_changed", %{
      "nodes" => [form_node_attrs(node, %{})],
      "edges" => []
    })

    view |> element("button", "Save") |> render_click()
    assert Forms.get(node.form_id).properties == %{"slug" => "applicatio_intake"}
  end

  test "a subflow node's form_flow_type writes through to the embedded flow", %{conn: conn} do
    root_id = create_flow(conn, "Onboarding", "subflows")
    save_subflow_node(conn, root_id)
    [node] = Flows.get(root_id).nodes

    {:ok, view, _html} = live(conn, "/admin/flows/#{root_id}/edit")

    view
    |> element("#flows-edit-editor")
    |> render_hook("form_flow:flow_changed", %{
      "nodes" => [subflow_node_attrs(node, %{"form_flow_type" => "wizard_any_order"})],
      "edges" => []
    })

    view |> element("button", "Save") |> render_click()
    assert render(view) =~ "Saved."

    # One stored copy — the embedded flow's properties; the node keeps none
    [saved_node] = Flows.get(root_id).nodes

    assert Flows.get(node.subflow_id).properties == %{
             "form_flow_type" => "wizard_any_order",
             "slug" => "onboarding_subflow1"
           }

    refute Map.has_key?(saved_node.properties["data"], "form_flow_type")

    # Loading projects the stored type back into the node's data, so the
    # canvas dropdown (and show mode's string) reflect it
    {:ok, view, _html} = live(conn, "/admin/flows/#{root_id}")
    assert view |> element("#flows-show-editor") |> render() =~ "wizard_any_order"

    # ...and the embedded flow's own pages read the same value
    {:ok, _view, html} = live(conn, "/admin/flows/#{root_id}/nodes/#{node.id}")
    assert html =~ "Wizard (any order)"

    # Picking "default" on the canvas clears the child's property
    {:ok, view, _html} = live(conn, "/admin/flows/#{root_id}/edit")

    view
    |> element("#flows-edit-editor")
    |> render_hook("form_flow:flow_changed", %{
      "nodes" => [subflow_node_attrs(node, %{})],
      "edges" => []
    })

    view |> element("button", "Save") |> render_click()

    assert Flows.get(node.subflow_id).properties == %{"slug" => "onboarding_subflow1"}
  end

  test "renaming a subflow node on the canvas renames the embedded flow", %{conn: conn} do
    root_id = create_flow(conn, "Onboarding", "subflows")
    save_subflow_node(conn, root_id)
    [node] = Flows.get(root_id).nodes
    assert Flows.get(node.subflow_id).name == "Subflow 1"

    {:ok, view, _html} = live(conn, "/admin/flows/#{root_id}/edit")

    view
    |> element("#flows-edit-editor")
    |> render_hook("form_flow:flow_changed", %{
      "nodes" => [subflow_node_attrs(node, %{"label" => "Collect documents"})],
      "edges" => []
    })

    view |> element("button", "Save") |> render_click()
    assert render(view) =~ "Saved."

    # The rename reached the entity the node embeds — the same name its own
    # pages edit — and loading projects it back into the node's title
    assert Flows.get(node.subflow_id).name == "Collect documents"

    {:ok, _view, html} = live(conn, "/admin/flows/#{root_id}/nodes/#{node.id}")
    assert html =~ "Collect documents"
  end

  test "renaming a form step on the canvas renames its form", %{conn: conn} do
    id = create_flow(conn)

    {:ok, view, _html} = live(conn, "/admin/flows/#{id}/edit")

    # First save creates the owned form, named from the canvas label
    edit_step(view)
    view |> element("button", "Save") |> render_click()

    [node] = Flows.get(id).nodes
    assert Forms.get(node.form_id).name == "Renamed step"

    # Second save renames the existing form through the node's label
    view
    |> element("#flows-edit-editor")
    |> render_hook("form_flow:flow_changed", %{
      "nodes" => [
        %{
          "id" => node.id,
          "type" => "step",
          "form_id" => node.form_id,
          "position" => %{"x" => 0, "y" => 0},
          "data" => %{"label" => "W-2 Details", "kind" => "form"}
        }
      ],
      "edges" => []
    })

    view |> element("button", "Save") |> render_click()
    assert render(view) =~ "Saved."

    assert Forms.get(node.form_id).name == "W-2 Details"
  end

  test "the show canvas is read-only; the edit canvas is not", %{conn: conn} do
    id = create_flow(conn)

    {:ok, view, _html} = live(conn, "/admin/flows/#{id}")
    assert view |> element("#flows-show-editor") |> render() =~ ~s(data-editable="false")

    {:ok, view, _html} = live(conn, "/admin/flows/#{id}/edit")
    assert view |> element("#flows-edit-editor") |> render() =~ ~s(data-editable="true")
  end

  test "saving a complex flow creates subflow children; drill-in shows them", %{conn: conn} do
    root_id = create_flow(conn, "Onboarding", "subflows")

    {:ok, view, _html} = live(conn, "/admin/flows/#{root_id}/edit")

    view
    |> element("#flows-edit-editor")
    |> render_hook("form_flow:flow_changed", %{
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

    assert [node] = Flows.get(root_id).nodes
    child = Flows.get(node.subflow_id)
    assert child.name == "Collect address"
    assert child.label == "forms"
    assert child.owner_flow_id == root_id

    # Drill-in show: breadcrumb back to the root, read-only child canvas
    {:ok, view, html} = live(conn, "/admin/flows/#{root_id}/nodes/#{node.id}")

    assert html =~ "Onboarding"
    assert html =~ "Collect address"
    assert has_element?(view, ~s(a[href="/admin/flows/#{root_id}"]), "Onboarding")
    assert view |> element("#flows-show-editor") |> render() =~ ~s(data-editable="false")

    # Drill-in edit works on the same node URL, with a breadcrumb that stays
    # in edit mode — backing out lands on the parent's editor. Edit-page
    # breadcrumbs are buttons, not plain links, so unsaved changes can gate
    # them the same way Open is gated.
    {:ok, view, html} = live(conn, "/admin/flows/#{root_id}/nodes/#{node.id}/edit")
    assert html =~ "Collect address"
    assert has_element?(view, "button", "Onboarding")
    assert has_element?(view, "button", "Flows")
  end

  test "the index lists roots but not their owned subflow children", %{conn: conn} do
    root_id = create_flow(conn, "Onboarding", "subflows")
    save_subflow_node(conn, root_id)

    {:ok, view, html} = live(conn, "/admin/flows")

    assert html =~ "Onboarding"
    refute html =~ "Subflow 1"
    assert view |> render() |> String.split("<tr") |> length() == 3
  end

  test "the index name links to the show page", %{conn: conn} do
    id = create_flow(conn, "Enrollment")

    {:ok, view, _html} = live(conn, "/admin/flows")

    assert view |> element(~s(td a[href="/admin/flows/#{id}"]), "Enrollment") |> has_element?()
  end

  test "deleting from a drill-in page removes the step and returns to the parent's editor", %{
    conn: conn
  } do
    root_id = create_flow(conn, "Onboarding", "subflows")
    save_subflow_node(conn, root_id)
    [node] = Flows.get(root_id).nodes

    {:ok, view, _html} = live(conn, "/admin/flows/#{root_id}/nodes/#{node.id}")

    view |> element("button", "Delete") |> render_click()
    assert_redirect(view, "/admin/flows/#{root_id}/edit")

    assert Flows.get(root_id).nodes == []
    assert Flows.get(node.subflow_id) == nil
  end

  test "deleting two levels deep returns to the containing subflow's editor", %{conn: conn} do
    {:ok, root} = Flows.create(%{name: "Root", label: "subflows"})

    {:ok, _} =
      Flows.update(root, %{
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

    [x] = Flows.get(root.id).nodes
    middle = Flows.get(x.subflow_id)

    {:ok, _} =
      Flows.update(middle, %{
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

    [y] = Enum.filter(Flows.get(middle.id).nodes, &(&1.properties["type"] == "subflow"))

    # The page shows Leaf; deleting removes node y from Middle, so the
    # destination is Middle's editor — addressed by the node embedding Middle
    {:ok, view, _html} = live(conn, "/admin/flows/#{root.id}/nodes/#{y.id}")

    view |> element("button", "Delete") |> render_click()
    assert_redirect(view, "/admin/flows/#{root.id}/nodes/#{x.id}/edit")

    assert Flows.get(y.subflow_id) == nil
    assert Flows.get(middle.id) != nil
  end

  test "deleting a subflow another flow still uses is refused with an explanation", %{conn: conn} do
    root_id = create_flow(conn, "Onboarding", "subflows")
    save_subflow_node(conn, root_id)
    [node] = Flows.get(root_id).nodes

    # Visiting the owned child directly and trying to delete it
    {:ok, view, _html} = live(conn, "/admin/flows/#{node.subflow_id}")

    view |> element("button", "Delete") |> render_click()

    assert render(view) =~ "another flow still uses it as a subflow"
    assert Flows.get(node.subflow_id) != nil
  end

  test "opening a subflow node navigates by node id", %{conn: conn} do
    root_id = create_flow(conn, "Onboarding", "subflows")
    save_subflow_node(conn, root_id)

    [node] = Flows.get(root_id).nodes

    {:ok, view, _html} = live(conn, "/admin/flows/#{root_id}")

    view
    |> element("#flows-show-editor")
    |> render_hook("form_flow:open_subflow", %{"node_id" => node.id})

    assert_redirect(view, "/admin/flows/#{root_id}/nodes/#{node.id}")
  end

  test "opening a subflow node the canvas never reported prompts instead of crashing",
       %{conn: conn} do
    root_id = create_flow(conn, "Onboarding", "subflows")

    {:ok, view, _html} = live(conn, "/admin/flows/#{root_id}/edit")

    view
    |> element("#flows-edit-editor")
    |> render_hook("form_flow:open_subflow", %{"node_id" => "3"})

    assert render(view) =~ "unsaved changes"
  end

  test "opening a brand-new subflow node saves it and navigates to the node it became",
       %{conn: conn} do
    root_id = create_flow(conn, "Onboarding", "subflows")

    {:ok, view, _html} = live(conn, "/admin/flows/#{root_id}/edit")

    # Added but never saved — Flows.get_node/1 can't find it under its
    # editor-temporary id yet
    view
    |> element("#flows-edit-editor")
    |> render_hook("form_flow:flow_changed", %{
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

    [node] = Flows.get(root_id).nodes
    assert {:ok, _} = Ecto.UUID.cast(node.id)
    assert node.subflow_id != nil

    # Not just "back to the root" — the specific node the temp id resolved to
    assert_redirect(view, "/admin/flows/#{root_id}/nodes/#{node.id}/edit")
  end

  test "opening a subflow from the edit canvas navigates directly when nothing changed since save",
       %{conn: conn} do
    root_id = create_flow(conn, "Onboarding", "subflows")
    save_subflow_node(conn, root_id)
    [node] = Flows.get(root_id).nodes

    {:ok, view, _html} = live(conn, "/admin/flows/#{root_id}/edit")

    view
    |> element("#flows-edit-editor")
    |> render_hook("form_flow:open_subflow", %{"node_id" => node.id})

    assert_redirect(view, "/admin/flows/#{root_id}/nodes/#{node.id}/edit")
  end

  test "opening a subflow from the edit canvas with unsaved changes prompts instead of navigating",
       %{conn: conn} do
    root_id = create_flow(conn, "Onboarding", "subflows")
    save_subflow_node(conn, root_id)
    [node] = Flows.get(root_id).nodes

    {:ok, view, _html} = live(conn, "/admin/flows/#{root_id}/edit")

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
    [node] = Flows.get(root_id).nodes

    {:ok, view, _html} = live(conn, "/admin/flows/#{root_id}/edit")

    move_subflow_node(view, node.id)

    view
    |> element("#flows-edit-editor")
    |> render_hook("form_flow:open_subflow", %{"node_id" => node.id})

    view |> element("button", "Save & Continue") |> render_click()

    assert_redirect(view, "/admin/flows/#{root_id}/nodes/#{node.id}/edit")

    [saved_node] = Flows.get(root_id).nodes
    assert saved_node.properties["position"] == %{"x" => 40, "y" => 40}
  end

  test "cancelling the unsaved-changes prompt keeps editing without discarding changes",
       %{conn: conn} do
    root_id = create_flow(conn, "Onboarding", "subflows")
    save_subflow_node(conn, root_id)
    [node] = Flows.get(root_id).nodes

    {:ok, view, _html} = live(conn, "/admin/flows/#{root_id}/edit")

    move_subflow_node(view, node.id)

    view
    |> element("#flows-edit-editor")
    |> render_hook("form_flow:open_subflow", %{"node_id" => node.id})

    view |> element("button", "Keep editing") |> render_click()

    refute render(view) =~ "unsaved changes"

    # Nothing was persisted, and nothing navigated away
    [unmoved_node] = Flows.get(root_id).nodes
    assert unmoved_node.properties["position"] == %{"x" => 0, "y" => 0}

    # The pending edit is still live on the canvas and can still be saved
    view |> element("button", "Save") |> render_click()
    assert render(view) =~ "Saved."

    [saved_node] = Flows.get(root_id).nodes
    assert saved_node.properties["position"] == %{"x" => 40, "y" => 40}
  end

  test "show navigates directly to the show page when nothing changed since save",
       %{conn: conn} do
    id = create_flow(conn)

    {:ok, view, _html} = live(conn, "/admin/flows/#{id}/edit")

    view |> element("button", "Show") |> render_click()

    assert_redirect(view, "/admin/flows/#{id}")
  end

  test "show with unsaved changes prompts to save before leaving", %{conn: conn} do
    id = create_flow(conn)

    {:ok, view, _html} = live(conn, "/admin/flows/#{id}/edit")

    edit_step(view)

    view |> element("button", "Show") |> render_click()

    # Still on the edit page — no redirect fired — with the prompt showing
    assert render(view) =~ "unsaved changes"

    view |> element("button", "Save & Continue") |> render_click()

    assert_redirect(view, "/admin/flows/#{id}")

    assert [node] = Flows.get(id).nodes
    assert node.properties["data"]["label"] == "Renamed step"
  end

  test "the unsaved-guard flag tracks unsaved changes for the beforeunload hook",
       %{conn: conn} do
    id = create_flow(conn)

    {:ok, view, html} = live(conn, "/admin/flows/#{id}/edit")
    assert html =~ ~s(id="flows-edit-unsaved-guard")
    assert has_element?(view, ~s(#flows-edit-unsaved-guard[data-unsaved="false"]))

    edit_step(view)

    assert has_element?(view, ~s(#flows-edit-unsaved-guard[data-unsaved="true"]))

    view |> element("button", "Save") |> render_click()

    assert has_element?(view, ~s(#flows-edit-unsaved-guard[data-unsaved="false"]))
  end

  test "discard changes is hidden when the canvas is clean", %{conn: conn} do
    id = create_flow(conn)

    {:ok, view, _html} = live(conn, "/admin/flows/#{id}/edit")

    refute has_element?(view, "button", "Discard changes")
  end

  test "discarding changes reloads the edit page and drops the unsaved edit", %{conn: conn} do
    id = create_flow(conn)

    {:ok, view, _html} = live(conn, "/admin/flows/#{id}/edit")

    edit_step(view)

    assert has_element?(view, "button", "Discard changes")

    # Selected by phx-click, not text: the modal's confirm button also reads
    # "Discard", a substring of the trigger's "Discard changes"
    view |> element(~s(button[phx-click="request_discard"])) |> render_click()

    assert render(view) =~ "Discard changes?"

    view |> element(~s(button[phx-click="confirm_discard"])) |> render_click()

    assert_redirect(view, "/admin/flows/#{id}/edit")

    # Nothing was persisted — the edit never went through save
    assert length(Flows.get(id).nodes) == 2
  end

  test "cancelling the discard prompt keeps the unsaved edit live", %{conn: conn} do
    id = create_flow(conn)

    {:ok, view, _html} = live(conn, "/admin/flows/#{id}/edit")

    edit_step(view)

    view |> element(~s(button[phx-click="request_discard"])) |> render_click()
    view |> element(~s(button[phx-click="cancel_discard"])) |> render_click()

    refute render(view) =~ "Discard changes?"

    # The pending edit is still live on the canvas and can still be saved
    view |> element("button", "Save") |> render_click()
    assert render(view) =~ "Saved."

    assert [node] = Flows.get(id).nodes
    assert node.properties["data"]["label"] == "Renamed step"
  end

  test "a breadcrumb navigates directly when nothing changed since save", %{conn: conn} do
    id = create_flow(conn)

    {:ok, view, _html} = live(conn, "/admin/flows/#{id}/edit")

    view |> element("button", "Flows") |> render_click()

    assert_redirect(view, "/admin/flows")
  end

  test "a breadcrumb with unsaved changes prompts to save before leaving", %{conn: conn} do
    id = create_flow(conn)

    {:ok, view, _html} = live(conn, "/admin/flows/#{id}/edit")

    edit_step(view)

    view |> element("button", "Flows") |> render_click()

    # Still on the edit page — no redirect fired — with the prompt showing
    assert render(view) =~ "unsaved changes"

    view |> element("button", "Save & Continue") |> render_click()

    assert_redirect(view, "/admin/flows")

    assert [node] = Flows.get(id).nodes
    assert node.properties["data"]["label"] == "Renamed step"
  end

  test "keep editing on a leave prompt discards nothing and stays on the canvas",
       %{conn: conn} do
    id = create_flow(conn)

    {:ok, view, _html} = live(conn, "/admin/flows/#{id}/edit")

    edit_step(view)

    view |> element("button", "Flows") |> render_click()
    view |> element("button", "Keep editing") |> render_click()

    refute render(view) =~ "unsaved changes"

    # Nothing was persisted, and nothing navigated away
    assert length(Flows.get(id).nodes) == 2

    # The pending edit is still live on the canvas and can still be saved
    view |> element("button", "Save") |> render_click()
    assert render(view) =~ "Saved."

    assert [node] = Flows.get(id).nodes
    assert node.properties["data"]["label"] == "Renamed step"
  end

  test "deleting a flow from the show page removes it and its children", %{conn: conn} do
    root_id = create_flow(conn, "Onboarding", "subflows")
    save_subflow_node(conn, root_id)
    [node] = Flows.get(root_id).nodes

    {:ok, view, _html} = live(conn, "/admin/flows/#{root_id}")

    view |> element("button", "Delete") |> render_click()
    assert_redirect(view, "/admin/flows")

    assert Flows.get(root_id) == nil
    assert Flows.get(node.subflow_id) == nil
  end

  test "show and edit handle a flow that does not exist", %{conn: conn} do
    for path <- [
          "/admin/flows/#{Ecto.UUID.generate()}",
          "/admin/flows/not-a-uuid/edit",
          "/admin/flows/#{Ecto.UUID.generate()}/nodes/#{Ecto.UUID.generate()}"
        ] do
      {:ok, _view, html} = live(conn, path)

      assert html =~ "Flow not found"
    end
  end

  # Creates a flow the way a user would: through the new page's chooser
  defp create_flow(conn, name \\ "Untitled flow", label \\ "forms") do
    {:ok, view, _html} = live(conn, "/admin/flows/new")

    view |> element("form") |> render_submit(%{"name" => name, "label" => label})

    {path, _flash} = assert_redirect(view)
    ["", "admin", "flows", id, "edit"] = String.split(path, "/")

    id
  end

  # Adds one subflow node to a complex flow and saves, creating its child
  defp save_subflow_node(conn, root_id) do
    {:ok, view, _html} = live(conn, "/admin/flows/#{root_id}/edit")

    view
    |> element("#flows-edit-editor")
    |> render_hook("form_flow:flow_changed", %{
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

  # A saved subflow node the way the editor reports it: the stored properties
  # (subflow_id reference included) round-trip through the canvas, with `data`
  # merged over the defaults — e.g. a picked form_flow_type
  # Adds one form step to a forms flow and saves, creating its form
  defp save_form_node(conn, flow_id) do
    {:ok, view, _html} = live(conn, "/admin/flows/#{flow_id}/edit")

    view
    |> element("#flows-edit-editor")
    |> render_hook("form_flow:flow_changed", %{
      "nodes" => [
        %{
          "id" => "1",
          "type" => "step",
          "position" => %{"x" => 0, "y" => 0},
          "data" => %{"label" => "Intake", "kind" => "form"}
        }
      ],
      "edges" => []
    })

    view |> element("button", "Save") |> render_click()
  end

  defp form_node_attrs(node, data) do
    %{
      "id" => node.id,
      "type" => "step",
      "form_id" => node.form_id,
      "position" => %{"x" => 0, "y" => 0},
      "data" => Map.merge(%{"label" => "Intake", "kind" => "form"}, data)
    }
  end

  defp subflow_node_attrs(node, data) do
    %{
      "id" => node.id,
      "type" => "subflow",
      "subflow_id" => node.subflow_id,
      "position" => %{"x" => 0, "y" => 0},
      "data" => Map.merge(%{"label" => "Subflow 1", "subflow_label" => "forms"}, data)
    }
  end

  # Reports a moved node without saving — the canvas ends up with unsaved
  # changes relative to whatever was last persisted
  defp move_subflow_node(view, node_id) do
    view
    |> element("#flows-edit-editor")
    |> render_hook("form_flow:flow_changed", %{
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
    |> render_hook("form_flow:flow_changed", %{
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
