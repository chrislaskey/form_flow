defmodule Demo.FormFlowFormsPreviewTest do
  @moduledoc """
  Exercises the form preview: a child LiveView
  (`FormFlow.Web.Templates.Forms.Preview`) embedded with `live_render`, so a
  definition that crashes the renderer takes down only the preview process —
  never the admin page around it.

  On the edit page the preview refreshes over PubSub when the parent app
  configures `:form_flow, :pubsub_server` (the demo does): the editor
  broadcasts the current definition to a per-editor topic and the child
  re-renders in place. Without a pubsub server it falls back to remounting
  the child with a bumped rev in its id — covered here by clearing the
  config for one test.
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

    defp toggle_auto_refresh(view) do
      view
      |> element(~s(button[aria-label="Toggle auto-update preview"]))
      |> render_click()
    end

    # A pushed refresh arrives through async hops (the debounced change pass
    # in the DynamicForm component, then the broadcast to the child), so poll
    # the child until the text shows; returns the last render either way
    defp await_text(child, text, tries \\ 40) do
      html = render(child)

      cond do
        html =~ text ->
          html

        tries > 0 ->
          Process.sleep(50)
          await_text(child, text, tries - 1)

        true ->
          html
      end
    end

    # The remount fallback mounts a fresh child, so poll for its new id
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

      assert html =~ "Auto-refresh"

      assert view |> element(~s(button[aria-label="Toggle auto-update preview"])) |> render() =~
               ~s(aria-checked="false")

      child = find_live_child(view, "forms-edit-preview-r0")
      assert render(child) =~ "Full name"
    end

    test "with auto-refresh off, changes leave the preview at its initial render", %{conn: conn} do
      {form, draft} = create_form()

      {:ok, view, _html} = live(conn, "/admin/forms/#{form.id}/versions/#{draft.id}/edit")
      edit_change(view, @new_definition)

      # Neither refresh mechanism may fire: no remounted child, no push. With
      # auto-refresh off nothing is debounced, so the change round trip has
      # fully settled by now and these reads are deterministic
      refute find_live_child(view, "forms-edit-preview-r1")

      child = find_live_child(view, "forms-edit-preview-r0")
      assert render(child) =~ "Full name"
      refute render(child) =~ "Email address"
    end

    test "the manual Refresh action pushes the definition into the same child", %{conn: conn} do
      {form, draft} = create_form()

      {:ok, view, _html} = live(conn, "/admin/forms/#{form.id}/versions/#{draft.id}/edit")
      child = find_live_child(view, "forms-edit-preview-r0")

      edit_change(view, @new_definition)
      view |> element(~s(button[phx-click="update_preview"])) |> render_click()

      # The broadcast is synchronous, so the child already has the message;
      # render/1 is a sync call and lands after it
      assert render(child) =~ "Email address"

      # Pushed in place — the child was not remounted
      refute find_live_child(view, "forms-edit-preview-r1")
    end

    test "reverting to the saved text still pushes — the guard tracks the last push", %{
      conn: conn
    } do
      {form, draft} = create_form()
      saved_json = Phoenix.json_library().encode!(@definition, pretty: true)

      {:ok, view, _html} = live(conn, "/admin/forms/#{form.id}/versions/#{draft.id}/edit")
      child = find_live_child(view, "forms-edit-preview-r0")

      edit_change(view, @new_definition)
      view |> element(~s(button[phx-click="update_preview"])) |> render_click()
      assert render(child) =~ "Email address"

      # Editing back to exactly the saved definition must push again, not
      # strand the preview on the intermediate content
      edit_change(view, saved_json)
      view |> element(~s(button[phx-click="update_preview"])) |> render_click()

      html = render(child)
      assert html =~ "Full name"
      refute html =~ "Email address"
    end

    test "toggling auto-refresh on pushes the preview up to date immediately", %{conn: conn} do
      {form, draft} = create_form()

      {:ok, view, _html} = live(conn, "/admin/forms/#{form.id}/versions/#{draft.id}/edit")
      child = find_live_child(view, "forms-edit-preview-r0")

      # Typed while the toggle was off — the preview still shows the original
      edit_change(view, @new_definition)
      refute render(child) =~ "Email address"

      toggle_auto_refresh(view)

      assert render(child) =~ "Email address"
    end

    test "with auto-refresh on, changes push to the preview after the debounce", %{conn: conn} do
      {form, draft} = create_form()

      {:ok, view, _html} = live(conn, "/admin/forms/#{form.id}/versions/#{draft.id}/edit")
      child = find_live_child(view, "forms-edit-preview-r0")

      toggle_auto_refresh(view)

      # The manual Refresh action only exists while auto-refresh is off
      refute has_element?(view, ~s(button[phx-click="update_preview"]))

      edit_change(view, @new_definition)

      # The 500ms debounce holds the change pass back before it can push
      refute render(child) =~ "Email address"

      assert await_text(child, "Email address") =~ "Email address"

      # Pushed in place — the child was not remounted
      refute find_live_child(view, "forms-edit-preview-r1")
      assert find_live_child(view, "forms-edit-preview-r0")
    end

    test "an invalid JSON draft previews as an inline error, not a crash", %{conn: conn} do
      {form, draft} = create_form()

      {:ok, view, _html} = live(conn, "/admin/forms/#{form.id}/versions/#{draft.id}/edit")
      child = find_live_child(view, "forms-edit-preview-r0")

      edit_change(view, "{not json")
      toggle_auto_refresh(view)

      assert render(child) =~ "can&#39;t be rendered as a form"

      # The editor around it is untouched
      assert render(view) =~ "Definition (JSON)"
    end

    test "without a pubsub server, Refresh falls back to remounting the child", %{conn: conn} do
      # The library reads the config on every call, so clearing it here
      # flips both pages onto the remount path for this test only. Safe
      # because the demo suite runs sync (the SQL sandbox is shared).
      original = Application.get_env(:form_flow, :pubsub_server)
      Application.put_env(:form_flow, :pubsub_server, nil)
      on_exit(fn -> Application.put_env(:form_flow, :pubsub_server, original) end)

      {form, draft} = create_form()

      {:ok, view, _html} = live(conn, "/admin/forms/#{form.id}/versions/#{draft.id}/edit")
      assert find_live_child(view, "forms-edit-preview-r0")

      edit_change(view, @new_definition)
      view |> element(~s(button[phx-click="update_preview"])) |> render_click()

      child = await_child(view, "forms-edit-preview-r1")
      assert child, "expected the preview to remount with a bumped rev"
      assert render(child) =~ "Email address"
      refute find_live_child(view, "forms-edit-preview-r0")
    end
  end
end
