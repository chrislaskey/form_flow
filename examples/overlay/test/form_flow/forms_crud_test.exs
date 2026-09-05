defmodule Demo.FormFlowFormsCrudTest do
  @moduledoc """
  Drives the forms CRUD pages end-to-end through the dedicated
  `live "/admin/*path", FormFlowLive.Admin` route (mounted with `base="/admin"`):
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

  alias FormFlow.Data.Templates.Flows
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
    {:ok, flow} = Flows.create()
    {:ok, _owned} = Forms.create(%{name: "Owned form", owner_flow_id: flow.id})

    {:ok, view, html} = live(conn, "/admin/forms")

    assert html =~ "Catalog form"
    refute html =~ "Owned form"
    assert has_element?(view, ~s(a[href="/admin/forms/#{form.id}"]), "Show")
  end

  test "show resolves the newest draft before anything is published", %{conn: conn} do
    {:ok, form} = Forms.create(%{name: "Unpublished"})

    {:ok, _view, html} = live(conn, "/admin/forms/#{form.id}")

    assert html =~ "draft"
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

  test "the new page generates a slug, or keeps the one typed", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/admin/forms/new")

    view
    |> element("#forms-new-form-form")
    |> render_submit(%{"dynamic_form" => %{"name" => "User Information"}})

    {path, _flash} = assert_redirect(view)
    assert "/admin/forms/" <> id = path
    assert Forms.get(id).slug == "user-inform"

    {:ok, view, _html} = live(conn, "/admin/forms/new")

    view
    |> element("#forms-new-form-form")
    |> render_submit(%{"dynamic_form" => %{"name" => "Anything", "slug" => "Chosen"}})

    {path, _flash} = assert_redirect(view)
    assert "/admin/forms/" <> id = path
    assert Forms.get(id).slug == "chosen"
  end

  test "Save writes the slug too, and a taken one is refused by name", %{conn: conn} do
    {:ok, _other} = Forms.create(%{name: "Other", slug: "taken"})
    {:ok, form} = Forms.create(%{name: "Mine"})
    [draft] = Forms.list_versions(form.id)

    {:ok, view, html} = live(conn, "/admin/forms/#{form.id}/versions/#{draft.id}/edit")
    assert html =~ "mine"

    # The save lands through send_update after the submit, so render the
    # view again rather than reading the submit's own response
    submit = fn slug ->
      view
      |> element("#forms-edit-form-form")
      |> render_submit(%{
        "dynamic_form" => %{"name" => "Mine", "slug" => slug, "definition" => ~s({"fields": []})}
      })

      render(view)
    end

    assert submit.("taken") =~ "The slug has already been taken."
    assert Forms.get(form.id).slug == "mine"

    assert submit.("mine2027") =~ "Saved."
    assert Forms.get(form.id).slug == "mine2027"
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

  test "picking a form_type persists it into the form's properties", %{conn: conn} do
    {:ok, form} = Forms.create(%{name: "Typed"})
    [draft] = Forms.list_versions(form.id)

    {:ok, view, html} = live(conn, "/admin/forms/#{form.id}/versions/#{draft.id}/edit")

    # The dropdown carries what the demo's Config enables — proof the
    # router's config attr reaches the form pages. No type picked, so none
    # of a type's property fields render yet
    assert html =~ "Form type"
    assert html =~ "Demo prefill"
    refute html =~ "Name to prefill"

    # Picking a type swaps in its properties' fields (FormFlow.Config.Property).
    # The swap lands through send_update after the change event, so render
    # the view again rather than reading the change's own response
    view
    |> element("#forms-edit-form-form")
    |> render_change(%{"dynamic_form" => %{"name" => "Typed", "form_type" => "demo_prefill"}})

    html = render(view)
    assert html =~ "Name to prefill"
    # A choice property renders as a select of its options
    assert html =~ ~s(<select)
    assert html =~ "Dr."
    # A related-form property has nothing to offer on a catalog form
    assert html =~ "Copy name from"
    assert html =~ "No earlier forms to choose from"

    view
    |> element("#forms-edit-form-form")
    |> render_submit(%{
      "dynamic_form" => %{
        "name" => "Typed",
        "form_type" => "demo_prefill",
        "property_name" => "Ada",
        "property_salutation" => "dr",
        "definition" => ~s({"elements": []})
      }
    })

    assert render(view) =~ "Saved."

    # The type and its property values, under the type's own key
    assert Forms.get(form.id).properties == %{
             "form_type" => "demo_prefill",
             "form_type_property_values" => %{"name" => "Ada", "salutation" => "dr"},
             "slug" => "typed"
           }

    # Show mode renders the stored type as its name, with its property values
    # — a choice by its label
    {:ok, _view, html} = live(conn, "/admin/forms/#{form.id}")
    assert html =~ "Demo prefill"
    assert html =~ "Name to prefill: Ada"
    assert html =~ "Salutation: Dr."

    # Picking "default" again removes the key — and the property values with
    # it — rather than pinning a value
    {:ok, view, _html} = live(conn, "/admin/forms/#{form.id}/versions/#{draft.id}/edit")

    view
    |> element("#forms-edit-form-form")
    |> render_submit(%{
      "dynamic_form" => %{
        "name" => "Typed",
        "form_type" => "",
        "definition" => ~s({"elements": []})
      }
    })

    assert Forms.get(form.id).properties == %{"slug" => "typed"}
  end

  test "a related-form property offers the forms earlier in the flow", %{conn: conn} do
    # Start → Intake → Review: editing Review's form, Intake is the only
    # earlier form; Review itself and nothing after it are offered
    {:ok, root} = Flows.create(%{name: "Onboarding"})
    start_node = build_node(root, ["Start"], "Start")
    {intake_form, _v1} = published_form()
    intake = build_node(root, ["Form"], "Intake", %{form_id: intake_form.id})
    {review_form, _v1} = published_form()
    review = build_node(root, ["Form"], "Review", %{form_id: review_form.id})
    edge(root, start_node, intake)
    edge(root, intake, review)
    {:ok, draft} = Forms.create_draft(review_form.id)

    {:ok, view, _html} =
      live(conn, "/admin/flows/#{root.id}/nodes/#{review.id}/form/versions/#{draft.id}/edit")

    view
    |> element("#forms-edit-form-form")
    |> render_change(%{"dynamic_form" => %{"name" => "Review", "form_type" => "demo_prefill"}})

    html = render(view)
    assert html =~ "Copy name from"
    assert html =~ ~s(value="#{intake.id}")
    assert html =~ "Intake"
    refute html =~ ~s(value="#{review.id}")
    refute html =~ "No earlier forms"

    view
    |> element("#forms-edit-form-form")
    |> render_submit(%{
      "dynamic_form" => %{
        "name" => "Review",
        "form_type" => "demo_prefill",
        "property_name" => "Ada",
        "property_source" => intake.id,
        "definition" => ~s({"elements": []})
      }
    })

    assert render(view) =~ "Saved."

    # The stored value is the chosen form's path — here one node deep
    assert Forms.get(review_form.id).properties["form_type_property_values"] == %{
             "name" => "Ada",
             "source" => intake.id
           }

    # Show renders it as the form's label
    {:ok, _view, html} = live(conn, "/admin/flows/#{root.id}/nodes/#{review.id}/form")
    assert html =~ "Copy name from: Intake"
  end

  test "a related-form value the flow no longer has is flagged, not hidden", %{conn: conn} do
    {:ok, root} = Flows.create(%{name: "Onboarding"})
    start_node = build_node(root, ["Start"], "Start")
    {review_form, _v1} = published_form()
    review = build_node(root, ["Form"], "Review", %{form_id: review_form.id})
    edge(root, start_node, review)

    # A value pointing at a node that isn't in the flow — rearranged, or
    # edited by hand; the cause doesn't matter
    {:ok, _form} =
      Forms.update(review_form, %{
        properties: %{
          "form_type" => "review",
          "form_type_property_values" => %{"source" => "gone"}
        }
      })

    {:ok, draft} = Forms.create_draft(review_form.id)

    {:ok, _view, html} =
      live(conn, "/admin/flows/#{root.id}/nodes/#{review.id}/form/versions/#{draft.id}/edit")

    assert html =~ "The saved choice is no longer in this flow"

    {:ok, _view, html} = live(conn, "/admin/flows/#{root.id}/nodes/#{review.id}/form")
    assert html =~ "Form to review: Missing — no longer in this flow"
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
    # the form itself renders no built-in submit. Publish sits to its right,
    # which is why the button says what it saves.
    assert has_element?(view, ~s(button[form="forms-edit-form-form"]), "Save draft")
    refute has_element?(view, ~s(#forms-edit-form-form button[type="submit"]))
    assert render(view) =~ ~r/Save draft\s*<\/button>.*Publish/s

    # Quiet (btn-soft) while clean, primary (no btn-soft) once the form
    # differs from what's persisted — matching the flows editor's Save
    assert has_element?(view, ~s(button[form="forms-edit-form-form"].btn-soft))

    view
    |> element("#forms-edit-form-form")
    |> render_change(%{"dynamic_form" => %{"name" => "Remote, edited", "definition" => "{}"}})

    refute has_element?(view, ~s(button[form="forms-edit-form-form"].btn-soft))

    view
    |> element("#forms-edit-form-form")
    |> render_submit(%{"dynamic_form" => %{"name" => "Remote, edited", "definition" => "{}"}})

    assert render(view) =~ "Saved."
    assert has_element?(view, ~s(button[form="forms-edit-form-form"].btn-soft))
  end

  test "opening a form node from the edit canvas lands on its show page, like the read-only canvas",
       %{conn: conn} do
    {root, node} = flow_with_form_node("Taxes 2026", "W-2 Details")

    {:ok, view, _html} = live(conn, "/admin/flows/#{root.id}/edit")

    view
    |> element("#flows-edit-editor")
    |> render_hook("form_flow:open_form", %{"node_id" => node.id})

    # `mode=edit` is the one thing that does cross this boundary — it tells
    # the form page's own breadcrumb to route Root and Parent back to their
    # editors, since that's where this click came from
    assert_redirect(view, "/admin/flows/#{root.id}/nodes/#{node.id}/form?mode=edit")

    # Stickiness ends at this boundary otherwise: Open is a read, not a
    # continuation of the canvas's own edit session, so it creates nothing
    assert length(Forms.list_versions(node.form_id)) == 1
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

    view |> element("button", "Archive version") |> render_click()
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

    # Delete draft sits left of Edit draft, which sits left of Publish
    assert html =~ ~r/Delete draft.*Edit draft.*Publish/s

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

    assert html =~ ~r/Delete draft.*Save.*Publish/s

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
    {root, _subflow_node, form_node} = nested_flow_with_form_node()
    [draft] = Forms.list_versions(form_node.form_id)

    show_path = "/admin/flows/#{root.id}/nodes/#{form_node.id}/form"
    edit_path = "#{show_path}/versions/#{draft.id}/edit"

    for path <- [show_path, edit_path] do
      {:ok, view, html} = live(conn, path)

      # Flows / Taxes 2026 / Wages / W-2 Details — the full trail on both pages
      assert html =~ "Taxes 2026", "missing root crumb on #{path}"
      assert html =~ "Wages", "missing subflow crumb on #{path}"
      assert html =~ "W-2 Details", "missing form name on #{path}"

      # Reached with no `mode`, Root is the ordinary show link
      assert has_element?(view, "a[href='/admin/flows/#{root.id}']", "Taxes 2026")
    end
  end

  test "opening a form node from a subflow's edit canvas points its breadcrumb back at both editors",
       %{conn: conn} do
    {root, subflow_node, form_node} = nested_flow_with_form_node()

    {:ok, view, _html} = live(conn, "/admin/flows/#{root.id}/nodes/#{subflow_node.id}/edit")

    view
    |> element("#flows-edit-editor")
    |> render_hook("form_flow:open_form", %{"node_id" => form_node.id})

    {show_path, _flash} = assert_redirect(view)
    assert show_path =~ "?mode=edit"

    {:ok, view, _html} = live(conn, show_path)
    assert has_element?(view, "a[href='/admin/flows/#{root.id}/edit']", "Taxes 2026")

    assert has_element?(
             view,
             "a[href='/admin/flows/#{root.id}/nodes/#{subflow_node.id}/edit']",
             "Wages"
           )

    # Edit draft carries the same query forward, so the editor's own
    # breadcrumb stays pointed at both editors too
    view |> element("a", "Edit draft") |> render_click()
    {edit_path, _flash} = assert_redirect(view)
    assert edit_path =~ "?mode=edit"

    {:ok, view, _html} = live(conn, edit_path)
    assert has_element?(view, "a[href='/admin/flows/#{root.id}/edit']", "Taxes 2026")

    assert has_element?(
             view,
             "a[href='/admin/flows/#{root.id}/nodes/#{subflow_node.id}/edit']",
             "Wages"
           )
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

  defp build_node(flow, labels, label, attrs \\ %{}) do
    attrs =
      Map.merge(
        %{flow_id: flow.id, labels: labels, properties: %{"data" => %{"label" => label}}},
        attrs
      )

    {:ok, node} =
      FormFlow.Data.Repo.insert(
        FormFlow.Data.Templates.Flow.Node.changeset(%FormFlow.Data.Templates.Flow.Node{}, attrs)
      )

    node
  end

  defp edge(flow, source, target) do
    {:ok, _relationship} =
      FormFlow.Data.Repo.insert(
        FormFlow.Data.Templates.Flow.Relationship.changeset(
          %FormFlow.Data.Templates.Flow.Relationship{},
          %{flow_id: flow.id, source_id: source.id, target_id: target.id, label: "CONNECTS_TO"}
        )
      )
  end

  defp published_form do
    {:ok, form} = Forms.create(%{name: "Form #{System.unique_integer([:positive])}"})
    [draft] = Forms.list_versions(form.id)
    {:ok, v1} = Forms.update_status(draft, :published)
    {form, v1}
  end

  defp flow_with_form_node(flow_name, form_label) do
    {:ok, flow} = Flows.create(%{name: flow_name})

    node_attrs = %{
      properties: %{"type" => "step", "data" => %{"label" => form_label, "kind" => "form"}}
    }

    {:ok, _} = Flows.update(flow, %{nodes: [node_attrs]})
    [node] = Flows.get(flow.id).nodes

    {Flows.get(flow.id), node}
  end

  # Root flow → subflow ("Wages") → form node ("W-2 Details"), reached by
  # drill-in — the nested case a breadcrumb has to walk back through
  defp nested_flow_with_form_node do
    {:ok, root} = Flows.create(%{name: "Taxes 2026", label: "subflows"})

    subflow_attrs = %{
      properties: %{
        "type" => "subflow",
        "data" => %{"label" => "Wages", "subflow_label" => "forms"}
      }
    }

    {:ok, _} = Flows.update(root, %{nodes: [subflow_attrs]})
    [subflow_node] = Flows.get(root.id).nodes
    child = Flows.get(subflow_node.subflow_id)

    form_attrs = %{
      properties: %{"type" => "step", "data" => %{"label" => "W-2 Details", "kind" => "form"}}
    }

    {:ok, _} = Flows.update(child, %{nodes: [form_attrs]})
    [form_node] = Flows.get(child.id).nodes

    {root, subflow_node, form_node}
  end
end
