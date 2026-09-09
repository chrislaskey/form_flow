defmodule Demo.FormFlowFlowStatusTest do
  @moduledoc """
  A flow's status — `draft`, `open`, `winding_down` — and the event log that
  records how it got there (`FormFlow.Data.Templates.Flow.Event`), against a
  real database: the data layer's writes and refusals, and what each status
  does on the user-facing pages and the admin pages.
  """

  use DemoWeb.ConnCase, async: false

  import Ecto.Query, only: [from: 2]
  import Phoenix.LiveViewTest

  alias FormFlow.Data.Instances
  alias FormFlow.Data.Repo, as: FormFlowRepo
  alias FormFlow.Data.Templates.Flow
  alias FormFlow.Data.Templates.Flows

  # ── the data layer ──────────────────────────────────────────────────────

  describe "the data layer" do
    test "a flow is born a draft, with a created event carrying the admin" do
      {:ok, flow} = Flows.create(%{name: "Dog License"}, user_id: "demo-admin")

      assert flow.status == "draft"
      assert [%{event: "created", user_id: "demo-admin", snapshot: %{}}] = events(flow)
    end

    test "update_status/3 moves the status and logs from, to, and who" do
      {:ok, flow} = Flows.create(%{name: "Dog License"})

      {:ok, opened} = Flows.update_status(flow, "open", user_id: "demo-admin")
      assert opened.status == "open"
      assert Flows.get(flow.id).status == "open"

      {:ok, winding} = Flows.update_status(opened, "winding_down", user_id: "other-admin")

      assert [
               %{event: "created"},
               %{
                 event: "status_changed",
                 user_id: "demo-admin",
                 snapshot: %{"from" => "draft", "to" => "open"}
               },
               %{
                 event: "status_changed",
                 user_id: "other-admin",
                 snapshot: %{"from" => "open", "to" => "winding_down"}
               }
             ] = events(winding)

      # Any status to any other — back to draft included — and an atom works
      {:ok, drafted} = Flows.update_status(winding, :draft, [])
      assert drafted.status == "draft"
      assert length(events(drafted)) == 4
    end

    test "the same status again is a no-op, and a status the flow cannot have is refused" do
      {:ok, flow} = Flows.create(%{name: "Dog License"})

      assert {:ok, ^flow} = Flows.update_status(flow, "draft", [])
      assert length(events(flow)) == 1

      assert {:error, :unknown_status} = Flows.update_status(flow, "closed", [])
    end

    test "a read-only or archived flow refuses every way of continuing, at the data layer" do
      {:ok, flow} = Flows.create(%{name: "Dog License 2025", status: "open"})
      {:ok, instance} = Instances.Flows.create(%{flow_id: flow.id, user_id: "u"})

      for status <- ["read_only", "archived"] do
        {:ok, _} = Flows.update_status(flow, status, [])

        assert {:error, :not_open} = Instances.Flows.create(%{flow_id: flow.id, user_id: "u"})

        assert {:error, :read_only} =
                 Instances.Forms.update_status(instance, [Ecto.UUID.generate()], :in_progress)

        assert {:error, :read_only} =
                 Instances.Forms.update_status(instance, [Ecto.UUID.generate()], :completed)
      end
    end

    test "a copy is a draft whatever the source is, with its own created event" do
      {:ok, source} = Flows.create(%{name: "Dog License", status: "open"})

      {:ok, copy} = Flows.copy(source, name: "Dog License 2027", user_id: "demo-admin")

      assert copy.status == "draft"
      assert [%{event: "created", user_id: "demo-admin"}] = events(copy)
      # The source's log is its own
      assert [%{event: "created"}] = events(source)
    end

    test "deleting a flow deletes its log, deliberately, before the flow" do
      {:ok, flow} = Flows.create(%{name: "Dog License"})
      {:ok, flow} = Flows.update_status(flow, "open", [])
      assert length(events(flow)) == 2

      {:ok, _deleted} = Flows.delete(Flows.get(flow.id))

      assert events(flow) == []
    end

    test "only an open flow takes a start" do
      {:ok, draft} = Flows.create(%{name: "Draft"})
      {:ok, open} = Flows.create(%{name: "Open", status: "open"})
      {:ok, winding} = Flows.create(%{name: "Winding", status: "winding_down"})

      assert {:error, :not_open} = Instances.Flows.create(%{flow_id: draft.id, user_id: "u"})
      assert {:error, :not_open} = Instances.Flows.create(%{flow_id: winding.id, user_id: "u"})
      assert {:ok, _instance} = Instances.Flows.create(%{flow_id: open.id, user_id: "u"})
    end

    test "narrow_allowed/2 keeps the instances of flows whose status allows the action" do
      {:ok, open} = Flows.create(%{name: "Open", status: "open"})
      {:ok, other} = Flows.create(%{name: "Other", status: "open"})
      {:ok, seen} = Instances.Flows.create(%{flow_id: open.id, user_id: "u"})
      {:ok, hidden} = Instances.Flows.create(%{flow_id: other.id, user_id: "u"})
      {:ok, _} = Flows.update_status(other, "draft", [])

      ids =
        Instances.Flows.list_query(user_id: "u")
        |> Instances.Flows.narrow_allowed(:see)
        |> FormFlowRepo.all()
        |> Enum.map(& &1.id)

      assert seen.id in ids
      refute hidden.id in ids
    end
  end

  # ── the user-facing pages ───────────────────────────────────────────────

  describe "the user-facing pages" do
    test "the listing offers open flows, names winding-down ones, and hides drafts",
         %{conn: conn} do
      {:ok, open} = Flows.create(%{name: "Cat License", status: "open"})
      {:ok, winding} = Flows.create(%{name: "Dog License 2025", status: "winding_down"})
      {:ok, _draft} = Flows.create(%{name: "Dog License 2027"})

      {:ok, view, html} = live(conn, "/users")

      assert has_element?(view, start_button(open))
      refute has_element?(view, start_button(winding))
      assert html =~ "Dog License 2025"
      assert html =~ "No longer taking new starts."
      refute html =~ "Dog License 2027"
      refute html =~ "No flows are open."
    end

    test "with nothing open the listing says so", %{conn: conn} do
      {:ok, _draft} = Flows.create(%{name: "Dog License 2027"})

      {:ok, _view, html} = live(conn, "/users")

      assert html =~ "No flows are open."
    end

    test "a start is refused server-side once the flow stops taking them", %{conn: conn} do
      {:ok, flow} = Flows.create(%{name: "Cat License", status: "open"})

      {:ok, view, _html} = live(conn, "/users")
      assert has_element?(view, start_button(flow))

      # The flow winds down after the page drew; the stale click is refused
      {:ok, _} = Flows.update_status(flow, "winding_down", [])
      html = view |> element(start_button(flow)) |> render_click()

      assert html =~ "That flow is no longer taking new starts."

      assert Instances.Flows.list_query(user_id: "demo-user") |> FormFlowRepo.all() == []
    end

    test "a winding-down flow's instances are listed and continue; a draft's disappear",
         %{conn: conn} do
      {:ok, flow} = Flows.create(%{name: "Dog License 2025", status: "open"})
      {:ok, instance} = Instances.Flows.create(%{flow_id: flow.id, user_id: "demo-user"})

      {:ok, _} = Flows.update_status(flow, "winding_down", [])
      {:ok, view, html} = live(conn, "/users")
      assert html =~ instance.id
      {:ok, _view, html} = live(conn, "/users/#{instance.id}")
      assert html =~ "Dog License 2025"
      refute html =~ "not available"

      {:ok, _} = Flows.update_status(flow, "draft", [])
      {:ok, _view, html} = live(conn, "/users")
      refute html =~ instance.id
      {:ok, _view, html} = live(conn, "/users/#{instance.id}")
      assert html =~ "This flow is not available right now."

      # Reopened, everything is back
      {:ok, _} = Flows.update_status(flow, "open", [])
      {:ok, _view, html} = live(conn, "/users/#{instance.id}")
      assert html =~ "Dog License 2025"
    end

    test "a read-only flow's instances are seen but not continued; an archived one's vanish",
         %{conn: conn} do
      {:ok, flow} = Flows.create(%{name: "Dog License 2024", status: "open"})
      {:ok, instance} = Instances.Flows.create(%{flow_id: flow.id, user_id: "demo-user"})

      {:ok, _} = Flows.update_status(flow, "read_only", [])

      # Listed, as View — there is nothing to continue
      {:ok, view, html} = live(conn, "/users")
      assert html =~ instance.id
      assert has_element?(view, ~s(a[href="/users/#{instance.id}"]), "View")
      refute has_element?(view, ~s(a[href="/users/#{instance.id}"]), "Continue")

      # The instance page opens; a form's edit page says why it will not
      {:ok, _view, html} = live(conn, "/users/#{instance.id}")
      assert html =~ "Dog License 2024"
      {:ok, _view, html} = live(conn, "/users/#{instance.id}/forms/#{Ecto.UUID.generate()}/edit")
      assert html =~ "This flow is read-only now; your answers are kept as they are."

      {:ok, _} = Flows.update_status(flow, "archived", [])
      {:ok, _view, html} = live(conn, "/users")
      refute html =~ instance.id
      {:ok, _view, html} = live(conn, "/users/#{instance.id}")
      assert html =~ "This flow is not available right now."
    end
  end

  # ── the admin pages ─────────────────────────────────────────────────────

  describe "the admin pages" do
    test "the index and the show page draw the status", %{conn: conn} do
      {:ok, draft} = Flows.create(%{name: "Dog License 2027"})
      {:ok, open} = Flows.create(%{name: "Cat License", status: "open"})

      {:ok, view, _html} = live(conn, "/admin/flows")
      assert has_element?(view, ".badge", "Draft")
      assert has_element?(view, ".badge", "Open")

      {:ok, view, _html} = live(conn, "/admin/flows/#{draft.id}")
      assert has_element?(view, ".badge", "Draft")

      {:ok, view, _html} = live(conn, "/admin/flows/#{open.id}")
      assert has_element?(view, ".badge", "Open")
    end

    test "the edit page's status dropdown explains the choice, and Save writes it with its event",
         %{conn: conn} do
      {:ok, flow} = Flows.create(%{name: "Dog License"})

      {:ok, view, html} = live(conn, "/admin/flows/#{flow.id}/edit")

      # The saved status, its summary, and who it reaches
      assert has_element?(view, "option[value=draft]", "Draft")
      assert has_element?(view, "option[value=open]", "Open")
      assert has_element?(view, "option[value=winding_down]", "Winding down")
      assert html =~ "Not offered to users"
      assert html =~ "Nobody has started this flow yet."

      # Picking another redraws the summary and counts as an unsaved change —
      # the choice reaches the page through send_update, so read it again
      view
      |> element("#flows-edit-flow-form-form")
      |> render_change(%{"dynamic_form" => %{"status" => "open"}})

      html = render(view)
      assert html =~ "Offered to users"
      assert has_element?(view, "button", "Discard changes")

      # Save writes the status through update_status/3: one event, signed by
      # the page's admin
      view |> element("button", "Save") |> render_click()

      assert Flows.get(flow.id).status == "open"

      assert [
               %{event: "created"},
               %{event: "status_changed", user_id: "demo-admin", snapshot: snapshot}
             ] =
               events(flow)

      assert snapshot == %{"from" => "draft", "to" => "open"}

      # Saving again with the status unchanged writes nothing
      view |> element("button", "Save") |> render_click()
      assert length(events(flow)) == 2
    end

    test "the summary counts the instances a change reaches", %{conn: conn} do
      {:ok, flow} = Flows.create(%{name: "Dog License", status: "open"})
      {:ok, _} = Instances.Flows.create(%{flow_id: flow.id, user_id: "a"})
      {:ok, done} = Instances.Flows.create(%{flow_id: flow.id, user_id: "b"})
      {:ok, _} = Instances.Flows.complete(done, [])

      {:ok, _view, html} = live(conn, "/admin/flows/#{flow.id}/edit")

      assert html =~ "2 instances started, 1 still in progress."
    end

    test "the show page's badge opens a dialog that changes the status and logs it", %{conn: conn} do
      {:ok, flow} = Flows.create(%{name: "Dog License"})

      {:ok, view, _html} = live(conn, "/admin/flows/#{flow.id}")

      html = view |> element("button[phx-click=request_status]") |> render_click()
      assert html =~ "Change the status of “Dog License”"
      assert html =~ "Not offered to users"
      assert has_element?(view, "option[value=read_only]", "Read only")
      assert has_element?(view, "option[value=archived]", "Archived")

      # Picking redraws the summary; Cancel closes without a write
      html =
        view
        |> element("form[phx-submit=save_status]")
        |> render_change(%{"status" => "read_only"})

      assert html =~ "Nothing changes: nobody can start or continue."
      refute view |> element("button", "Cancel") |> render_click() =~ "Change the status"
      assert Flows.get(flow.id).status == "draft"

      # Save writes it, signed by the page's admin, and the badge follows
      view |> element("button[phx-click=request_status]") |> render_click()

      html =
        view
        |> element("form[phx-submit=save_status]")
        |> render_submit(%{"status" => "open"})

      refute html =~ "Change the status"
      assert has_element?(view, ".badge", "Open")
      assert Flows.get(flow.id).status == "open"

      assert [
               %{event: "created"},
               %{event: "status_changed", user_id: "demo-admin", snapshot: snapshot}
             ] =
               events(flow)

      assert snapshot == %{"from" => "draft", "to" => "open"}
    end

    test "the index's row menu changes the status too, and the listing follows", %{conn: conn} do
      {:ok, flow} = Flows.create(%{name: "Dog License", status: "open"})
      menu = "#flow-#{flow.id}-actions"

      {:ok, view, _html} = live(conn, "/admin/flows")

      html = view |> element("#{menu} button", "Change status") |> render_click()
      assert html =~ "Change the status of “Dog License”"
      assert html =~ "Offered to users"

      view
      |> element("form[phx-submit=save_status]")
      |> render_submit(%{"status" => "winding_down"})

      {path, _flash} = assert_redirect(view)
      assert path =~ "/admin/flows"
      assert Flows.get(flow.id).status == "winding_down"

      assert [%{event: "created"}, %{event: "status_changed", user_id: "demo-admin"}] =
               events(flow)

      {:ok, view, _html} = live(conn, path)
      assert has_element?(view, ".badge", "Winding down")
    end

    test "an owned subflow has no status field: status is the root's", %{conn: conn} do
      {:ok, root} = Flows.create(%{name: "Licensing", label: "subflows"})
      {:ok, owned} = Flows.create(%{name: "Application", owner_flow_id: root.id})

      {:ok, view, html} = live(conn, "/admin/flows/#{owned.id}/edit")

      refute has_element?(view, "option[value=draft]")
      refute html =~ "Not offered to users"
    end
  end

  defp events(flow) do
    FormFlowRepo.all(
      from(e in Flow.Event,
        where: e.flow_id == ^flow.id,
        order_by: [asc: e.inserted_at, asc: e.id]
      )
    )
  end

  defp start_button(flow), do: "button[phx-value-flow-id='#{flow.id}']"
end
