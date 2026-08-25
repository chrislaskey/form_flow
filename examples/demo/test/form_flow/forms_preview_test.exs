defmodule Demo.FormFlowFormsPreviewTest do
  @moduledoc """
  Exercises the form preview on the show page: a child LiveView
  (`FormFlow.Web.Templates.Forms.Preview`) embedded with `live_render`, so a
  definition that crashes the renderer takes down only the preview process —
  never the admin page around it.
  """

  use DemoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias FormFlow.Data.Templates.Forms

  @definition %{
    "title" => "Contact",
    "elements" => [
      %{"type" => "text", "name" => "name", "title" => "Full name", "isRequired" => true}
    ]
  }

  defp create_form(definition \\ @definition) do
    {:ok, form} = Forms.create(%{name: "Preview form", definition: definition})
    [draft] = Forms.list_versions(form.id)
    {form, draft}
  end

  test "the show page renders the definition as a live form in a child LiveView", %{conn: conn} do
    {form, draft} = create_form()

    {:ok, view, _html} = live(conn, "/admin/forms/#{form.id}")

    child = find_live_child(view, "form-preview-#{draft.id}")
    assert child, "expected the preview child LiveView to be mounted"

    # The whole point: the preview is its own process, not the page's
    assert child.pid != view.pid

    assert render(child) =~ "Full name"
  end

  test "a valid preview submission confirms without persisting anything", %{conn: conn} do
    {form, draft} = create_form()

    {:ok, view, _html} = live(conn, "/admin/forms/#{form.id}")
    child = find_live_child(view, "form-preview-#{draft.id}")

    child
    |> element("#form-preview-#{draft.id}-form-form")
    |> render_submit(%{"dynamic_form" => %{"name" => "Ada Lovelace"}})

    # The success notice lands via handle_info after the submit round trip,
    # so it shows on the next render, not in render_submit's return
    assert render(child) =~ "nothing was saved"
    assert Forms.instance_counts(form.id) == %{"in_progress" => 0, "completed" => 0}
  end

  test "a malformed definition renders an inline error instead of a form", %{conn: conn} do
    # An element that is not a map blows up the parser — the eager parse in
    # mount turns that into an inline message rather than a crash loop
    {form, draft} = create_form(%{"elements" => ["not-an-element"]})

    {:ok, view, _html} = live(conn, "/admin/forms/#{form.id}")
    child = find_live_child(view, "form-preview-#{draft.id}")

    assert render(child) =~ "can&#39;t be rendered as a form"
    assert render(view) =~ "Definition"
  end

  # A "kill the child, assert the parent survives" test is deliberately
  # absent: LiveViewTest's ClientProxy stops itself when any view process
  # goes DOWN (client_proxy.ex), unlike the browser client, which remounts
  # only the crashed child. Crash isolation rests on the child being a
  # separate process — asserted above — plus LiveView's documented child
  # semantics; verify the remount loop manually in a browser.

  describe "edit page" do
    @new_definition ~s({"elements": [{"type": "text", "name": "email", "title": "Email address"}]})

    defp edit_change(view, definition) do
      view
      |> element("#forms-edit-form-form")
      |> render_change(%{
        "dynamic_form" => %{
          "name" => "Preview form",
          "description" => "",
          "definition" => definition
        }
      })
    end

    # The refresh arrives through two async hops (the debounced change pass,
    # then send_update back to the editor), so poll for the remounted child
    defp await_child(view, id, tries \\ 40) do
      case find_live_child(view, id) do
        nil when tries > 0 ->
          Process.sleep(50)
          render(view)
          await_child(view, id, tries - 1)

        child ->
          child
      end
    end

    test "renders the saved definition as an initial preview", %{conn: conn} do
      {form, draft} = create_form()

      {:ok, view, html} = live(conn, "/admin/forms/#{form.id}/versions/#{draft.id}/edit")

      assert html =~ "Auto-update"

      assert view |> element(~s(button[aria-label="Toggle auto-update preview"])) |> render() =~
               ~s(aria-checked="false")

      child = await_child(view, "forms-edit-preview-r0")
      assert render(child) =~ "Full name"
    end

    test "with auto-update off, changes leave the preview at its initial render", %{conn: conn} do
      {form, draft} = create_form()

      {:ok, view, _html} = live(conn, "/admin/forms/#{form.id}/versions/#{draft.id}/edit")
      edit_change(view, @new_definition)

      refute find_live_child(view, "forms-edit-preview-r1")

      # The preview still shows the saved definition — the typed one only
      # exists in the editor textarea
      child = find_live_child(view, "forms-edit-preview-r0")
      assert render(child) =~ "Full name"
      refute render(child) =~ "Email address"
    end

    test "the manual Update action refreshes the preview while auto-update is off", %{conn: conn} do
      {form, draft} = create_form()

      {:ok, view, _html} = live(conn, "/admin/forms/#{form.id}/versions/#{draft.id}/edit")

      edit_change(view, @new_definition)
      refute find_live_child(view, "forms-edit-preview-r1")

      view |> element(~s(button[phx-click="update_preview"])) |> render_click()

      child = await_child(view, "forms-edit-preview-r1")
      assert render(child) =~ "Email address"
    end

    test "toggling auto-update on catches the preview up immediately", %{conn: conn} do
      {form, draft} = create_form()

      {:ok, view, _html} = live(conn, "/admin/forms/#{form.id}/versions/#{draft.id}/edit")

      # Typed while the toggle was off — the preview still shows the original
      edit_change(view, @new_definition)

      view
      |> element(~s(button[aria-label="Toggle auto-update preview"]))
      |> render_click()

      child = await_child(view, "forms-edit-preview-r1")
      assert render(child) =~ "Email address"
    end

    test "with auto-update on, changes re-render the preview after the debounce", %{conn: conn} do
      {form, draft} = create_form()

      {:ok, view, _html} = live(conn, "/admin/forms/#{form.id}/versions/#{draft.id}/edit")

      view
      |> element(~s(button[aria-label="Toggle auto-update preview"]))
      |> render_click()

      # No changes typed yet, so enabling alone must not remount anything;
      # the manual Update action only exists while auto-update is off
      assert find_live_child(view, "forms-edit-preview-r0")
      refute has_element?(view, ~s(button[phx-click="update_preview"]))

      edit_change(view, @new_definition)

      # The 500ms debounce holds the change pass back before it can refresh
      refute find_live_child(view, "forms-edit-preview-r1")

      child = await_child(view, "forms-edit-preview-r1")
      assert render(child) =~ "Email address"
      refute find_live_child(view, "forms-edit-preview-r0")
    end

    test "an invalid JSON draft previews as an inline error, not a crash", %{conn: conn} do
      {form, draft} = create_form()

      {:ok, view, _html} = live(conn, "/admin/forms/#{form.id}/versions/#{draft.id}/edit")
      edit_change(view, "{not json")

      view
      |> element(~s(button[aria-label="Toggle auto-update preview"]))
      |> render_click()

      child = await_child(view, "forms-edit-preview-r1")
      assert render(child) =~ "can&#39;t be rendered as a form"

      # The editor around it is untouched
      assert render(view) =~ "Definition (JSON)"
    end
  end
end
