defmodule Demo.FormFlowFormsCrudTest do
  @moduledoc """
  Drives the forms CRUD pages end-to-end through the dedicated
  `live "/admin/*path", AdminLive` route (mounted with `base="/admin"`):
  `/admin/forms` is the catalog, `/admin/forms/new` creates a lineage with
  its initial draft, `/admin/forms/:id` shows the resolved version (latest
  published, else newest draft) with the version history and the publish
  dialog, `/admin/forms/:id/versions/:vid/edit` edits a draft, and
  `/admin/flows/:root/nodes/:node_id/form` is the drill-in from a flow.

  The editor's React side can't run here, so the form node's Open button is
  driven by pushing the hook's event.
  """

  use DemoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias FormFlow.Data.Graphs
  alias FormFlow.Data.Templates.Forms

  test "the admin root is a generic landing linking both indexes", %{conn: conn} do
    {:ok, view, html} = live(conn, "/admin")

    assert html =~ "Templates"
    assert has_element?(view, ~s(a[href="/admin/flows"]), "Flows")
    assert has_element?(view, ~s(a[href="/admin/forms"]), "Forms")
  end

  test "breadcrumbs lead back to the landing from inside both sections", %{conn: conn} do
    for path <- ["/admin/forms", "/admin/flows", "/admin/forms/new", "/admin/flows/new"] do
      {:ok, view, _html} = live(conn, path)

      assert has_element?(view, ~s(a[href="/admin"]), "Templates"),
             "missing Templates root crumb on #{path}"
    end
  end

  test "the new page creates a lineage with its initial draft", %{conn: conn} do
    {:ok, view, html} = live(conn, "/admin/forms/new")

    assert html =~ "New form"

    view
    |> element("#forms-new-form-form")
    |> render_submit(%{"dynamic_form" => %{"name" => "W-2 Details", "description" => "Wages"}})

    {path, _flash} = assert_redirect(view)
    assert "/admin/forms/" <> id = path

    form = Forms.get(id)
    assert form.name == "W-2 Details"
    assert [%{status: "draft"}] = Forms.list_versions(id)
  end

  test "the catalog lists forms; owned forms never appear", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/admin/forms")
    assert html =~ "No forms yet"

    {:ok, form} = Forms.create(%{name: "Catalog form"})
    {:ok, graph} = Graphs.create()
    {:ok, _owned} = Forms.create(%{name: "Owned form", owner_graph_id: graph.id})

    {:ok, view, html} = live(conn, "/admin/forms")

    assert html =~ "Catalog form"
    refute html =~ "Owned form"
    assert has_element?(view, ~s(a[href="/admin/forms/#{form.id}"]), "Show")
  end

  test "show resolves the newest draft before anything is published", %{conn: conn} do
    {:ok, form} = Forms.create(%{name: "Unpublished", definition: %{"wip" => true}})

    {:ok, _view, html} = live(conn, "/admin/forms/#{form.id}")

    assert html =~ "draft"
    assert html =~ "wip"
  end

  test "editing a draft saves JSON and rejects bad syntax", %{conn: conn} do
    {:ok, form} = Forms.create(%{name: "Editable"})
    [draft] = Forms.list_versions(form.id)

    {:ok, view, html} = live(conn, "/admin/forms/#{form.id}/versions/#{draft.id}/edit")

    assert html =~ "Definition (JSON)"

    view
    |> element("#forms-edit-form-form")
    |> render_submit(%{
      "dynamic_form" => %{
        "name" => "Editable",
        "definition" => ~s({"fields": [{"name": "ssn"}]})
      }
    })

    assert render(view) =~ "Saved."
    assert Forms.get_version(draft.id).definition == %{"fields" => [%{"name" => "ssn"}]}

    view
    |> element("#forms-edit-form-form")
    |> render_submit(%{"dynamic_form" => %{"name" => "Editable", "definition" => "{nope"}})

    assert render(view) =~ "is not valid JSON"
  end

  test "one Save writes identity to the lineage and the definition to the draft",
       %{conn: conn} do
    {:ok, form} = Forms.create(%{name: "Before", description: "Old"})
    [draft] = Forms.list_versions(form.id)

    {:ok, view, _html} = live(conn, "/admin/forms/#{form.id}/versions/#{draft.id}/edit")

    view
    |> element("#forms-edit-form-form")
    |> render_submit(%{
      "dynamic_form" => %{
        "name" => "After",
        "description" => "New description",
        "definition" => ~s({"fields": []})
      }
    })

    assert render(view) =~ "Saved."

    updated = Forms.get(form.id)
    assert updated.name == "After"
    assert updated.description == "New description"
    assert Forms.get_version(draft.id).definition == %{"fields" => []}
  end

  test "the edit page identifies its draft inline, linking back for the rest",
       %{conn: conn} do
    {form, v1} = published_form()
    {:ok, draft} = Forms.create_draft(form.id, based_on: v1.id)
    {:ok, _other} = Forms.create_draft(form.id)

    {:ok, view, html} = live(conn, "/admin/forms/#{form.id}/versions/#{draft.id}/edit")

    assert html =~ "Editing"
    assert html =~ "1 other draft(s) exist"

    # The base version links to its show page in a new tab
    assert has_element?(
             view,
             ~s(a[href="/admin/forms/#{form.id}/versions/#{v1.id}"][target="_blank"]),
             "v1"
           )
  end

  test "the edit page saves from the header via the remote submit button", %{conn: conn} do
    {:ok, form} = Forms.create(%{name: "Remote"})
    [draft] = Forms.list_versions(form.id)

    {:ok, view, _html} = live(conn, "/admin/forms/#{form.id}/versions/#{draft.id}/edit")

    # The header button submits the DynamicForm below through its form= id;
    # the form itself renders no built-in submit. Publish sits to its right.
    assert has_element?(view, ~s(button[form="forms-edit-form-form"]), "Save")
    refute view |> element("#forms-edit-form-form") |> render() =~ ">Save draft<"
    assert render(view) =~ ~r/Save\s*<\/button>.*Publish/s

    # Quiet while clean, primary once the form differs from what's persisted —
    # matching the flows editor's Save
    refute has_element?(view, ~s(button[form="forms-edit-form-form"].bg-cyan-600))

    view
    |> element("#forms-edit-form-form")
    |> render_change(%{"dynamic_form" => %{"name" => "Remote, edited", "definition" => "{}"}})

    assert has_element?(view, ~s(button[form="forms-edit-form-form"].bg-cyan-600))

    view
    |> element("#forms-edit-form-form")
    |> render_submit(%{"dynamic_form" => %{"name" => "Remote, edited", "definition" => "{}"}})

    assert render(view) =~ "Saved."
    refute has_element?(view, ~s(button[form="forms-edit-form-form"].bg-cyan-600))
  end

  test "opening a form node from the edit canvas stays in edit mode", %{conn: conn} do
    {root, node} = flow_with_form_node("Taxes 2026", "W-2 Details")
    [draft] = Forms.list_versions(node.form_id)

    {:ok, view, _html} = live(conn, "/admin/flows/#{root.id}/edit")

    view
    |> element("#flows-edit-editor")
    |> render_hook("form_flow:open_form", %{"node_id" => node.id})

    assert_redirect(
      view,
      "/admin/flows/#{root.id}/nodes/#{node.id}/form/versions/#{draft.id}/edit"
    )

    # With only a published version, a fresh draft is forked from it
    {:ok, _v1} = Forms.update_status(draft, :published)

    {:ok, view, _html} = live(conn, "/admin/flows/#{root.id}/edit")

    view
    |> element("#flows-edit-editor")
    |> render_hook("form_flow:open_form", %{"node_id" => node.id})

    {path, _flash} = assert_redirect(view)
    assert path =~ ~r{/form/versions/(.+)/edit$}

    [_, new_draft_id] = Regex.run(~r{/versions/([^/]+)/edit$}, path)
    new_draft = Forms.get_version(new_draft_id)
    assert new_draft.status == "draft"
    assert new_draft.based_on_version_id == draft.id
  end

  test "the edit page publishes too — directly the first time, dialog after",
       %{conn: conn} do
    {:ok, form} = Forms.create(%{name: "Publishable"})
    [draft] = Forms.list_versions(form.id)

    {:ok, view, _html} = live(conn, "/admin/forms/#{form.id}/versions/#{draft.id}/edit")

    view |> element("button", "Publish") |> render_click()

    assert_redirect(view, "/admin/forms/#{form.id}/versions/#{draft.id}")
    assert %{status: "published", version: 1} = Forms.get_version(draft.id)

    # Later publishes prompt, with the saved-definition caveat Edit needs
    {:ok, second} = Forms.create_draft(form.id, based_on: draft.id)
    {:ok, view, _html} = live(conn, "/admin/forms/#{form.id}/versions/#{second.id}/edit")

    view |> element("button", "Publish") |> render_click()
    assert render(view) =~ "Publish this draft?"
    assert render(view) =~ "unsaved edits are not included"

    view
    |> element("#forms-edit-publish-form-form")
    |> render_submit(%{"dynamic_form" => %{"preset" => "small_fix"}})

    assert_redirect(view, "/admin/forms/#{form.id}/versions/#{second.id}")
    assert %{status: "published", version: 2} = Forms.get_version(second.id)
  end

  test "only drafts render the editor", %{conn: conn} do
    {form, v1} = published_form()

    {:ok, _view, html} = live(conn, "/admin/forms/#{form.id}/versions/#{v1.id}/edit")

    assert html =~ "Only drafts can be edited"
  end

  test "the first publish skips the policy dialog — there is nobody to migrate",
       %{conn: conn} do
    {:ok, form} = Forms.create(%{name: "Publishable"})
    [draft] = Forms.list_versions(form.id)

    {:ok, view, _html} = live(conn, "/admin/forms/#{form.id}")

    view |> element("button", "Publish") |> render_click()

    assert_redirect(view, "/admin/forms/#{form.id}/versions/#{draft.id}")
    assert %{status: "published", version: 1} = Forms.get_version(draft.id)
  end

  test "every later publish prompts for the policy, archived history included",
       %{conn: conn} do
    {form, v1} = published_form()
    {:ok, _} = Forms.update_status(v1, :archived)
    {:ok, draft} = Forms.create_draft(form.id)

    {:ok, view, _html} = live(conn, "/admin/forms/#{form.id}/versions/#{draft.id}")

    view |> element("button", "Publish") |> render_click()
    assert render(view) =~ "Publish this draft?"

    view
    |> element("#forms-show-publish-form-form")
    |> render_submit(%{"dynamic_form" => %{"preset" => "small_fix"}})

    assert_redirect(view, "/admin/forms/#{form.id}/versions/#{draft.id}")
    assert %{status: "published", version: 2} = Forms.get_version(draft.id)
  end

  test "the big-fix preset passes through to the migration policy", %{conn: conn} do
    {form, v1} = published_form()

    {:ok, instance} =
      FormFlow.Data.Repo.insert(
        FormFlow.Data.Instances.Form.changeset(%FormFlow.Data.Instances.Form{}, %{
          template_form_version_id: v1.id,
          data: %{"name" => "Ada"}
        })
      )

    {:ok, draft} = Forms.create_draft(form.id, based_on: v1.id)

    {:ok, view, _html} = live(conn, "/admin/forms/#{form.id}/versions/#{draft.id}")

    view |> element("button", "Publish") |> render_click()
    assert render(view) =~ "Publish this draft?"

    view
    |> element("#forms-show-publish-form-form")
    |> render_submit(%{"dynamic_form" => %{"preset" => "big_fix"}})

    migrated = FormFlow.Data.Instances.Forms.get(instance.id)
    assert migrated.template_form_version_id == draft.id
    assert migrated.data == %{}
  end

  test "a published version offers a new draft, landing on its editor", %{conn: conn} do
    {form, _v1} = published_form()

    {:ok, view, _html} = live(conn, "/admin/forms/#{form.id}")

    view |> element("button", "New draft from this version") |> render_click()

    {path, _flash} = assert_redirect(view)
    assert path =~ ~r{^/admin/forms/#{form.id}/versions/.+/edit$}
  end

  test "archiving the latest published version falls back to the previous one",
       %{conn: conn} do
    {form, v1} = published_form()
    {:ok, draft} = Forms.create_draft(form.id, based_on: v1.id)
    {:ok, v2} = Forms.update_status(draft, :published)

    {:ok, view, _html} = live(conn, "/admin/forms/#{form.id}")
    assert render(view) =~ "v2 · published"

    view |> element("button", "Archive") |> render_click()
    assert_redirect(view, "/admin/forms/#{form.id}/versions/#{v2.id}")

    # The bare URL resolves latest published — v1 again
    {:ok, _view, html} = live(conn, "/admin/forms/#{form.id}")
    assert html =~ "v1 · published"
  end

  test "a draft can be deleted from its show page; published versions survive",
       %{conn: conn} do
    {form, v1} = published_form()
    {:ok, draft} = Forms.create_draft(form.id, based_on: v1.id)

    {:ok, view, html} = live(conn, "/admin/forms/#{form.id}/versions/#{draft.id}")

    # Delete draft sits left of the Show/Edit toggle, which sits left of Publish
    assert html =~ ~r/Delete draft.*Switch to Edit.*Publish/s

    view |> element("button", "Delete draft") |> render_click()

    assert_redirect(view, "/admin/forms/#{form.id}")
    assert Forms.get_version(draft.id) == nil
    assert Forms.get_version(v1.id).status == "published"

    # Published versions never offer the button
    {:ok, view, _html} = live(conn, "/admin/forms/#{form.id}/versions/#{v1.id}")
    refute has_element?(view, "button", "Delete draft")
  end

  test "a draft can be deleted from its edit page too", %{conn: conn} do
    {form, v1} = published_form()
    {:ok, draft} = Forms.create_draft(form.id, based_on: v1.id)

    {:ok, view, html} = live(conn, "/admin/forms/#{form.id}/versions/#{draft.id}/edit")

    assert html =~ ~r/Delete draft.*Switch to Show.*Save.*Publish/s

    view |> element("button", "Delete draft") |> render_click()

    assert_redirect(view, "/admin/forms/#{form.id}")
    assert Forms.get_version(draft.id) == nil
  end

  test "deleting a catalog form returns to the catalog", %{conn: conn} do
    {:ok, form} = Forms.create(%{name: "Mistake"})

    {:ok, view, _html} = live(conn, "/admin/forms/#{form.id}")

    view |> element(~s(button[phx-click="delete"])) |> render_click()

    assert_redirect(view, "/admin/forms")
    assert Forms.get(form.id) == nil
  end

  test "drill-in shows the form with a breadcrumb back to the root", %{conn: conn} do
    {root, node} = flow_with_form_node("Taxes 2026", "W-2 Details")

    {:ok, _view, html} = live(conn, "/admin/flows/#{root.id}/nodes/#{node.id}/form")

    assert html =~ "Taxes 2026"
    assert html =~ "W-2 Details"
    assert html =~ "draft"
  end

  test "drill-in edit shows the same full breadcrumb as show", %{conn: conn} do
    # The nested case: root flow → subflow → form node, reached by drill-in
    {:ok, root} = Graphs.create(%{name: "Taxes 2026", label: "subflows"})

    subflow_attrs = %{
      properties: %{
        "type" => "subflow",
        "data" => %{"label" => "Wages", "subflow_label" => "forms"}
      }
    }

    {:ok, _} = Graphs.update(root, %{nodes: [subflow_attrs]})
    [subflow_node] = Graphs.get(root.id).nodes

    child = Graphs.get(subflow_node.subflow_id)

    form_attrs = %{
      properties: %{"type" => "step", "data" => %{"label" => "W-2 Details", "kind" => "form"}}
    }

    {:ok, _} = Graphs.update(child, %{nodes: [form_attrs]})
    [form_node] = Graphs.get(child.id).nodes
    [draft] = Forms.list_versions(form_node.form_id)

    show_path = "/admin/flows/#{root.id}/nodes/#{form_node.id}/form"
    edit_path = "#{show_path}/versions/#{draft.id}/edit"

    for path <- [show_path, edit_path] do
      {:ok, _view, html} = live(conn, path)

      # Flows / Taxes 2026 / Wages / W-2 Details — the full trail on both pages
      assert html =~ "Taxes 2026", "missing root crumb on #{path}"
      assert html =~ "Wages", "missing subflow crumb on #{path}"
      assert html =~ "W-2 Details", "missing form name on #{path}"
    end
  end

  test "a form node's Open button navigates to the drill-in URL", %{conn: conn} do
    {root, node} = flow_with_form_node("Taxes 2026", "W-2 Details")

    {:ok, view, _html} = live(conn, "/admin/flows/#{root.id}")

    view
    |> element("#flows-show-editor")
    |> render_hook("form_flow:open_form", %{"node_id" => node.id})

    assert_redirect(view, "/admin/flows/#{root.id}/nodes/#{node.id}/form")
  end

  # --- helpers --------------------------------------------------------------

  defp published_form do
    {:ok, form} = Forms.create(%{name: "Form #{System.unique_integer([:positive])}"})
    [draft] = Forms.list_versions(form.id)
    {:ok, v1} = Forms.update_status(draft, :published)
    {form, v1}
  end

  defp flow_with_form_node(flow_name, form_label) do
    {:ok, graph} = Graphs.create(%{name: flow_name})

    node_attrs = %{
      properties: %{"type" => "step", "data" => %{"label" => form_label, "kind" => "form"}}
    }

    {:ok, _} = Graphs.update(graph, %{nodes: [node_attrs]})
    [node] = Graphs.get(graph.id).nodes

    {Graphs.get(graph.id), node}
  end
end
