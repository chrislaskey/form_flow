defmodule Demo.FormFlowFormsCrudTest do
  @moduledoc """
  Drives the forms CRUD pages end-to-end: `/forms` is the catalog,
  `/forms/new` creates a lineage with its initial draft, `/forms/:id` shows
  the resolved version (latest published, else newest draft) with the version
  history and the publish dialog, `/forms/:id/versions/:vid/edit` edits a
  draft, and `/flows/:root/nodes/:node_id/form` is the drill-in from a flow.

  The standalone pages ride the demo's `/*path` catch-all; drill-ins ride the
  dedicated `/flows/*path` page. The editor's React side can't run here, so
  the form node's Open button is driven by pushing the hook's event.
  """

  use DemoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias FormFlow.Data.Graphs
  alias FormFlow.Data.Templates.Forms

  test "the new page creates a lineage with its initial draft", %{conn: conn} do
    {:ok, view, html} = live(conn, "/forms/new")

    assert html =~ "New form"

    view
    |> element("#forms-new-form-form")
    |> render_submit(%{"dynamic_form" => %{"name" => "W-2 Details", "description" => "Wages"}})

    {path, _flash} = assert_redirect(view)
    assert "/forms/" <> id = path

    form = Forms.get(id)
    assert form.name == "W-2 Details"
    assert [%{status: "draft"}] = Forms.list_versions(id)
  end

  test "the catalog lists forms; owned forms never appear", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/forms")
    assert html =~ "No forms yet"

    {:ok, form} = Forms.create(%{name: "Catalog form"})
    {:ok, graph} = Graphs.create()
    {:ok, _owned} = Forms.create(%{name: "Owned form", owner_graph_id: graph.id})

    {:ok, view, html} = live(conn, "/forms")

    assert html =~ "Catalog form"
    refute html =~ "Owned form"
    assert has_element?(view, ~s(a[href="/forms/#{form.id}"]), "Show")
  end

  test "show resolves the newest draft before anything is published", %{conn: conn} do
    {:ok, form} = Forms.create(%{name: "Unpublished", definition: %{"wip" => true}})

    {:ok, _view, html} = live(conn, "/forms/#{form.id}")

    assert html =~ "draft"
    assert html =~ "wip"
  end

  test "editing a draft saves JSON and rejects bad syntax", %{conn: conn} do
    {:ok, form} = Forms.create(%{name: "Editable"})
    [draft] = Forms.list_versions(form.id)

    {:ok, view, html} = live(conn, "/forms/#{form.id}/versions/#{draft.id}/edit")

    assert html =~ "Definition (JSON)"

    view
    |> element("#forms-edit-form-form")
    |> render_submit(%{"dynamic_form" => %{"definition" => ~s({"fields": [{"name": "ssn"}]})}})

    assert render(view) =~ "Saved."
    assert Forms.get_version(draft.id).definition == %{"fields" => [%{"name" => "ssn"}]}

    view
    |> element("#forms-edit-form-form")
    |> render_submit(%{"dynamic_form" => %{"definition" => "{nope"}})

    assert render(view) =~ "is not valid JSON"
  end

  test "only drafts render the editor", %{conn: conn} do
    {form, v1} = published_form()

    {:ok, _view, html} = live(conn, "/forms/#{form.id}/versions/#{v1.id}/edit")

    assert html =~ "Only drafts can be edited"
  end

  test "publishing a draft through the dialog assigns v1", %{conn: conn} do
    {:ok, form} = Forms.create(%{name: "Publishable"})
    [draft] = Forms.list_versions(form.id)

    {:ok, view, _html} = live(conn, "/forms/#{form.id}")

    view |> element("button", "Publish") |> render_click()
    assert render(view) =~ "Publish this draft?"

    view
    |> element("#forms-show-publish-form-form")
    |> render_submit(%{"dynamic_form" => %{"preset" => "small_fix"}})

    assert_redirect(view, "/forms/#{form.id}/versions/#{draft.id}")
    assert %{status: "published", version: 1} = Forms.get_version(draft.id)
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

    {:ok, view, _html} = live(conn, "/forms/#{form.id}/versions/#{draft.id}")

    view |> element("button", "Publish") |> render_click()

    view
    |> element("#forms-show-publish-form-form")
    |> render_submit(%{"dynamic_form" => %{"preset" => "big_fix"}})

    migrated = FormFlow.Data.Instances.Forms.get(instance.id)
    assert migrated.template_form_version_id == draft.id
    assert migrated.data == %{}
  end

  test "a published version offers a new draft, landing on its editor", %{conn: conn} do
    {form, _v1} = published_form()

    {:ok, view, _html} = live(conn, "/forms/#{form.id}")

    view |> element("button", "New draft from this version") |> render_click()

    {path, _flash} = assert_redirect(view)
    assert path =~ ~r{^/forms/#{form.id}/versions/.+/edit$}
  end

  test "archiving the latest published version falls back to the previous one",
       %{conn: conn} do
    {form, v1} = published_form()
    {:ok, draft} = Forms.create_draft(form.id, based_on: v1.id)
    {:ok, v2} = Forms.update_status(draft, :published)

    {:ok, view, _html} = live(conn, "/forms/#{form.id}")
    assert render(view) =~ "v2 · published"

    view |> element("button", "Archive") |> render_click()
    assert_redirect(view, "/forms/#{form.id}/versions/#{v2.id}")

    # The bare URL resolves latest published — v1 again
    {:ok, _view, html} = live(conn, "/forms/#{form.id}")
    assert html =~ "v1 · published"
  end

  test "deleting a catalog form returns to the catalog", %{conn: conn} do
    {:ok, form} = Forms.create(%{name: "Mistake"})

    {:ok, view, _html} = live(conn, "/forms/#{form.id}")

    view |> element("button", "Delete") |> render_click()

    assert_redirect(view, "/forms")
    assert Forms.get(form.id) == nil
  end

  test "drill-in shows the form with a breadcrumb back to the root", %{conn: conn} do
    {root, node} = flow_with_form_node("Taxes 2026", "W-2 Details")

    {:ok, _view, html} = live(conn, "/flows/#{root.id}/nodes/#{node.id}/form")

    assert html =~ "Taxes 2026"
    assert html =~ "W-2 Details"
    assert html =~ "draft"
  end

  test "a form node's Open button navigates to the drill-in URL", %{conn: conn} do
    {root, node} = flow_with_form_node("Taxes 2026", "W-2 Details")

    {:ok, view, _html} = live(conn, "/flows/#{root.id}")

    view
    |> element("#flows-show-editor")
    |> render_hook("form_flow:open_form", %{"node_id" => node.id})

    assert_redirect(view, "/flows/#{root.id}/nodes/#{node.id}/form")
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
