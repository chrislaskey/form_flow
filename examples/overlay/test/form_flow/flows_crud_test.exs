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
    assert has_element?(view, ~s(a[href="/admin/flows/#{id}/overview"]), "Overview")
    assert has_element?(view, "code", Flows.get(id).slug)
  end

  test "the index badge reads the cached health; the health page runs the check", %{conn: conn} do
    {:ok, flow} =
      Flows.create(%{
        name: "Enrollment",
        label: "forms",
        nodes: Flows.starter_nodes(),
        relationships: []
      })

    flow = Flows.get(flow.id)
    page = "/admin/flows/#{flow.id}/health"
    badge = ~s(a[href="#{page}"])
    entries = "#flows-health-entries"
    detail = "#flows-health-detail"
    standing = "#flows-health-standing"

    # Never checked: the index runs no check, so the badge says so
    {:ok, view, _html} = live(conn, "/admin/flows")
    assert has_element?(view, "#{badge} span", "–")

    # Start and End, unwired: Start reaches nothing (an error, with the flow
    # itself), End is not connected (a warning). The page names the flow,
    # says what it checked, and how it stands.
    {:ok, view, _html} = live(conn, page)

    assert has_element?(view, "h2", "Enrollment")
    assert has_element?(view, "h2", "Health check")
    assert has_element?(view, "dt", "Checked")
    assert has_element?(view, "#flows-health-checked", "just now")
    assert has_element?(view, ~s(nav a[href="/admin/flows/#{flow.id}"]), "Enrollment")
    assert has_element?(view, "nav", "Health")
    refute has_element?(view, ~s(a[href="/admin/flows/#{flow.id}/edit"]), "Edit")
    assert has_element?(view, "dt", "Perspectives")
    assert has_element?(view, "dd", "Simple flow")
    assert has_element?(view, standing, "1 error")
    assert has_element?(view, standing, "1 warning")
    assert has_element?(view, standing, "checks passing")
    assert has_element?(view, ~s(a[href="/admin/flows/#{flow.id}/overview"]), "Flow Overview")

    # Every entry as a row — where it is — the first open one selected, and
    # its detail: the message, why, the check, what to do, where Open goes
    assert has_element?(view, "#{entries} button[aria-current=true]", "Enrollment")
    assert has_element?(view, "#{entries} button[aria-current=false]", "End")
    assert has_element?(view, "#{detail} h3", "This flow does not connect Start to End")
    assert has_element?(view, "#{detail} .badge", "error")
    assert has_element?(view, "#{detail} code", "end_unreachable")
    assert has_element?(view, detail, "To fix:")
    assert has_element?(view, detail, "a path leads from Start to End")

    assert has_element?(
             view,
             ~s(#{detail} a[href="/admin/flows/#{flow.id}/edit"]),
             "Open Enrollment"
           )

    # The visit wrote the cache: the badge now counts what is open
    {:ok, index, _html} = live(conn, "/admin/flows")
    assert has_element?(index, "#{badge} span", "2")

    # Selecting the warning rides in the URL, and the detail follows
    stop = Enum.find(flow.nodes, &("End" in &1.labels))
    key = "unconnected@#{stop.id}"

    view |> element(~s(#{entries} button[phx-value-entry="#{key}"])) |> render_click()

    assert_patch(view, "#{page}?entry=#{key}")
    assert has_element?(view, "#{detail} h3", "“End” is not connected from Start")
    assert has_element?(view, "#{detail} .badge", "warning")
    assert has_element?(view, ~s(#{detail} a[href="/admin/flows/#{flow.id}/edit"]), "Open End")

    # Ignoring it: the switch turns on, it leaves the count, stays listed with
    # who and when, and is recorded on the flow for the next visit
    switch = "#flows-health-ignore"
    assert has_element?(view, "#{switch}[aria-checked=false]", "Ignore")

    view |> element(switch) |> render_click()

    assert has_element?(view, "#{switch}[aria-checked=true]", "Ignored")
    today = Date.to_iso8601(Date.utc_today())
    assert has_element?(view, detail, "Ignored by demo-admin on #{today}")
    assert has_element?(view, standing, "1 ignored")
    assert has_element?(view, standing, "0 warnings")
    assert has_element?(view, "#{entries} button[aria-current=true] .bg-zinc-300")

    assert %{
             "ignored_entries" => [
               %{"code" => "unconnected", "user_id" => "demo-admin", "path" => [_end_id]}
             ],
             "status" => %{"level" => "error", "counts" => %{"ignored" => 1}}
           } = Flows.get(flow.id).properties["_health_metadata"]

    {:ok, index, _html} = live(conn, "/admin/flows")
    assert has_element?(index, "#{badge} span", "1")

    # The URL brings the selection back; stop ignoring
    {:ok, view, _html} = live(conn, "#{page}?entry=#{key}")
    assert has_element?(view, "#{switch}[aria-checked=true]", "Ignored")

    view |> element(switch) |> render_click()

    assert has_element?(view, "#{switch}[aria-checked=false]", "Ignore")
    refute Map.has_key?(Flows.get(flow.id).properties["_health_metadata"], "ignored_entries")

    {:ok, index, _html} = live(conn, "/admin/flows")
    assert has_element?(index, "#{badge} span", "2")
  end

  test "the health page says so when the flow is deleted under it", %{conn: conn} do
    {:ok, flow} =
      Flows.create(%{name: "Gone", nodes: Flows.starter_nodes(), relationships: []})

    {:ok, view, _html} = live(conn, "/admin/flows/#{flow.id}/health")
    assert has_element?(view, "#flows-health-ignore")

    {:ok, _flow} = Flows.delete(Flows.get(flow.id))

    view |> element("#flows-health-ignore") |> render_click()

    assert render(view) =~ "Flow not found."
  end

  test "saves through the pages refresh the badge; the health page catches up a lagging one",
       %{conn: conn} do
    id = create_flow(conn, "Enrollment")
    page = "/admin/flows/#{id}/health"
    badge = ~s(a[href="#{page}"])

    # Wired through a form step from the edit page: the save creates the
    # step's form as a draft, which users cannot start — one error — and the
    # page's own badge (through the navigate event) reads the fresh status
    flow = Flows.get(id)
    start = Enum.find(flow.nodes, &("Start" in &1.labels))
    stop = Enum.find(flow.nodes, &("End" in &1.labels))

    # The New page cached the flow's first status: Start and End, unwired
    {:ok, view, _html} = live(conn, "/admin/flows/#{id}/edit")
    assert has_element?(view, ~s(button[phx-value-to="#{page}"] span), "2")

    view
    |> element("#flows-edit-editor")
    |> render_hook("form_flow:flow_changed", %{
      "nodes" => [
        %{
          "id" => start.id,
          "type" => "step",
          "position" => %{"x" => 0, "y" => 0},
          "data" => start.properties["data"]
        },
        %{
          "id" => stop.id,
          "type" => "step",
          "position" => %{"x" => 900, "y" => 0},
          "data" => stop.properties["data"]
        },
        %{
          "id" => "1",
          "type" => "step",
          "position" => %{"x" => 450, "y" => 0},
          "data" => %{"label" => "Name", "kind" => "form"}
        }
      ],
      "edges" => [
        %{"id" => "e1", "source" => start.id, "target" => "1"},
        %{"id" => "e2", "source" => "1", "target" => stop.id}
      ]
    })

    view |> element("button", "Save") |> render_click()

    assert render(view) =~ "Saved."
    assert has_element?(view, ~s(button[phx-value-to="#{page}"] span), "1")

    {:ok, index, _html} = live(conn, "/admin/flows")
    assert has_element?(index, "#{badge} span", "1")

    # The badge leaves the edit page through the navigate event, like Overview
    view |> element(~s(button[phx-value-to="#{page}"])) |> render_click()
    assert_redirect(view, page)

    # Publishing the step's form from its page: healthy, and the show page's
    # badge — the root's, from a drill-in — says so
    node = Enum.find(Flows.get(id).nodes, & &1.form_id)
    [draft] = Forms.list_versions(node.form_id)
    form_page = "/admin/flows/#{id}/nodes/#{node.id}/form/versions/#{draft.id}"

    {:ok, view, _html} = live(conn, form_page)
    view |> element("button", "Publish") |> render_click()
    assert_redirect(view, form_page)

    {:ok, view, _html} = live(conn, "/admin/flows/#{id}")
    assert has_element?(view, "#{badge} span", "✓")

    {:ok, view, _html} = live(conn, page)
    assert has_element?(view, "#flows-health-standing", "0 errors")
    assert render(view) =~ "Nothing to report"

    # A save that bypasses the pages leaves the badge behind — until the
    # health page is opened, which writes the cache back
    flow = Flows.get(id)

    {:ok, _flow} =
      Flows.update(flow, %{
        nodes: Enum.map(flow.nodes, &%{id: &1.id, properties: &1.properties}),
        relationships: []
      })

    {:ok, index, _html} = live(conn, "/admin/flows")
    assert has_element?(index, "#{badge} span", "✓")

    {:ok, view, _html} = live(conn, page)
    assert has_element?(view, "#flows-health-standing", "1 error")

    {:ok, index, _html} = live(conn, "/admin/flows")
    assert has_element?(index, "#{badge} span", "3")
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

  test "drilled into a subflow, the header's Step slug edits the step; the subflow has none",
       %{conn: conn} do
    root_id = create_flow(conn, "Licensing", "subflows")
    save_subflow_node(conn, root_id)
    [node] = Flows.get(root_id).nodes
    assert node.slug == "licensing_subflow-1"
    assert Flows.get(node.subflow_id).slug == nil

    {:ok, view, html} = live(conn, "/admin/flows/#{root_id}/nodes/#{node.id}/edit")
    assert html =~ "Step slug"
    assert html =~ "licensing_subflow-1"

    view
    |> element("#flows-edit-flow-form-form")
    |> render_change(%{"dynamic_form" => %{"slug" => "documents"}})

    assert Flows.get_node(node.id).slug == "licensing_subflow-1"
    assert has_element?(view, "button", "Discard changes")

    view |> element("button", "Save") |> render_click()

    assert Flows.get_node(node.id).slug == "documents"
    assert Flows.get(node.subflow_id).slug == nil
    assert Flows.get(root_id).slug == "licensing"
    refute has_element?(view, "button", "Discard changes")
  end

  test "a subflow's identity form offers its type's perspectives; Save stores them",
       %{conn: conn} do
    root_id = create_flow(conn, "Licensing", "subflows")
    save_subflow_node(conn, root_id)
    [node] = Flows.get(root_id).nodes

    # The field belongs to the type the subflow amounts to — a fresh one
    # never chose, so the first type's, shown as selected
    {:ok, view, html} = live(conn, "/admin/flows/#{root_id}/nodes/#{node.id}/edit")
    assert html =~ "Perspectives"
    assert html =~ "Reviewer"
    assert Flows.get(node.subflow_id).properties["form_flow_type"] == nil

    view
    |> element("#flows-edit-flow-form-form")
    |> render_change(%{
      "dynamic_form" => %{"form_flow_type" => "wizard_in_order", "perspectives" => ["reviewer"]}
    })

    # Nothing persists until Save — a pending choice is an unsaved change
    refute Map.has_key?(Flows.get(node.subflow_id).properties, "perspectives")
    assert has_element?(view, "button", "Discard changes")

    view |> element("button", "Save") |> render_click()

    assert Flows.get(node.subflow_id).properties["perspectives"] == ["reviewer"]

    # Show mode names them
    {:ok, _view, html} = live(conn, "/admin/flows/#{root_id}/nodes/#{node.id}")
    assert html =~ "For: Reviewer"

    # The parent canvas names them on the subflow node: the ids ride in the
    # node's data, the names in the editor's options
    {:ok, view, _html} = live(conn, "/admin/flows/#{root_id}")
    canvas = view |> element("#flows-show-editor") |> render()
    assert canvas =~ ~s(perspectives&quot;:[&quot;reviewer&quot;])
    assert canvas =~ "Reviewer"
  end

  test "the canvas's projected perspectives never save onto the node", %{conn: conn} do
    root_id = create_flow(conn, "Licensing", "subflows")
    save_subflow_node(conn, root_id)
    [node] = Flows.get(root_id).nodes

    {:ok, _} =
      Flows.update(Flows.get(node.subflow_id), %{properties: %{"perspectives" => ["reviewer"]}})

    # The editor reports the node back with the projection still in its data
    {:ok, view, _html} = live(conn, "/admin/flows/#{root_id}/edit")

    view
    |> element("#flows-edit-editor")
    |> render_hook("form_flow:flow_changed", %{
      "nodes" => [
        %{
          "id" => node.id,
          "type" => "subflow",
          "subflow_id" => node.subflow_id,
          "position" => %{"x" => 0, "y" => 0},
          "data" => %{
            "label" => "Subflow 1",
            "subflow_label" => "forms",
            "perspectives" => ["reviewer"]
          }
        }
      ],
      "edges" => []
    })

    view |> element("button", "Save") |> render_click()

    [saved] = Flows.get(root_id).nodes
    refute Map.has_key?(saved.properties["data"], "perspectives")
    assert Flows.get(node.subflow_id).properties["perspectives"] == ["reviewer"]
  end

  test "a subflow that never chose a type shows the first one, on edit and show", %{conn: conn} do
    root_id = create_flow(conn, "Onboarding", "subflows")
    save_subflow_node(conn, root_id)
    [node] = Flows.get(root_id).nodes

    {:ok, _view, html} = live(conn, "/admin/flows/#{root_id}/nodes/#{node.id}/edit")

    assert html =~
             ~r/<option[^>]*selected[^>]*value="wizard_in_order"|<option[^>]*value="wizard_in_order"[^>]*selected/

    {:ok, _view, html} = live(conn, "/admin/flows/#{root_id}/nodes/#{node.id}")
    assert html =~ "Wizard (in order)"

    # Shown, not stored: the subflow still behaves as the default until the
    # admin picks, and nothing was written to make it so
    assert Flows.get(node.subflow_id).properties["form_flow_type"] == nil
  end

  test "a complex flow has no perspectives of its own — its subflows do", %{conn: conn} do
    root_id = create_flow(conn, "Licensing", "subflows")

    {:ok, _view, html} = live(conn, "/admin/flows/#{root_id}/edit")

    refute html =~ "Perspectives"
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
    # demo's types add — proof the router's flow_types attr reaches the
    # page
    assert html =~ "Form flow type"
    assert html =~ "Wizard (any order)"
    assert html =~ "Wizard (in order)"
    assert html =~ "Demo checklist"

    view
    |> element("#flows-edit-flow-form-form")
    |> render_change(%{"dynamic_form" => %{"form_flow_type" => "wizard_any_order"}})

    # Nothing persists until Save — a pending type is an unsaved change
    assert Map.delete(Flows.get(id).properties, "_health_metadata") == %{"slug" => "untitled-fl"}
    assert has_element?(view, "button", "Discard changes")

    view |> element("button", "Save") |> render_click()

    # The save also caches the flow's health, under its own key
    assert Map.delete(Flows.get(id).properties, "_health_metadata") == %{
             "form_flow_type" => "wizard_any_order",
             "slug" => "untitled-fl"
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

    assert Map.delete(Flows.get(id).properties, "_health_metadata") == %{"slug" => "untitled-fl"}
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

    assert Forms.get(node.form_id).properties == %{"form_type" => "review"}

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
    assert Forms.get(node.form_id).properties == %{}
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

    assert Flows.get(node.subflow_id).properties == %{"form_flow_type" => "wizard_any_order"}

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

    assert Flows.get(node.subflow_id).properties == %{}
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

  test "renaming a subflow on its own edit page renames the step in the parent too", %{conn: conn} do
    root_id = create_flow(conn, "Dog License", "subflows")
    save_subflow_node(conn, root_id)
    [node] = Flows.get(root_id).nodes

    {:ok, view, html} = live(conn, "/admin/flows/#{root_id}/nodes/#{node.id}/edit")
    assert html =~ "Step name"

    view
    |> element("#flows-edit-flow-form-form")
    |> render_change(%{"dynamic_form" => %{"name" => "Application"}})

    view |> element("button", "Save") |> render_click()
    assert render(view) =~ "Saved."

    assert Flows.get(node.subflow_id).name == "Application"
    [node] = Flows.get(root_id).nodes
    assert get_in(node.properties, ["data", "label"]) == "Application"

    # Reloading the parent's canvas shows the step's own label — nothing is
    # projected over it from the subflow
    {:ok, _view, html} = live(conn, "/admin/flows/#{root_id}/edit")
    assert html =~ "Application"
  end

  test "the root flow's own edit page still edits its name", %{conn: conn} do
    id = create_flow(conn, "Dog License")

    {:ok, _view, html} = live(conn, "/admin/flows/#{id}/edit")
    refute html =~ "Step name"
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

  test "deleting a subflow on its own page is refused with an explanation", %{conn: conn} do
    root_id = create_flow(conn, "Onboarding", "subflows")
    save_subflow_node(conn, root_id)
    [node] = Flows.get(root_id).nodes

    # Visiting the owned child directly and trying to delete it
    {:ok, view, _html} = live(conn, "/admin/flows/#{node.subflow_id}")

    view |> element("button", "Delete") |> render_click()

    assert render(view) =~ "it is a subflow of another flow"
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

  test "copying from the show page asks a name and slug, and lands on the copy", %{conn: conn} do
    id = create_flow(conn, "Dog License", "forms")
    save_form_node(conn, id)
    [source_step] = Flows.get(id).nodes

    {:ok, view, _html} = live(conn, "/admin/flows/#{id}")

    # The dialog prefills what a copy would get by default
    html = view |> element("button", "Duplicate Flow") |> render_click()
    assert html =~ "Duplicate this flow?"
    assert html =~ ~s|value="Dog License (copy)"|
    assert html =~ ~s|value="dog-license-2"|

    view
    |> element("form[phx-submit=copy]")
    |> render_submit(%{"name" => "Dog License 2027", "slug" => ""})

    {path, _flash} = assert_redirect(view)
    assert "/admin/flows/" <> copy_id = path
    copy = Flows.get(copy_id)
    assert copy.name == "Dog License 2027"
    # Left blank, the slug is the default the dialog showed
    assert copy.slug == "dog-license-2"

    # The copy is whole — its own step on its own form, with provenance —
    # and its health is cached, as for any saved flow
    assert [step] = copy.nodes
    assert step.id != source_step.id
    assert step.form_id != source_step.form_id
    assert Forms.get(step.form_id).copied_from_form_id == source_step.form_id
    assert FormFlow.Data.Templates.Flows.Health.status(copy) != nil

    # The index lists both, by their own names
    {:ok, _view, html} = live(conn, "/admin/flows")
    assert html =~ "Dog License 2027"
    assert html =~ "Dog License"
  end

  test "a taken slug keeps the copy dialog open with the reason", %{conn: conn} do
    id = create_flow(conn, "Dog License", "forms")
    before = length(Flows.list())

    {:ok, view, _html} = live(conn, "/admin/flows/#{id}")
    view |> element("button", "Duplicate Flow") |> render_click()

    html =
      view
      |> element("form[phx-submit=copy]")
      |> render_submit(%{"name" => "Dog License (copy)", "slug" => "dog-license"})

    assert html =~ "Duplicate this flow?"
    assert html =~ "The slug has already been taken."
    assert length(Flows.list()) == before

    # The dialog redraws with what was typed, so the fix is one edit away
    assert html =~ ~s|value="dog-license"|
    assert html =~ ~s|value="Dog License (copy)"|

    # Cancel closes it
    refute view |> element("button", "Cancel") |> render_click() =~ "Duplicate this flow?"
  end

  test "the index copies a flow from its row menu, and lands on the copy", %{conn: conn} do
    id = create_flow(conn, "Dog License", "forms")
    save_form_node(conn, id)
    menu = "#flow-#{id}-actions"

    {:ok, view, _html} = live(conn, "/admin/flows")

    # The dialog prefills for that row's flow
    html = view |> element("#{menu} button", "Duplicate Flow") |> render_click()
    assert html =~ "Duplicate this flow?"
    assert html =~ ~s|value="Dog License (copy)"|
    assert html =~ ~s|value="dog-license-2"|

    # A blank name is the one offered
    view
    |> element("form[phx-submit=copy]")
    |> render_submit(%{"name" => "", "slug" => "dl-copy"})

    {path, _flash} = assert_redirect(view)
    assert "/admin/flows/" <> copy_id = path
    copy = Flows.get(copy_id)
    assert copy.name == "Dog License (copy)"
    assert copy.slug == "dl-copy"
    assert [_step] = copy.nodes
    assert FormFlow.Data.Templates.Flows.Health.status(copy) != nil

    # Cancel closes the dialog without a copy
    {:ok, view, _html} = live(conn, "/admin/flows")
    before = length(Flows.list())
    view |> element("#{menu} button", "Duplicate Flow") |> render_click()
    refute view |> element("button", "Cancel") |> render_click() =~ "Duplicate this flow?"
    assert length(Flows.list()) == before
  end

  test "the edit page has no Duplicate Flow: a copy is of what is saved", %{conn: conn} do
    id = create_flow(conn, "Dog License", "forms")

    {:ok, view, _html} = live(conn, "/admin/flows/#{id}/edit")
    refute has_element?(view, "button", "Duplicate Flow")

    {:ok, view, _html} = live(conn, "/admin/flows/#{id}")
    assert has_element?(view, "button", "Duplicate Flow")
  end

  test "a subflow's show page has no Duplicate Flow: a subflow is copied by pasting its step",
       %{conn: conn} do
    root_id = create_flow(conn, "Licensing", "subflows")
    save_subflow_node(conn, root_id)
    [node] = Flows.get(root_id).nodes

    # Drilled in, or addressed by the owned flow's own id: the guard is
    # ownership, not the route
    for path <- [
          "/admin/flows/#{root_id}/nodes/#{node.id}",
          "/admin/flows/#{node.subflow_id}"
        ] do
      {:ok, view, _html} = live(conn, path)
      refute has_element?(view, "button", "Duplicate Flow")
    end

    {:ok, view, _html} = live(conn, "/admin/flows/#{root_id}")
    assert has_element?(view, "button", "Duplicate Flow")
  end

  test "a step pasted on the canvas is copied at save; a source that is gone refuses the save with the reason",
       %{conn: conn} do
    id = create_flow(conn, "Intake", "forms")
    save_form_node(conn, id)
    [source] = Flows.get(id).nodes

    {:ok, view, _html} = live(conn, "/admin/flows/#{id}/edit")

    # The pasted node as the canvas reports it: the source's snapshot — its
    # stale form_id copy included — under a temp id, with the marker in data
    pasted = %{
      "id" => "2",
      "type" => "step",
      "form_id" => source.form_id,
      "position" => %{"x" => 300, "y" => 0},
      "data" => %{"label" => "Intake again", "kind" => "form", "copy_of_node_id" => source.id}
    }

    view
    |> element("#flows-edit-editor")
    |> render_hook("form_flow:flow_changed", %{
      "nodes" => [form_node_attrs(source, %{}), pasted],
      "edges" => []
    })

    view |> element("button", "Save") |> render_click()

    nodes = Flows.get(id).nodes
    assert length(nodes) == 2
    again = Enum.find(nodes, &(get_in(&1.properties, ["data", "label"]) == "Intake again"))
    assert again.form_id != source.form_id
    assert Forms.get(again.form_id).copied_from_form_id == source.form_id
    assert Forms.get(again.form_id).name == "Intake again"
    refute Map.has_key?(again.properties["data"], "copy_of_node_id")

    # A marker naming a step that no longer exists: the save is refused, and
    # the page says so in the words the data layer chose
    gone = %{
      pasted
      | "id" => "3",
        "data" => Map.put(pasted["data"], "copy_of_node_id", Ecto.UUID.generate())
    }

    view
    |> element("#flows-edit-editor")
    |> render_hook("form_flow:flow_changed", %{
      "nodes" => [
        form_node_attrs(source, %{}),
        form_node_attrs(again, %{"label" => "Intake again"}),
        gone
      ],
      "edges" => []
    })

    html = view |> element("button", "Save") |> render_click()
    assert html =~ "The step it was copied from no longer exists."
    assert length(Flows.get(id).nodes) == 2
  end

  test "show, edit, and the overview handle a flow that does not exist", %{conn: conn} do
    for path <- [
          "/admin/flows/#{Ecto.UUID.generate()}",
          "/admin/flows/not-a-uuid/edit",
          "/admin/flows/#{Ecto.UUID.generate()}/nodes/#{Ecto.UUID.generate()}",
          "/admin/flows/#{Ecto.UUID.generate()}/overview"
        ] do
      {:ok, _view, html} = live(conn, path)

      assert html =~ "Flow not found"
    end
  end

  test "the overview draws every level at once, connected steps only", %{conn: conn} do
    root_id = create_flow(conn, "Licensing", "subflows")

    # Start → Application → End, plus a subflow node nothing points at
    {:ok, view, _html} = live(conn, "/admin/flows/#{root_id}/edit")

    view
    |> element("#flows-edit-editor")
    |> render_hook("form_flow:flow_changed", %{
      "nodes" => [
        step_attrs("1", "Start", "start"),
        %{
          "id" => "2",
          "type" => "subflow",
          "position" => %{"x" => 0, "y" => 0},
          "data" => %{"label" => "Application", "subflow_label" => "forms"}
        },
        step_attrs("3", "End", "end"),
        %{
          "id" => "4",
          "type" => "subflow",
          "position" => %{"x" => 0, "y" => 0},
          "data" => %{"label" => "Abandoned idea", "subflow_label" => "forms"}
        }
      ],
      "edges" => [
        %{"id" => "e1-2", "source" => "1", "target" => "2"},
        %{"id" => "e2-3", "source" => "2", "target" => "3"}
      ]
    })

    view |> element("button", "Save") |> render_click()

    application = flow_node(root_id, "Application")

    # Inside it: Start → Intake → End, plus a form step nothing points at
    {:ok, view, _html} = live(conn, "/admin/flows/#{root_id}/nodes/#{application.id}/edit")

    view
    |> element("#flows-edit-editor")
    |> render_hook("form_flow:flow_changed", %{
      "nodes" => [
        step_attrs("1", "Start", "start"),
        step_attrs("2", "Intake", "form"),
        step_attrs("3", "End", "end"),
        step_attrs("4", "Draft form", "form")
      ],
      "edges" => [
        %{"id" => "e1-2", "source" => "1", "target" => "2"},
        %{"id" => "e2-3", "source" => "2", "target" => "3"}
      ]
    })

    view |> element("button", "Save") |> render_click()

    {:ok, view, html} = live(conn, "/admin/flows/#{root_id}/overview")

    assert html =~ "Licensing"

    tree = overview_tree(view)

    assert tree["flow"]["name"] == "Licensing"
    assert node_labels(tree["nodes"]) == ["Application", "End", "Start"]

    # The subflow is expanded in place, keyed by the node that embeds it
    assert Map.keys(tree["subflows"]) == [application.id]
    assert [inner] = Map.values(tree["subflows"])
    assert node_labels(inner["nodes"]) == ["End", "Intake", "Start"]

    # Neither level's unwired step is drawn here — the drill-down is where
    # they are seen and fixed, and both are still on it
    refute html =~ "Abandoned idea"
    refute html =~ "Draft form"

    {:ok, _view, root_html} = live(conn, "/admin/flows/#{root_id}")
    assert root_html =~ "Abandoned idea"

    {:ok, _view, inner_html} = live(conn, "/admin/flows/#{root_id}/nodes/#{application.id}")
    assert inner_html =~ "Draft form"
  end

  test "the overview's Open events navigate under the root, like the show page's", %{conn: conn} do
    root_id = create_flow(conn, "Licensing", "subflows")
    save_subflow_node(conn, root_id)
    [node] = Flows.get(root_id).nodes

    {:ok, view, _html} = live(conn, "/admin/flows/#{root_id}/overview")

    view
    |> element("#flows-overview-overview")
    |> render_hook("form_flow:open_subflow", %{"node_id" => node.id})

    assert_redirect(view, "/admin/flows/#{root_id}/nodes/#{node.id}")

    {:ok, view, _html} = live(conn, "/admin/flows/#{root_id}/overview")

    view
    |> element("#flows-overview-overview")
    |> render_hook("form_flow:open_form", %{"node_id" => node.id})

    assert_redirect(view, "/admin/flows/#{root_id}/nodes/#{node.id}/form")
  end

  test "show and edit link to the overview, from any depth, for the root", %{conn: conn} do
    root_id = create_flow(conn, "Licensing", "subflows")
    save_subflow_node(conn, root_id)
    [node] = Flows.get(root_id).nodes

    overview = "/admin/flows/#{root_id}/overview"

    {:ok, view, _html} = live(conn, "/admin/flows/#{root_id}")
    assert has_element?(view, ~s(a[href="#{overview}"]), "Overview")

    {:ok, view, _html} = live(conn, "/admin/flows/#{root_id}/nodes/#{node.id}")
    assert has_element?(view, ~s(a[href="#{overview}"]), "Overview")

    # The edit page leaves through its own "navigate" event, so unsaved
    # changes prompt first — a button carrying the destination, not a link
    {:ok, view, _html} = live(conn, "/admin/flows/#{root_id}/nodes/#{node.id}/edit")
    assert has_element?(view, ~s(button[phx-value-to="#{overview}"]), "Overview")

    view |> element(~s(button[phx-value-to="#{overview}"])) |> render_click()
    assert_redirect(view, overview)
  end

  test "show, edit, and the overview carry the root's health badge, from any depth", %{conn: conn} do
    root_id = create_flow(conn, "Licensing", "subflows")
    save_subflow_node(conn, root_id)
    [node] = Flows.get(root_id).nodes

    health = "/admin/flows/#{root_id}/health"

    # The edit page's save refreshed the root; every page reads that one status
    %{counts: counts} = FormFlow.Data.Templates.Flows.Health.status(Flows.get(root_id))
    count = to_string(counts.error + counts.warning + counts.info)

    for path <- [
          "/admin/flows/#{root_id}",
          "/admin/flows/#{root_id}/nodes/#{node.id}",
          "/admin/flows/#{root_id}/overview"
        ] do
      {:ok, view, _html} = live(conn, path)
      assert has_element?(view, ~s(a[href="#{health}"][title^="Health:"] span), count)
    end

    {:ok, view, _html} = live(conn, "/admin/flows/#{root_id}/nodes/#{node.id}/edit")
    assert has_element?(view, ~s(button[phx-value-to="#{health}"] span), count)

    # A subflow's own health page reports its root
    {:ok, view, _html} = live(conn, "/admin/flows/#{node.subflow_id}/health")
    assert has_element?(view, "h2", "Licensing")
    assert has_element?(view, "#flows-health-entries button", "Licensing")
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

  # A Start, End, or form step the way the editor reports it
  defp step_attrs(id, label, kind) do
    %{
      "id" => id,
      "type" => "step",
      "position" => %{"x" => 0, "y" => 0},
      "data" => %{"label" => label, "kind" => kind}
    }
  end

  defp flow_node(flow_id, label) do
    Enum.find(Flows.get(flow_id).nodes, &(get_in(&1.properties, ["data", "label"]) == label))
  end

  # The nested ReactFlow data the overview canvas mounts with, read off the
  # hook's container the way the bundle reads it
  defp overview_tree(view) do
    view
    |> element("#flows-overview-overview")
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.attribute("data-tree")
    |> hd()
    |> Jason.decode!()
  end

  defp node_labels(nodes), do: nodes |> Enum.map(&get_in(&1, ["data", "label"])) |> Enum.sort()
end
