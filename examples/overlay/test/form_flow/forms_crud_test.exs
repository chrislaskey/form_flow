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

    # Past the never-published-and-blank chooser, straight to the form
    {:ok, view, html} =
      live(conn, "/admin/forms/#{form.id}/versions/#{draft.id}/edit?start=custom")

    # A blank draft opens in the form builder; the JSON field is the radio's
    # other choice, and a submit that names it is a submit as JSON
    assert has_element?(view, ~s(input[name="dynamic_form[definition_editor]"][value="json"]))
    assert html =~ "Add element"
    refute html =~ "Definition (JSON)"

    view
    |> element("#forms-edit-form-form")
    |> render_submit(%{
      "dynamic_form" => %{
        "name" => "Editable",
        "definition_editor" => "json",
        "definition" => ~s({"fields": [{"name": "ssn"}]})
      }
    })

    assert render(view) =~ "Saved."
    assert Forms.get_version(draft.id).definition == %{"fields" => [%{"name" => "ssn"}]}

    view
    |> element("#forms-edit-form-form")
    |> render_submit(%{
      "dynamic_form" => %{
        "name" => "Editable",
        "definition_editor" => "json",
        "definition" => "{nope"
      }
    })

    assert render(view) =~ "is not valid JSON"
  end

  test "the form builder saves its entries as the definition's elements", %{conn: conn} do
    {:ok, form} = Forms.create(%{name: "Built"})
    [draft] = Forms.list_versions(form.id)

    {:ok, view, _html} =
      live(conn, "/admin/forms/#{form.id}/versions/#{draft.id}/edit?start=custom")

    # Entries arrive as the browser sends a nested form: indexed, with the
    # entry fields named after the SurveyJS properties they set. Choices are
    # one per line; a property that doesn't apply to the type (a text
    # element's choices) is left out of the JSON.
    view
    |> element("#forms-edit-form-form")
    |> render_submit(%{
      "dynamic_form" => %{
        "name" => "Built",
        "definition_editor" => "form",
        "elements" => %{
          "0" => %{
            "type" => "text",
            "name" => "email",
            "title" => "Email",
            "inputType" => "email",
            "isRequired" => "true",
            "choices" => "left over"
          },
          "1" => %{
            "type" => "dropdown",
            "name" => "subject",
            "choices" => "Sales\nsupport | Support"
          }
        }
      }
    })

    assert render(view) =~ "Saved."

    assert Forms.get_version(draft.id).definition == %{
             "elements" => [
               %{
                 "type" => "text",
                 "name" => "email",
                 "title" => "Email",
                 "inputType" => "email",
                 "isRequired" => true
               },
               %{
                 "type" => "dropdown",
                 "name" => "subject",
                 "choices" => ["Sales", %{"value" => "support", "text" => "Support"}]
               }
             ]
           }

    # Two elements can't share a name — the nested form's key — and every
    # element needs a type and a name. The preview follows the builder as
    # faithfully as it follows the JSON, duplicate names included, and two
    # fields with one name are two inputs with one id — fine in a browser,
    # an error to LiveViewTest — so it is left out of this step.
    view |> element(~s(button[phx-click="toggle_auto_update"])) |> render_click()

    view
    |> element("#forms-edit-form-form")
    |> render_submit(%{
      "dynamic_form" => %{
        "name" => "Built",
        "definition_editor" => "form",
        "elements" => %{
          "0" => %{"type" => "text", "name" => "email"},
          "1" => %{"type" => "text", "name" => "email"},
          "2" => %{"type" => "", "name" => ""}
        }
      }
    })

    html = render(view)
    assert html =~ "is already used by another element"
    assert html =~ "can&#39;t be blank"
    refute html =~ "Saved."
  end

  test "an element's arrows move it up and down the builder", %{conn: conn} do
    {:ok, form} =
      Forms.create(%{
        name: "Ordered",
        definition: %{
          "elements" => [
            %{"type" => "text", "name" => "first"},
            %{"type" => "text", "name" => "second"},
            %{"type" => "text", "name" => "third"}
          ]
        }
      })

    [draft] = Forms.list_versions(form.id)
    {:ok, view, _html} = live(conn, "/admin/forms/#{form.id}/versions/#{draft.id}/edit")

    assert has_element?(view, ~s(input[name="dynamic_form[elements][0][name]"][value="first"]))
    assert has_element?(view, ~s(button[aria-label="Move up"][disabled]))

    # The arrow writes "up" into the entry's move field and fires the form's
    # change; the page reorders and hands the entries back as the form's data
    view
    |> element("#forms-edit-form-form")
    |> render_change(%{
      "dynamic_form" => %{
        "elements" => %{
          "0" => %{"type" => "text", "name" => "first"},
          "1" => %{"type" => "text", "name" => "second", "move" => "up"},
          "2" => %{"type" => "text", "name" => "third"}
        }
      }
    })

    render(view)
    assert has_element?(view, ~s(input[name="dynamic_form[elements][0][name]"][value="second"]))
    assert has_element?(view, ~s(input[name="dynamic_form[elements][1][name]"][value="first"]))
    assert has_element?(view, ~s(input[name="dynamic_form[elements][2][name]"][value="third"]))

    # Saved in the new order, with nothing of the request in the JSON
    view
    |> element("#forms-edit-form-form")
    |> render_submit(%{"dynamic_form" => %{"name" => "Ordered", "definition_editor" => "form"}})

    assert render(view) =~ "Saved."

    assert Enum.map(Forms.get_version(draft.id).definition["elements"], & &1["name"]) ==
             ["second", "first", "third"]

    refute Forms.get_version(draft.id).definition |> inspect() =~ "move"
  end

  test "a group and a nested form hold elements inside them", %{conn: conn} do
    {:ok, form} = Forms.create(%{name: "Nested"})
    [draft] = Forms.list_versions(form.id)

    {:ok, view, _html} =
      live(conn, "/admin/forms/#{form.id}/versions/#{draft.id}/edit?start=custom")

    submit = fn elements ->
      view
      |> element("#forms-edit-form-form")
      |> render_submit(%{
        "dynamic_form" => %{
          "name" => "Nested",
          "definition_editor" => "form",
          "elements" => elements
        }
      })

      render(view)
    end

    # A group's members are written as its elements, a nested form's as its
    # template — one level deep, each as the same kind of entry
    html =
      submit.(%{
        "0" => %{
          "type" => "panel",
          "name" => "address",
          "title" => "Address",
          "groupType" => "vertical",
          "children" => %{
            "0" => %{"type" => "text", "name" => "street"},
            "1" => %{"type" => "text", "name" => "city", "isRequired" => "true"}
          }
        },
        "1" => %{
          "type" => "paneldynamic",
          "name" => "phones",
          "templateTitle" => "Phone {panelIndex}",
          "minPanelCount" => "1",
          "children" => %{"0" => %{"type" => "text", "name" => "number", "inputType" => "tel"}}
        }
      })

    assert html =~ "Saved."

    assert Forms.get_version(draft.id).definition == %{
             "elements" => [
               %{
                 "type" => "panel",
                 "name" => "address",
                 "title" => "Address",
                 "groupType" => "vertical",
                 "elements" => [
                   %{"type" => "text", "name" => "street"},
                   %{"type" => "text", "name" => "city", "isRequired" => true}
                 ]
               },
               %{
                 "type" => "paneldynamic",
                 "name" => "phones",
                 "templateTitle" => "Phone {panelIndex}",
                 "minPanelCount" => 1,
                 "templateElements" => [
                   %{"type" => "text", "name" => "number", "inputType" => "tel"}
                 ]
               }
             ]
           }

    # Reopened, the members show inside their container's entry, with the
    # container types on offer at the form level only
    {:ok, view, _html} = live(conn, "/admin/forms/#{form.id}/versions/#{draft.id}/edit")

    assert has_element?(
             view,
             ~s(input[name="dynamic_form[elements][0][children][1][name]"][value="city"])
           )

    assert has_element?(
             view,
             ~s(select[name="dynamic_form[elements][0][type]"] option[value="panel"])
           )

    refute has_element?(
             view,
             ~s(select[name="dynamic_form[elements][0][children][0][type]"] option[value="panel"])
           )

    # A group's member shares the form's scope, so it can't repeat a name
    # outside the group; a nested form's template is a scope of its own
    html =
      submit.(%{
        "0" => %{"type" => "text", "name" => "city"},
        "1" => %{
          "type" => "panel",
          "name" => "address",
          "children" => %{"0" => %{"type" => "text", "name" => "city"}}
        }
      })

    assert html =~ "uses the same name more than once: city"
    refute html =~ "Saved."
  end

  test "switching editors moves the definition across, and refuses what the builder can't show",
       %{conn: conn} do
    {:ok, form} =
      Forms.create(%{
        name: "Hand-written",
        definition: %{"elements" => [%{"type" => "text", "name" => "ssn", "readOnly" => true}]}
      })

    [draft] = Forms.list_versions(form.id)

    {:ok, view, html} = live(conn, "/admin/forms/#{form.id}/versions/#{draft.id}/edit")

    # readOnly has no control in the builder, so this one opens as JSON
    assert html =~ "Definition (JSON)"
    refute html =~ "Add element"

    assert has_element?(
             view,
             ~s(input[name="dynamic_form[definition_editor]"][value="json"][checked])
           )

    # Asking for the builder is refused, by name, and the radio snaps back
    # The page reacts to the change through a send_update the component
    # handles after the change event replies, so read the page afterwards
    switch = fn params ->
      view |> element("#forms-edit-form-form") |> render_change(%{"dynamic_form" => params})
      render(view)
    end

    html = switch.(%{"definition_editor" => "form"})
    assert html =~ ~s(Element &quot;ssn&quot; uses &quot;readOnly&quot;)

    assert has_element?(
             view,
             ~s(input[name="dynamic_form[definition_editor]"][value="json"][checked])
           )

    html = switch.(%{"definition_editor" => "form", "definition" => "{nope"})
    assert html =~ "Fix the JSON syntax before switching to the form builder."

    assert has_element?(
             view,
             ~s(input[name="dynamic_form[definition_editor]"][value="json"][checked])
           )

    # Once the JSON is something the builder can show, the switch decodes it
    # into one entry per element
    _html =
      switch.(%{
        "definition_editor" => "form",
        "definition" =>
          ~s({"title": "Kept", "elements": [{"type": "text", "name": "ssn", "isRequired": true}]})
      })

    assert has_element?(view, ~s(input[name="dynamic_form[elements][0][name]"][value="ssn"]))
    assert has_element?(view, ~s(input[name="dynamic_form[elements][0][isRequired]"][checked]))
    refute render(view) =~ "Definition (JSON)"

    # And switching back writes the entries into the JSON — the rest of the
    # document, its title here, untouched
    html =
      switch.(%{
        "definition_editor" => "json",
        "elements" => %{
          "0" => %{"type" => "text", "name" => "ssn"},
          "1" => %{"type" => "boolean", "name" => "consent", "title" => "I agree"}
        }
      })

    assert html =~ "Definition (JSON)"
    assert html =~ ~s(&quot;title&quot;: &quot;Kept&quot;)
    assert html =~ ~s(&quot;name&quot;: &quot;consent&quot;)
    refute html =~ "Add element"
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

    {:ok, view, html} =
      live(conn, "/admin/forms/#{form.id}/versions/#{draft.id}/edit?start=custom")

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

    {:ok, view, _html} =
      live(conn, "/admin/forms/#{form.id}/versions/#{draft.id}/edit?start=custom")

    view
    |> element("#forms-edit-form-form")
    |> render_submit(%{
      "dynamic_form" => %{
        "name" => "After",
        "description" => "New description",
        "definition_editor" => "json",
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

    {:ok, view, html} =
      live(conn, "/admin/forms/#{form.id}/versions/#{draft.id}/edit?start=custom")

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

    # Auto-refresh defaults on, and DynamicForm debounces its change pass
    # while it's on (`change_debounce_in_ms`) — the property swap lands
    # through that same debounced pass, so it isn't there to read yet
    Process.sleep(520)
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

  test "a blank, never-published draft offers the copy-or-custom chooser; anything else doesn't",
       %{conn: conn} do
    {:ok, form} = Forms.create(%{name: "Fresh"})
    [draft] = Forms.list_versions(form.id)

    {:ok, _view, html} = live(conn, "/admin/forms/#{form.id}/versions/#{draft.id}/edit")
    assert html =~ "Start this form from"
    assert html =~ "Custom form"
    assert html =~ "Copy form"

    # A definition already typed in — even once nothing has been published —
    # is something a copy would overwrite, so the chooser stops offering
    {:ok, _} = Forms.update_draft(draft, %{definition: %{"fields" => []}})
    {:ok, _view, html} = live(conn, "/admin/forms/#{form.id}/versions/#{draft.id}/edit")
    refute html =~ "Start this form from"

    # Publishing is the other way out, regardless of the definition
    {:ok, _} = Forms.update_draft(draft, %{definition: %{}})
    {:ok, _v1} = Forms.update_status(draft, :published)
    {:ok, new_draft} = Forms.create_draft(form.id, based_on: draft.id)
    {:ok, _view, html} = live(conn, "/admin/forms/#{form.id}/versions/#{new_draft.id}/edit")
    refute html =~ "Start this form from"
  end

  test "the chooser is the only thing on the page until a choice is made", %{conn: conn} do
    {:ok, form} = Forms.create(%{name: "Fresh"})
    [draft] = Forms.list_versions(form.id)

    {:ok, view, html} = live(conn, "/admin/forms/#{form.id}/versions/#{draft.id}/edit")

    assert html =~ "Start this form from"
    refute has_element?(view, "#forms-edit-form-form")
    refute has_element?(view, "button", "Publish")
    refute html =~ "Definition (JSON)"

    # Custom form is the default selection; Select is what commits it
    view
    |> element(~s(button[phx-click="select_custom"]))
    |> render_click()

    assert_redirect(view, "/admin/forms/#{form.id}/versions/#{draft.id}/edit?start=custom")

    {:ok, view, html} =
      live(conn, "/admin/forms/#{form.id}/versions/#{draft.id}/edit?start=custom")

    refute html =~ "Start this form from"
    assert has_element?(view, "#forms-edit-form-form")
    assert has_element?(view, "button", "Publish")

    # Nothing about the form or draft changed — Custom form is a no-op
    assert Forms.get_version(draft.id).definition == %{}
  end

  test "Copy form writes the source's identity and definition, keeping this form's own slug",
       %{conn: conn} do
    {:ok, source} =
      Forms.create(%{
        name: "Source Form",
        description: "The original",
        definition: %{"fields" => [%{"name" => "ssn"}]}
      })

    [source_draft] = Forms.list_versions(source.id)
    {:ok, _v1} = Forms.update_status(source_draft, :published)
    {:ok, source} = Forms.update(source, %{properties: %{"form_type" => "demo_prefill"}})

    {root, node} = flow_with_form_node("Taxes 2026", "W-2 Details")
    dest = Forms.get(node.form_id)
    [dest_draft] = Forms.list_versions(dest.id)

    {:ok, view, _html} =
      live(conn, "/admin/flows/#{root.id}/nodes/#{node.id}/form/versions/#{dest_draft.id}/edit")

    view
    |> element("input[type=radio][value=copy]")
    |> render_click(%{"selection" => "copy"})

    # The option shows the slug alongside the name, so two forms with the
    # same display name are still tellable apart in the dropdown
    assert render(view) =~ "Source Form · #{source.slug}"

    view
    |> element("#forms-edit-chooser-copy")
    |> render_change(%{"source_form_id" => source.id})

    view
    |> element(~s(button[phx-click="copy_form"]))
    |> render_click()

    updated = Forms.get(dest.id)
    assert updated.name == "Source Form"
    assert updated.description == "The original"
    assert updated.slug == "taxes-2026_w2-details"
    assert updated.properties["form_type"] == "demo_prefill"

    assert Forms.get_version(dest_draft.id).definition == %{"fields" => [%{"name" => "ssn"}]}

    # The chooser served its purpose — a copy is content, so it stops offering
    html = render(view)
    refute html =~ "Start this form from"
  end

  test "Copy definition, under the JSON field, works any time and touches only the definition",
       %{conn: conn} do
    {:ok, source} =
      Forms.create(%{name: "Source Form", definition: %{"fields" => [%{"name" => "ssn"}]}})

    [source_draft] = Forms.list_versions(source.id)
    {:ok, _v1} = Forms.update_status(source_draft, :published)

    {form, v1} = published_form()
    {:ok, draft} = Forms.create_draft(form.id, based_on: v1.id)

    {:ok, view, html} = live(conn, "/admin/forms/#{form.id}/versions/#{draft.id}/edit")

    # Already published, so the main chooser doesn't offer itself — Copy
    # definition isn't gated by that at all. It belongs to the JSON editor,
    # though: the blank draft opens in the form builder, where it is hidden
    refute html =~ "Start this form from"
    refute html =~ "Copy definition from existing form"

    view
    |> element("#forms-edit-form-form")
    |> render_change(%{"dynamic_form" => %{"definition_editor" => "json"}})

    assert render(view) =~ "Copy definition from existing form"

    view
    |> element("#forms-edit-definition-copy")
    |> render_change(%{"source_form_id" => source.id})

    view
    |> element(~s(button[phx-click="copy_definition"]))
    |> render_click()

    updated = Forms.get(form.id)
    assert updated.name == form.name
    assert updated.description == form.description
    assert updated.slug == form.slug
    assert Forms.get_version(draft.id).definition == %{"fields" => [%{"name" => "ssn"}]}
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

    # Auto-refresh defaults on, and DynamicForm debounces its change pass
    # while it's on — the property swap lands through that same debounced
    # pass, so it isn't there to read yet
    Process.sleep(520)
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

    {:ok, view, _html} =
      live(conn, "/admin/forms/#{form.id}/versions/#{draft.id}/edit?start=custom")

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

  test "opening a never-published form node from the edit canvas lands straight on its editor",
       %{conn: conn} do
    {root, node} = flow_with_form_node("Taxes 2026", "W-2 Details")
    [draft] = Forms.list_versions(node.form_id)

    {:ok, view, _html} = live(conn, "/admin/flows/#{root.id}/edit")

    view
    |> element("#flows-edit-editor")
    |> render_hook("form_flow:open_form", %{"node_id" => node.id})

    # Nothing has ever been published, so there's nothing on Show worth
    # seeing yet — Open lands straight on the node's own (sole) draft,
    # exactly as it would have landed on a fresh "Save & Continue"
    assert_redirect(
      view,
      "/admin/flows/#{root.id}/nodes/#{node.id}/form/versions/#{draft.id}/edit?mode=edit"
    )

    # And it creates nothing to get there — the same draft as before the click
    assert length(Forms.list_versions(node.form_id)) == 1
  end

  test "opening a form node from the edit canvas lands on its show page once it has been published",
       %{conn: conn} do
    {root, node} = flow_with_form_node("Taxes 2026", "W-2 Details")
    [draft] = Forms.list_versions(node.form_id)
    {:ok, _v1} = Forms.update_status(draft, :published)

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

    {:ok, view, _html} =
      live(conn, "/admin/forms/#{form.id}/versions/#{draft.id}/edit?start=custom")

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

  test "Delete draft is hidden when a draft is the form's only version", %{conn: conn} do
    {:ok, form} = Forms.create(%{name: "Solo"})
    [draft] = Forms.list_versions(form.id)

    {:ok, _view, html} = live(conn, "/admin/forms/#{form.id}")
    refute html =~ "Delete draft"

    {:ok, _view, html} = live(conn, "/admin/forms/#{form.id}/versions/#{draft.id}/edit")
    refute html =~ "Delete draft"

    # A second version — draft or published, doesn't matter which — is what
    # brings the button back
    {:ok, _other_draft} = Forms.create_draft(form.id)

    {:ok, _view, html} = live(conn, "/admin/forms/#{form.id}/versions/#{draft.id}")
    assert html =~ "Delete draft"
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
    [draft] = Forms.list_versions(form_node.form_id)
    {:ok, _v1} = Forms.update_status(draft, :published)

    {:ok, view, _html} = live(conn, "/admin/flows/#{root.id}/nodes/#{subflow_node.id}/edit")

    view
    |> element("#flows-edit-editor")
    |> render_hook("form_flow:open_form", %{"node_id" => form_node.id})

    # Published, so this lands on Show rather than the never-published
    # shortcut straight to the editor
    assert_redirect(view, "/admin/flows/#{root.id}/nodes/#{form_node.id}/form?mode=edit")

    {:ok, view, _html} =
      live(conn, "/admin/flows/#{root.id}/nodes/#{form_node.id}/form?mode=edit")

    assert has_element?(view, "a[href='/admin/flows/#{root.id}/edit']", "Taxes 2026")

    assert has_element?(
             view,
             "a[href='/admin/flows/#{root.id}/nodes/#{subflow_node.id}/edit']",
             "Wages"
           )

    # "New draft from this version" carries the same query forward, so the
    # editor's own breadcrumb stays pointed at both editors too
    view |> element("button", "New draft from this version") |> render_click()
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

  test "opening a never-published form node from a nested edit canvas lands straight on its editor",
       %{conn: conn} do
    {root, subflow_node, form_node} = nested_flow_with_form_node()

    {:ok, view, _html} = live(conn, "/admin/flows/#{root.id}/nodes/#{subflow_node.id}/edit")

    view
    |> element("#flows-edit-editor")
    |> render_hook("form_flow:open_form", %{"node_id" => form_node.id})

    {edit_path, _flash} = assert_redirect(view)
    assert edit_path =~ ~r{/versions/[^/]+/edit\?mode=edit$}

    {:ok, view, _html} = live(conn, edit_path)
    assert has_element?(view, "a[href='/admin/flows/#{root.id}/edit']", "Taxes 2026")

    assert has_element?(
             view,
             "a[href='/admin/flows/#{root.id}/nodes/#{subflow_node.id}/edit']",
             "Wages"
           )

    # Nothing was created to make this possible — this is the node's own
    # initial draft
    assert length(Forms.list_versions(form_node.form_id)) == 1
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
