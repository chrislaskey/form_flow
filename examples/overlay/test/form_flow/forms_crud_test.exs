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

  # /admin is the admin experience
  @moduletag user: "admin"

  import Phoenix.LiveViewTest

  alias FormFlow.Data.Instances
  alias FormFlow.Data.Templates.Flows
  alias FormFlow.Data.Templates.Flows.Health
  alias FormFlow.Data.Templates.Forms

  test "the admin root is a generic landing linking both indexes", %{conn: conn} do
    {:ok, view, html} = live(conn, "/admin")

    assert html =~ "Templates"
    assert has_element?(view, "h2", "Form Flow")
    assert has_element?(view, ~s(a[href="/admin/flows"]), "Flows")
    assert has_element?(view, ~s(a[href="/admin/forms"]), "Forms")
  end

  test "breadcrumbs lead back to the landing from inside both sections", %{conn: conn} do
    for path <- ["/admin/forms", "/admin/flows", "/admin/forms/new", "/admin/flows/new"] do
      {:ok, view, _html} = live(conn, path)

      assert has_element?(view, ~s(a[href="/admin"]), "Form Flow"),
             "missing Form Flow root crumb on #{path}"
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
    # other choice, and a submit that names it is a submit as JSON. With no
    # other form to copy from, Copy existing form isn't offered
    assert has_element?(view, ~s(input[name="dynamic_form[definition_editor]"][value="json"]))
    refute has_element?(view, ~s(input[name="dynamic_form[definition_editor]"][value="copy"]))
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

    # Add element must not also submit the form — a button with no type is a
    # submit button, and a click would silently save the draft
    assert has_element?(view, ~s(button[type="button"][phx-click="add_nested_entry"]))

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

  test "a catalog form cannot be pointed at a step; the copy is the way", %{conn: conn} do
    {:ok, shared} = Forms.create(%{name: "Check owner", properties: %{"form_type" => "review"}})
    {:ok, flow} = Flows.create(%{name: "Intake"})

    about = %{properties: %{"type" => "step", "data" => %{"label" => "About", "kind" => "form"}}}

    check = %{
      form_id: shared.id,
      properties: %{"type" => "step", "data" => %{"label" => "Check", "kind" => "form"}}
    }

    {:ok, _} = Flows.update(flow, %{nodes: [about, check]})
    about_node = Enum.find(Flows.get(flow.id).nodes, &(&1.form_id != shared.id))
    check_node = Enum.find(Flows.get(flow.id).nodes, &(&1.form_id == shared.id))
    [draft] = Forms.list_versions(shared.id)

    {:ok, view, _html} =
      live(
        conn,
        "/admin/flows/#{flow.id}/nodes/#{check_node.id}/form/versions/#{draft.id}/edit?start=custom"
      )

    view
    |> element("#forms-edit-form-form")
    |> render_submit(%{
      "dynamic_form" => %{
        "name" => "Check owner",
        "form_type" => "review",
        "property_source" => about_node.id,
        "definition" => ~s({"elements": []})
      }
    })

    # The save lands through send_update, so the page is read after it
    html = render(view)
    assert html =~ "is shared by every flow that uses it"
    assert html =~ "Copy the form into this flow instead"
    refute Map.has_key?(Forms.get(shared.id).properties, "form_type_property_values")
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
    # router's config attr reaches the form pages. Nothing saved yet, so it
    # shows the first type the page offers — the one the form would be
    # governed by anyway — and none of another type's property fields
    assert html =~ "Form type"
    assert html =~ "Demo prefill"

    assert has_element?(
             view,
             ~s(select[name="dynamic_form[form_type]"] option[value="default"][selected])
           )

    refute has_element?(view, ~s(select[name="dynamic_form[form_type]"] option[value=""]))
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

    # The type is required: a blank is refused, and picking the first type
    # again saves it explicitly, its property values gone with the old type
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

    assert render(view) =~ "can&#39;t be blank"
    assert Forms.get(form.id).properties["form_type"] == "demo_prefill"

    view
    |> element("#forms-edit-form-form")
    |> render_submit(%{
      "dynamic_form" => %{
        "name" => "Typed",
        "form_type" => "default",
        "definition" => ~s({"elements": []})
      }
    })

    assert render(view) =~ "Saved."
    assert Forms.get(form.id).properties == %{"form_type" => "default", "slug" => "typed"}
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

  test "Copy form writes the source's description, type, and definition, keeping this form's own name and slug",
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

    # The option says where the form comes from, and ends with its slug, so
    # two forms with the same display name are still tellable apart
    assert render(view) =~ "Reusable form - Source Form (#{source.slug})"

    view
    |> element("#forms-edit-chooser-copy")
    |> render_change(%{"source_form_id" => source.id})

    view
    |> element(~s(button[phx-click="copy_form"]))
    |> render_click()

    # The step keeps its own name — a copy brings content, not identity — so
    # the node's label and its owned form's name stay one value
    updated = Forms.get(dest.id)
    assert updated.name == "W-2 Details"
    assert updated.description == "The original"
    assert updated.slug == nil
    assert Flows.get_node(node.id).slug == "taxes-2026_w2-details"
    assert updated.properties["form_type"] == "demo_prefill"

    assert Forms.get_version(dest_draft.id).definition == %{"fields" => [%{"name" => "ssn"}]}

    # The chooser served its purpose — a copy is content, so it stops offering
    html = render(view)
    refute html =~ "Start this form from"
  end

  describe "reusing a catalog form" do
    # Dog License and Cat License share the catalog's Owner contact: one
    # lineage, two steps pointing at it, each flow's step label its own.
    test "the chooser's Reuse form: through a step only, the catalog alone, unpublished forms marked, landing on the step's form page",
         %{conn: conn} do
      {owner, _v1} = published_catalog("Owner contact")
      {:ok, unpublished} = Forms.create(%{name: "License options"})

      {:ok, _review} =
        Forms.create(%{name: "Check owner", properties: %{"form_type" => "review"}})

      {_other_root, _other_node} = flow_with_form_node("Other flow", "Private form")

      # Standalone, a catalog form's own draft has nothing to repoint
      [unpublished_draft] = Forms.list_versions(unpublished.id)

      {:ok, _view, html} =
        live(conn, "/admin/forms/#{unpublished.id}/versions/#{unpublished_draft.id}/edit")

      assert html =~ "Start this form from"
      refute html =~ "Reuse form"

      {root, node} = flow_with_form_node("Dog License", "Owner contact")
      own = Forms.get(node.form_id)
      [own_draft] = Forms.list_versions(own.id)

      {:ok, view, html} =
        live(conn, "/admin/flows/#{root.id}/nodes/#{node.id}/form/versions/#{own_draft.id}/edit")

      assert html =~ "Reuse form"

      view
      |> element("input[type=radio][value=reuse]")
      |> render_click(%{"selection" => "reuse"})

      # The catalog alone: never an owned form, never a form whose type ties
      # it to one flow; a form nobody could start yet says so
      html = render(view)
      assert html =~ "Owner contact (#{owner.slug})"
      assert html =~ "License options (#{unpublished.slug}) — draft, never published"
      refute html =~ "Check owner"
      refute html =~ "Private form"

      view
      |> element("#forms-edit-chooser-reuse")
      |> render_change(%{"source_form_id" => owner.id})

      # The confirmation says what goes
      assert has_element?(
               view,
               ~s|button[phx-click="reuse_form"][data-confirm*="“#{own.name}” is deleted"]|
             )

      view |> element(~s(button[phx-click="reuse_form"])) |> render_click()

      # This URL named the deleted draft; the step's form page is where to be
      assert_redirect(view, "/admin/flows/#{root.id}/nodes/#{node.id}/form")
      assert Flows.get_node(node.id).form_id == owner.id
      assert Forms.get(own.id) == nil

      # Which now resolves the catalog form — published, so no chooser
      {:ok, _view, html} = live(conn, "/admin/flows/#{root.id}/nodes/#{node.id}/form")
      assert html =~ "Catalog form"
      assert html =~ "used in Dog License"
    end

    test "the badge names every flow using the form and how to stop; the catalog says where it is used",
         %{conn: conn} do
      {owner, _v1} = published_catalog("Owner contact")
      {dog, dog_node} = flow_with_catalog_form_node("Dog License", owner)
      {_cat, _cat_node} = flow_with_catalog_form_node("Cat License", owner)

      {:ok, _view, html} = live(conn, "/admin/flows/#{dog.id}/nodes/#{dog_node.id}/form")
      assert html =~ "Catalog form"
      assert html =~ "used in Dog License, Cat License"

      # And how a step leaves it
      assert html =~ "remove this step from the canvas and add it again"

      # The edit page wears it too, before the first keystroke
      [v1] = Forms.list_versions(owner.id)
      {:ok, draft} = Forms.create_draft(owner.id, based_on: v1.id)

      {:ok, _view, html} =
        live(conn, "/admin/flows/#{dog.id}/nodes/#{dog_node.id}/form/versions/#{draft.id}/edit")

      assert html =~ "used in Dog License, Cat License"

      # The catalog knows too, before anyone opens the form to edit it
      {:ok, _view, html} = live(conn, "/admin/forms")
      assert html =~ "Dog License, Cat License"

      {:ok, _view, html} = live(conn, "/admin/forms/#{owner.id}")
      assert html =~ "Used in Dog License, Cat License"
      refute html =~ "Catalog form"
    end

    test "the publish dialog attributes instances to the flows they are in", %{conn: conn} do
      {owner, v1} = published_catalog("Owner contact")
      {dog, dog_node} = flow_with_catalog_form_node("Dog License", owner)
      {cat, cat_node} = flow_with_catalog_form_node("Cat License", owner)
      {:ok, dog} = Flows.update_status(dog, "open", [])
      {:ok, cat} = Flows.update_status(cat, "open", [])
      start_at(dog, dog_node)
      start_at(cat, cat_node)

      {:ok, draft} = Forms.create_draft(owner.id, based_on: v1.id)
      {:ok, view, _html} = live(conn, "/admin/forms/#{owner.id}/versions/#{draft.id}")

      view |> element("button", "Publish") |> render_click()

      html = render(view)
      assert html =~ "2 in progress and 0 completed"
      assert html =~ "In progress: 1 in Cat License, 1 in Dog License"
    end

    test "deleting a catalog form in use names the flows using it", %{conn: conn} do
      {owner, _v1} = published_catalog("Owner contact")
      flow_with_catalog_form_node("Dog License", owner)
      flow_with_catalog_form_node("Cat License", owner)

      {:ok, view, _html} = live(conn, "/admin/forms/#{owner.id}")

      view |> element(~s(button[phx-click="delete"])) |> render_click()

      assert render(view) =~ "Dog License and Cat License use it. Remove those steps first."
      assert Forms.get(owner.id) != nil
    end
  end

  describe "health after a form save" do
    # Every save a form page makes ends with one refresh of the health cached
    # on each root using the form (`Health.refresh_for_form/2`); reuse
    # refreshes the step's root. Publish and the edit page's save are proven
    # in flows_crud_test; the rest here, by the badge's counts and by the
    # check's time moving on where the counts do not.
    test "create draft, copy definition, delete draft, archive, and reuse each refresh the flow's health",
         %{conn: conn} do
      {root, node} = wired_flow_with_form_node("Enrollment", "Name")
      own = Forms.get(node.form_id)
      [draft] = Forms.list_versions(own.id)
      form_page = "/admin/flows/#{root.id}/nodes/#{node.id}/form"

      status = fn -> Health.status(Flows.get(root.id)) end

      # Nothing has been checked yet; publishing from the page checks first
      assert status.() == nil

      {:ok, view, _html} = live(conn, "#{form_page}/versions/#{draft.id}")
      # Reached through a flow, the form page carries the flow's badge
      assert has_element?(view, ~s(a[href="/admin/flows/#{root.id}/health"] span), "–")
      view |> element("button", "Publish") |> render_click()
      assert_redirect(view, "#{form_page}/versions/#{draft.id}")
      assert %{level: :ok, counts: %{error: 0, info: 0}, checked_at: published_at} = status.()

      {:ok, view, _html} = live(conn, "#{form_page}/versions/#{draft.id}")
      assert has_element?(view, ~s(a[href="/admin/flows/#{root.id}/health"] span), "✓")

      # Create draft: checked again, though a draft matching the published
      # version has nothing to report
      {:ok, view, _html} = live(conn, "#{form_page}/versions/#{draft.id}")
      view |> element(~s(button[phx-click="create_draft"])) |> render_click()
      new_draft = Enum.find(Forms.list_versions(own.id), &(&1.status == "draft"))
      assert_redirect(view, "#{form_page}/versions/#{new_draft.id}/edit")
      assert %{counts: %{info: 0}, checked_at: drafted_at} = status.()
      assert DateTime.compare(drafted_at, published_at) == :gt

      # Copy definition from a published catalog form: the draft now differs
      # from what users see
      {:ok, source} = Forms.create(%{name: "Source"})
      [source_draft] = Forms.list_versions(source.id)

      {:ok, source_draft} =
        Forms.update_draft(source_draft, %{definition: %{"fields" => [%{"name" => "ssn"}]}})

      {:ok, _v1} = Forms.update_status(source_draft, :published)

      {:ok, view, _html} = live(conn, "#{form_page}/versions/#{new_draft.id}/edit")

      view
      |> element("#forms-edit-form-form")
      |> render_change(%{"dynamic_form" => %{"definition_editor" => "copy"}})

      view
      |> element("#forms-edit-form-form")
      |> render_change(%{"dynamic_form" => %{"definition_copy_source" => source.id}})

      view |> element(~s(button[phx-click="copy_definition"])) |> render_click()
      assert %{level: :info, counts: %{info: 1}} = status.()

      # Info is work in progress, not something wrong: the badge stays a
      # check, in the info colour, and the tooltip says what there is to review
      assert has_element?(view, ~s(a[href="/admin/flows/#{root.id}/health"].bg-white span), "✓")
      assert has_element?(view, ~s(a[title="Health: healthy · 1 to review"]))

      # Delete draft: the info goes
      view |> element(~s(button[phx-click="delete_draft"])) |> render_click()
      assert_redirect(view, form_page)
      assert %{level: :ok, counts: %{info: 0}} = status.()

      # Archive the published version: nothing users can start
      {:ok, view, _html} = live(conn, "#{form_page}/versions/#{draft.id}")
      view |> element(~s(button[phx-click="archive"])) |> render_click()
      assert %{level: :error, counts: %{error: 1}} = status.()

      # Reuse, from another flow's blank step: that root is checked for the
      # first time
      {other, other_node} = flow_with_form_node("Cat License", "Owner")
      [other_draft] = Forms.list_versions(other_node.form_id)
      assert Health.status(Flows.get(other.id)) == nil

      {:ok, view, _html} =
        live(
          conn,
          "/admin/flows/#{other.id}/nodes/#{other_node.id}/form/versions/#{other_draft.id}/edit"
        )

      view
      |> element("input[type=radio][value=reuse]")
      |> render_click(%{"selection" => "reuse"})

      view
      |> element("#forms-edit-chooser-reuse")
      |> render_change(%{"source_form_id" => source.id})

      view |> element(~s(button[phx-click="reuse_form"])) |> render_click()
      assert_redirect(view, "/admin/flows/#{other.id}/nodes/#{other_node.id}/form")
      assert %{checked_at: %DateTime{}} = Health.status(Flows.get(other.id))
    end
  end

  # A root flow wired Start → one form step (its own form, a blank draft) → End
  defp wired_flow_with_form_node(flow_name, form_label) do
    {:ok, flow} = Flows.create(%{name: flow_name, nodes: Flows.starter_nodes()})
    flow = Flows.get(flow.id)
    start = Enum.find(flow.nodes, &("Start" in &1.labels))
    stop = Enum.find(flow.nodes, &("End" in &1.labels))
    step_id = Ecto.UUID.generate()

    {:ok, _flow} =
      Flows.update(flow, %{
        nodes:
          Enum.map(flow.nodes, &%{id: &1.id, properties: &1.properties}) ++
            [
              %{
                id: step_id,
                properties: %{
                  "type" => "step",
                  "data" => %{"label" => form_label, "kind" => "form"}
                }
              }
            ],
        relationships: [
          %{source_id: start.id, target_id: step_id, label: "CONNECTS_TO"},
          %{source_id: step_id, target_id: stop.id, label: "CONNECTS_TO"}
        ]
      })

    {Flows.get(flow.id), Flows.get_node(step_id)}
  end

  # A published catalog form by name — what a step reuses
  defp published_catalog(name) do
    {:ok, form} = Forms.create(%{name: name})
    [draft] = Forms.list_versions(form.id)
    {:ok, v1} = Forms.update_status(draft, :published)
    {Forms.get(form.id), v1}
  end

  # A user starts the form at a root flow's step
  defp start_at(flow, node) do
    {:ok, journey} = Instances.Flows.create(%{template_flow_id: flow.id, user_id: "owner"})
    {:ok, instance} = Instances.Forms.update_status(journey, [node.id], :in_progress)
    instance
  end

  describe "a step's name" do
    # The Name field edits the step — the node's label, which is what the
    # instance pages show — and the owned form's name follows it. A catalog
    # form's own name is edited on its catalog page, not from a step.
    test "from a node, Name is the step's label; saving renames the step and its owned form",
         %{conn: conn} do
      {root, node} = flow_with_form_node("Dog License", "Owner contact")
      form = Forms.get(node.form_id)
      [draft] = Forms.list_versions(form.id)

      {:ok, view, html} =
        live(
          conn,
          "/admin/flows/#{root.id}/nodes/#{node.id}/form/versions/#{draft.id}/edit?start=custom"
        )

      assert html =~ "Step name"

      view
      |> element("#forms-edit-form-form")
      |> render_submit(%{
        "dynamic_form" => %{"name" => "Your details", "definition" => ~s({"fields": []})}
      })

      assert render(view) =~ "Saved."
      assert Forms.get(form.id).name == "Your details"

      [node] = Flows.get(root.id).nodes
      assert get_in(node.properties, ["data", "label"]) == "Your details"
    end

    test "from a node, a catalog form keeps its own name; saving renames only the step",
         %{conn: conn} do
      {:ok, catalog} = Forms.create(%{name: "Owner contact"})
      [draft] = Forms.list_versions(catalog.id)
      {root, node} = flow_with_catalog_form_node("Cat License", catalog)

      {:ok, view, html} =
        live(
          conn,
          "/admin/flows/#{root.id}/nodes/#{node.id}/form/versions/#{draft.id}/edit?start=custom"
        )

      # The field shows the step's label, and says whose name is not being edited
      assert html =~ "Step name"
      assert has_element?(view, "input[name='dynamic_form[name]'][value='Owner contact']")
      assert html =~ "catalog"

      view
      |> element("#forms-edit-form-form")
      |> render_submit(%{
        "dynamic_form" => %{"name" => "Your details", "definition" => ~s({"fields": []})}
      })

      assert render(view) =~ "Saved."

      [node] = Flows.get(root.id).nodes
      assert get_in(node.properties, ["data", "label"]) == "Your details"
      assert Forms.get(catalog.id).name == "Owner contact"
    end

    test "on its catalog page, Name is the form's own name and saving renames it", %{conn: conn} do
      {:ok, catalog} = Forms.create(%{name: "Owner contact"})
      [draft] = Forms.list_versions(catalog.id)

      {:ok, view, html} =
        live(conn, "/admin/forms/#{catalog.id}/versions/#{draft.id}/edit?start=custom")

      refute html =~ "Step name"

      view
      |> element("#forms-edit-form-form")
      |> render_submit(%{
        "dynamic_form" => %{"name" => "Owner details", "definition" => ~s({"fields": []})}
      })

      assert render(view) =~ "Saved."
      assert Forms.get(catalog.id).name == "Owner details"
    end
  end

  describe "a step's slug" do
    # Through a step the Slug field is the step's — the node's, the handle a
    # host names the step by — and the owned form behind it has none. A
    # catalog form's own slug is edited on its catalog page.
    test "from a node, Slug is the step's; saving writes the node, and the owned form has none",
         %{conn: conn} do
      {root, node} = flow_with_form_node("Dog License", "Owner contact")
      form = Forms.get(node.form_id)
      [draft] = Forms.list_versions(form.id)

      {:ok, view, html} =
        live(
          conn,
          "/admin/flows/#{root.id}/nodes/#{node.id}/form/versions/#{draft.id}/edit?start=custom"
        )

      assert html =~ "Step slug"

      assert has_element?(
               view,
               "input[name='dynamic_form[slug]'][value='dog-license_owner-conta']"
             )

      submit = fn slug ->
        view
        |> element("#forms-edit-form-form")
        |> render_submit(%{
          "dynamic_form" => %{
            "name" => "Owner contact",
            "slug" => slug,
            "definition" => ~s({"fields": []})
          }
        })

        render(view)
      end

      assert submit.("owner-contact") =~ "Saved."
      assert Flows.get_node(node.id).slug == "owner-contact"
      assert Forms.get(form.id).slug == nil

      # A slug another step holds is refused by name, and nothing moves
      {:ok, other} = Flows.create(%{name: "Cat License"})

      {:ok, _} =
        Flows.update(other, %{
          nodes: [
            %{
              slug: "taken",
              properties: %{
                "type" => "step",
                "data" => %{"label" => "Owner contact", "kind" => "form"}
              }
            }
          ]
        })

      assert submit.("taken") =~ "The slug has already been taken."
      assert Flows.get_node(node.id).slug == "owner-contact"
    end

    test "from a node, a catalog form's own slug is named beside the step's, and stays its own",
         %{conn: conn} do
      {:ok, catalog} = Forms.create(%{name: "Owner contact"})
      [draft] = Forms.list_versions(catalog.id)
      {root, node} = flow_with_catalog_form_node("Cat License", catalog)

      {:ok, view, html} =
        live(
          conn,
          "/admin/flows/#{root.id}/nodes/#{node.id}/form/versions/#{draft.id}/edit?start=custom"
        )

      assert html =~ "Step slug"

      assert has_element?(
               view,
               "input[name='dynamic_form[slug]'][value='cat-license_owner-conta']"
             )

      assert html =~ "own slug is “owner-conta”"

      view
      |> element("#forms-edit-form-form")
      |> render_submit(%{
        "dynamic_form" => %{
          "name" => "Owner contact",
          "slug" => "cat-owner",
          "definition" => ~s({"fields": []})
        }
      })

      assert render(view) =~ "Saved."
      assert Flows.get_node(node.id).slug == "cat-owner"
      assert Forms.get(catalog.id).slug == "owner-conta"
    end
  end

  test "Copy offers this flow's forms alongside the catalog, each once, never the form itself",
       %{conn: conn} do
    # Start → Owner details → Pet details → a reused catalog form. Owned
    # forms are not in the catalog, but they are in this flow
    {:ok, root} = Flows.create(%{name: "Licensing"})
    {:ok, owner_form} = Forms.create(%{name: "Owner details", owner_flow_id: root.id})

    {:ok, pet_form} =
      Forms.create(%{
        name: "Pet details",
        owner_flow_id: root.id,
        definition: %{"fields" => [%{"name" => "breed"}]}
      })

    {:ok, catalog} = Forms.create(%{name: "Catalog Form", definition: %{"fields" => []}})
    start_node = build_node(root, ["Start"], "Start")
    owner = build_node(root, ["Form"], "Owner details", %{form_id: owner_form.id})
    pet = build_node(root, ["Form"], "Pet details", %{form_id: pet_form.id, slug: "pet-details"})

    reused =
      build_node(root, ["Form"], "Vaccination record", %{form_id: catalog.id, slug: "vaccination"})

    edge(root, start_node, owner)
    edge(root, owner, pet)
    edge(root, pet, reused)
    [draft] = Forms.list_versions(owner_form.id)

    assert Enum.map(Forms.list(), & &1.id) == [catalog.id]

    {:ok, view, _html} =
      live(conn, "/admin/flows/#{root.id}/nodes/#{owner.id}/form/versions/#{draft.id}/edit")

    view
    |> element("input[type=radio][value=copy]")
    |> render_click(%{"selection" => "copy"})

    # A flow's form is named by its step: the step's label and the step's slug
    html = render(view)
    assert html =~ ~s(value="#{pet_form.id}")
    assert html =~ "Current flow - Pet details (pet-details)"
    refute html =~ ~s(value="#{owner_form.id}")

    # The reused catalog form is offered once, at its step, by the step's
    # name and slug — not again from the catalog under its own
    assert length(String.split(html, ~s(value="#{catalog.id}"))) == 2
    assert html =~ "Current flow - Vaccination record (vaccination)"
    refute html =~ "Reusable form - Catalog Form"
    refute html =~ "(#{catalog.slug})"

    view
    |> element("#forms-edit-chooser-copy")
    |> render_change(%{"source_form_id" => pet_form.id})

    view
    |> element(~s(button[phx-click="copy_form"]))
    |> render_click()

    assert Forms.get_version(draft.id).definition == %{"fields" => [%{"name" => "breed"}]}

    # The editor's own Copy existing form lists the same sources
    view
    |> element("#forms-edit-form-form")
    |> render_change(%{"dynamic_form" => %{"definition_editor" => "copy"}})

    html = render(view)
    assert html =~ "Copy definition from existing form"
    assert html =~ ~s(value="#{pet_form.id}")
    assert html =~ ~s(value="#{catalog.id}")
    refute html =~ ~s(value="#{owner_form.id}")
  end

  test "Form type follows Description, and the picked type's name and description show under it",
       %{conn: conn} do
    {:ok, form} = Forms.create(%{name: "Typed"})
    [draft] = Forms.list_versions(form.id)

    {:ok, view, html} =
      live(conn, "/admin/forms/#{form.id}/versions/#{draft.id}/edit?start=custom")

    {description_at, _} = :binary.match(html, ~s(name="dynamic_form[description]"))
    {type_at, _} = :binary.match(html, ~s(name="dynamic_form[form_type]"))
    assert description_at < type_at

    # The default type is what an unset one resolves to, so it is described
    assert html =~ "About Default form type"
    assert html =~ "The form as designed, nothing more."

    view
    |> element("#forms-edit-form-form")
    |> render_change(%{"dynamic_form" => %{"form_type" => "review"}})

    # Lands through DynamicForm's debounced change pass, like the property swap
    Process.sleep(520)
    html = render(view)
    assert html =~ "About Review form type"
    assert html =~ "answers beside this one, for checking them."
    refute html =~ "About Default form type"
    refute html =~ "The form as designed, nothing more."
  end

  test "Copy existing form is its own editor, works any time and touches only the definition",
       %{conn: conn} do
    {:ok, source} =
      Forms.create(%{name: "Source Form", definition: %{"fields" => [%{"name" => "ssn"}]}})

    [source_draft] = Forms.list_versions(source.id)
    {:ok, _v1} = Forms.update_status(source_draft, :published)

    {form, v1} = published_form()
    {:ok, draft} = Forms.create_draft(form.id, based_on: v1.id)

    {:ok, view, html} = live(conn, "/admin/forms/#{form.id}/versions/#{draft.id}/edit")

    # Already published, so the main chooser doesn't offer itself — Copy
    # existing form isn't gated by that at all. It is the radio's third
    # choice, hidden while the draft opens in the form builder
    refute html =~ "Start this form from"
    refute html =~ "Copy definition from existing form"

    assert has_element?(
             view,
             ~s(input[name="dynamic_form[definition_editor]"][value="copy"])
           )

    view
    |> element("#forms-edit-form-form")
    |> render_change(%{"dynamic_form" => %{"definition_editor" => "copy"}})

    html = render(view)
    assert html =~ "Copy definition from existing form"
    refute html =~ "Definition (JSON)"
    refute html =~ "Add element"

    # The source is a field of the form; the button carries the pick with it
    view
    |> element("#forms-edit-form-form")
    |> render_change(%{"dynamic_form" => %{"definition_copy_source" => source.id}})

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
    # The reviewing form is the tree's own: a shared one could not point at a step
    {review_form, _v1} = published_form(owner_flow_id: root.id)
    review = build_node(root, ["Form"], "Review", %{form_id: review_form.id})
    edge(root, start_node, intake)
    edge(root, intake, review)
    # The form is published, so its details — the type among them — are
    # edited on the details page
    {:ok, view, _html} = live(conn, "/admin/flows/#{root.id}/nodes/#{review.id}/form/edit")

    view
    |> element("#forms-details-form-form")
    |> render_change(%{"dynamic_form" => %{"name" => "Review", "form_type" => "demo_prefill"}})

    html = render(view)
    assert html =~ "Copy name from"
    assert html =~ ~s(value="#{intake.id}")
    assert html =~ "Intake"
    refute html =~ ~s(value="#{review.id}")
    refute html =~ "No earlier forms"

    view
    |> element("#forms-details-form-form")
    |> render_submit(%{
      "dynamic_form" => %{
        "name" => "Review",
        "form_type" => "demo_prefill",
        "property_name" => "Ada",
        "property_source" => intake.id
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

    {:ok, _view, html} = live(conn, "/admin/flows/#{root.id}/nodes/#{review.id}/form/edit")

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

    assert html =~ "Current draft is based on"
    assert html =~ "Last updated just now on"
    assert html =~ "Other drafts of this form exist"
    assert has_element?(view, ~s(a[href="/admin/forms/#{form.id}"]), "See all versions")

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

    # Save draft and Publish trade the primary style: whichever is the next
    # thing to do wears it. Clean, that is Publish — publishing takes the
    # last saved definition, and there is nothing newer to save.
    refute has_element?(view, ~s(button[form="forms-edit-form-form"].btn-primary))
    assert has_element?(view, ~s(button.btn-primary), "Publish")

    view
    |> element("#forms-edit-form-form")
    |> render_change(%{"dynamic_form" => %{"name" => "Remote, edited", "definition" => "{}"}})

    assert has_element?(view, ~s(button[form="forms-edit-form-form"].btn-primary))
    refute has_element?(view, ~s(button.btn-primary), "Publish")

    view
    |> element("#forms-edit-form-form")
    |> render_submit(%{"dynamic_form" => %{"name" => "Remote, edited", "definition" => "{}"}})

    assert render(view) =~ "Saved."
    refute has_element?(view, ~s(button[form="forms-edit-form-form"].btn-primary))
    assert has_element?(view, ~s(button.btn-primary), "Publish")
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

    # Later publishes prompt. The saved-definition caveat is only about
    # unsaved edits, so a clean draft is not warned about them
    {:ok, second} = Forms.create_draft(form.id, based_on: draft.id)
    {:ok, view, _html} = live(conn, "/admin/forms/#{form.id}/versions/#{second.id}/edit")

    view |> element("button", "Publish") |> render_click()
    assert render(view) =~ "Publish this draft?"
    refute render(view) =~ "unsaved edits are not included"

    view |> element("button", "Cancel") |> render_click()

    view
    |> element("#forms-edit-form-form")
    |> render_change(%{
      "dynamic_form" => %{"name" => "Publishable, edited", "definition" => "{}"}
    })

    view |> element("button", "Publish") |> render_click()
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

    {:ok, view, html} = live(conn, "/admin/forms/#{form.id}")

    # No draft yet, so nothing to continue
    refute html =~ "Continue editing latest draft"

    view |> element("button", "New draft from this version") |> render_click()

    {path, _flash} = assert_redirect(view)
    assert path =~ ~r{^/admin/forms/#{form.id}/versions/.+/edit$}
  end

  test "published and archived versions lead to the latest draft, and an archived one can be forked",
       %{conn: conn} do
    {form, v1} = published_form()
    {:ok, older_draft} = Forms.create_draft(form.id, based_on: v1.id)
    {:ok, draft} = Forms.create_draft(form.id, based_on: v1.id)

    # The default view is the published version; the newest draft is a click
    # away rather than a version-history hunt
    {:ok, view, _html} = live(conn, "/admin/forms/#{form.id}")

    assert has_element?(
             view,
             ~s(a[href="/admin/forms/#{form.id}/versions/#{draft.id}/edit"]),
             "Continue editing latest draft"
           )

    refute has_element?(
             view,
             ~s(a[href="/admin/forms/#{form.id}/versions/#{older_draft.id}/edit"])
           )

    # An archived version keeps both, and only loses Archive
    {:ok, _} = Forms.update_status(v1, :archived)
    {:ok, view, html} = live(conn, "/admin/forms/#{form.id}/versions/#{v1.id}")
    assert html =~ "v1 · archived"
    assert html =~ "Continue editing latest draft"
    assert html =~ "New draft from this version"
    refute html =~ "Archive version"

    view |> element("button", "New draft from this version") |> render_click()
    {path, _flash} = assert_redirect(view)
    assert path =~ ~r{^/admin/forms/#{form.id}/versions/.+/edit$}

    [forked | _rest] = Forms.list_versions(form.id)
    assert forked.based_on_version_id == v1.id
    assert forked.definition == v1.definition
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

  # The details — name, slug, description, type — belong to the lineage and
  # change the moment they are saved. The draft editor carries them only
  # until the form is first published; after that they have their own page.
  describe "form details" do
    test "a never-published draft edits the details beside its definition", %{conn: conn} do
      {:ok, form} = Forms.create(%{name: "Fresh", description: "Before"})
      [draft] = Forms.list_versions(form.id)

      {:ok, view, html} =
        live(conn, "/admin/forms/#{form.id}/versions/#{draft.id}/edit?start=custom")

      assert html =~ "Form details"
      assert has_element?(view, ~s(input[name="dynamic_form[name]"]))
      refute has_element?(view, ~s(a[href="/admin/forms/#{form.id}/edit"]))

      view
      |> element("#forms-edit-form-form")
      |> render_submit(%{
        "dynamic_form" => %{
          "name" => "Renamed",
          "description" => "After",
          "definition" => ~s({"elements": []})
        }
      })

      assert render(view) =~ "Saved."
      assert %{name: "Renamed", description: "After"} = Forms.get(form.id)
    end

    test "once published, the draft editor drops the details and points at their page",
         %{conn: conn} do
      {form, v1} = published_form(name: "Settled", description: "Kept")
      {:ok, draft} = Forms.create_draft(form.id, based_on: v1.id)

      {:ok, view, html} = live(conn, "/admin/forms/#{form.id}/versions/#{draft.id}/edit")

      refute has_element?(view, ~s(input[name="dynamic_form[name]"]))
      refute has_element?(view, ~s(select[name="dynamic_form[form_type]"]))
      assert html =~ "Note:"
      assert html =~
               "Form details like the name, slug, description, and type are global and managed"
      assert has_element?(view, ~s(a[href="/admin/forms/#{form.id}/edit"]), "here")

      # A save writes the definition and nothing else — a name in the
      # request is not a field of this page
      view
      |> element("#forms-edit-form-form")
      |> render_submit(%{
        "dynamic_form" => %{"name" => "Smuggled", "definition" => ~s({"elements": []})}
      })

      assert render(view) =~ "Saved."
      assert Forms.get_version(draft.id).definition == %{"elements" => []}
      assert %{name: "Settled", description: "Kept"} = Forms.get(form.id)
    end

    test "the details page saves the lineage for every version at once", %{conn: conn} do
      {form, _v1} = published_form(name: "Settled", description: "Before")

      {:ok, view, html} = live(conn, "/admin/forms/#{form.id}/edit")

      assert html =~ "Form details"
      assert html =~ "shared by every version"
      # The banner leads back to the form's page, where drafts are
      assert has_element?(view, ~s(a[href="/admin/forms/#{form.id}"]), "the form")
      assert has_element?(view, ~s(input[name="dynamic_form[name]"][value="Settled"]))

      # Picking a type swaps in its properties' fields; the swap lands
      # through send_update after the change event
      view
      |> element("#forms-details-form-form")
      |> render_change(%{"dynamic_form" => %{"name" => "Settled", "form_type" => "demo_prefill"}})

      assert render(view) =~ "Name to prefill"

      view
      |> element("#forms-details-form-form")
      |> render_submit(%{
        "dynamic_form" => %{
          "name" => "Renamed",
          "slug" => "renamed",
          "description" => "After",
          "form_type" => "demo_prefill",
          "property_name" => "Ada"
        }
      })

      assert render(view) =~ "Saved."

      updated = Forms.get(form.id)
      assert updated.name == "Renamed"
      assert updated.slug == "renamed"
      assert updated.description == "After"
      assert updated.properties["form_type"] == "demo_prefill"
      assert updated.properties["form_type_property_values"] == %{"name" => "Ada"}

      # No draft was made: the published version is still the only one
      assert [%{status: "published"}] = Forms.list_versions(form.id)
    end

    test "from a node, the details page edits the step's name and slug", %{conn: conn} do
      {root, node} = flow_with_form_node("Dog License", "Owner contact")
      form = Forms.get(node.form_id)
      [draft] = Forms.list_versions(form.id)
      {:ok, _v1} = Forms.update_status(draft, :published)

      {:ok, view, html} = live(conn, "/admin/flows/#{root.id}/nodes/#{node.id}/form/edit")

      assert html =~ "Step name"
      assert html =~ "Step slug"
      assert has_element?(view, ~s(input[name="dynamic_form[name]"][value="Owner contact"]))

      view
      |> element("#forms-details-form-form")
      |> render_submit(%{
        "dynamic_form" => %{"name" => "Your details", "slug" => "your-details"}
      })

      assert render(view) =~ "Saved."

      [node] = Flows.get(root.id).nodes
      assert get_in(node.properties, ["data", "label"]) == "Your details"
      assert node.slug == "your-details"
      assert Forms.get(form.id).name == "Your details"
    end

    test "the show page lists the details and links to their page", %{conn: conn} do
      {form, _v1} = published_form(name: "Settled", description: "What it is for")

      {:ok, view, html} = live(conn, "/admin/forms/#{form.id}")

      assert html =~ "Form details"
      assert html =~ "What it is for"
      assert html =~ form.slug
      assert has_element?(view, ~s(a[href="/admin/forms/#{form.id}/edit"]), "Edit form details")

      # Through a step, with the flow's mode carried along
      {root, node} = flow_with_form_node("Dog License", "Owner contact")
      {:ok, view, html} = live(conn, "/admin/flows/#{root.id}/nodes/#{node.id}/form?mode=edit")

      assert html =~ "Step name"

      assert has_element?(
               view,
               ~s(a[href="/admin/flows/#{root.id}/nodes/#{node.id}/form/edit?mode=edit"]),
               "Edit form details"
             )
    end

    test "New draft from this version is primary only while there is no draft", %{conn: conn} do
      {form, v1} = published_form()

      {:ok, view, _html} = live(conn, "/admin/forms/#{form.id}")
      assert has_element?(view, ~s(button.btn-primary[phx-click="create_draft"]))
      refute has_element?(view, "a", "Continue editing latest draft")

      {:ok, _draft} = Forms.create_draft(form.id, based_on: v1.id)

      {:ok, view, _html} = live(conn, "/admin/forms/#{form.id}")
      assert has_element?(view, "a.btn-primary", "Continue editing latest draft")
      assert has_element?(view, ~s(button[phx-click="create_draft"]))
      refute has_element?(view, ~s(button.btn-primary[phx-click="create_draft"]))
    end
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

  defp published_form(attrs \\ []) do
    {:ok, form} =
      Forms.create(Map.new([name: "Form #{System.unique_integer([:positive])}"] ++ attrs))

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

  # A flow whose one form step points at an existing catalog form — what the
  # reuse of a catalog form produces — labelled with the form's own name, so
  # that building it renames nothing
  defp flow_with_catalog_form_node(flow_name, catalog) do
    {:ok, flow} = Flows.create(%{name: flow_name})

    node_attrs = %{
      properties: %{
        "type" => "step",
        "form_id" => catalog.id,
        "data" => %{"label" => catalog.name, "kind" => "form"}
      }
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
