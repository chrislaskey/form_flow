defmodule Demo.FormFlowFlowStatusTest do
  @moduledoc """
  A flow's status — `draft`, `pre_release`, `open`, `winding_down`,
  `read_only`, `archived` — and the event log that records how it got there
  (`FormFlow.Data.Templates.Flow.Event`), against a real database: the data
  layer's writes and refusals, and what each status does on the user-facing
  pages and the admin pages.

  `/users` is the demo's page, which names `demo-user` among its pre-release
  users; `UnlistedPage` below is the same router with nobody named, for the
  other side of that rule.
  """

  use DemoWeb.ConnCase, async: false

  defmodule UnlistedPage do
    use Phoenix.LiveView

    @impl true
    def mount(_params, %{"path" => path} = session, socket) do
      {:ok,
       Phoenix.Component.assign(socket,
         path: path,
         uri: "http://localhost/users/#{Enum.join(path, "/")}",
         params: %{},
         flows: Map.get(session, "flows")
       )}
    end

    @impl true
    def render(assigns) do
      ~H"""
      <FormFlow.Web.router
        user_id="demo-user"
        uri={@uri}
        params={@params}
        path={@path}
        base="/users"
        flows={@flows}
      />
      """
    end
  end

  # The same router with `pre_release_user_ids` as a function of the page's
  # context — a role, decided per viewer — rather than a list
  defmodule RolePage do
    use Phoenix.LiveView

    @impl true
    def mount(_params, %{"path" => path, "staff" => staff?}, socket) do
      {:ok,
       Phoenix.Component.assign(socket,
         path: path,
         uri: "http://localhost/users/#{Enum.join(path, "/")}",
         params: %{},
         pre_release_user_ids: fn context, _callback_data ->
           if staff?, do: [context.user_id], else: []
         end
       )}
    end

    @impl true
    def render(assigns) do
      ~H"""
      <FormFlow.Web.router
        user_id="demo-user"
        uri={@uri}
        params={@params}
        path={@path}
        base="/users"
        pre_release_user_ids={@pre_release_user_ids}
      />
      """
    end
  end

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

    test "the data layer does what it is asked, whatever the status — the pages are the gate" do
      {:ok, draft} = Flows.create(%{name: "Draft"})
      {:ok, archived} = Flows.create(%{name: "Archived", status: "archived"})

      # A support tool repairing a record, an appeal after the deadline
      assert {:ok, _} = Instances.Flows.create(%{flow_id: draft.id, user_id: "u"})
      assert {:ok, instance} = Instances.Flows.create(%{flow_id: archived.id, user_id: "u"})

      # Continuing is refused for reasons of its own (no such position), never
      # for the status
      assert {:error, :unknown_position} =
               Instances.Forms.update_status(instance, [Ecto.UUID.generate()], :in_progress)
    end

    test "a pre-release flow takes a start from anyone at the data layer, and marks the journey" do
      {:ok, flow} = Flows.create(%{name: "Dog License 2027", status: "pre_release"})

      {:ok, instance} = Instances.Flows.create(%{flow_id: flow.id, user_id: "anyone"})
      assert instance.metadata == %{"form_flow" => %{"pre_release" => true}}

      # The host's own metadata is kept beside the marker
      {:ok, instance} =
        Instances.Flows.create(%{flow_id: flow.id, user_id: "b", metadata: %{"host" => 1}})

      assert instance.metadata == %{"host" => 1, "form_flow" => %{"pre_release" => true}}

      # An open flow marks nothing
      {:ok, open} = Flows.create(%{name: "Cat License", status: "open"})
      {:ok, instance} = Instances.Flows.create(%{flow_id: open.id, user_id: "c"})
      assert instance.metadata == %{}
    end

    test "list_pre_release/1 and delete_pre_release/2 act on the marked journeys alone" do
      {:ok, flow} = Flows.create(%{name: "Dog License 2027", status: "open"})
      {:ok, real} = Instances.Flows.create(%{flow_id: flow.id, user_id: "a"})

      # Nothing marked: nothing deleted, nothing logged
      assert Instances.Flows.list_pre_release(flow) == []
      assert Instances.Flows.delete_pre_release(flow, user_id: "demo-admin") == {:ok, 0}
      assert [%{event: "created"}] = events(flow)

      {:ok, flow} = Flows.update_status(flow, "pre_release", [])
      {:ok, trial} = Instances.Flows.create(%{flow_id: flow.id, user_id: "b"})
      assert Instances.Flow.pre_release?(trial)
      refute Instances.Flow.pre_release?(real)
      assert [%{id: id}] = Instances.Flows.list_pre_release(flow)
      assert id == trial.id

      # The trial run goes, trail and all; the real instance stays; one event says how many
      assert {:ok, 1} = Instances.Flows.delete_pre_release(flow, user_id: "demo-admin")
      refute Instances.Flows.get(trial.id)
      assert Instances.Flows.get(real.id)

      assert FormFlowRepo.all(
               from(e in Instances.Flow.Event, where: e.instance_flow_id == ^trial.id)
             ) == []

      assert [
               _created,
               _status_changed,
               %{
                 event: "pre_release_instances_deleted",
                 snapshot: %{"count" => 1},
                 user_id: "demo-admin"
               }
             ] = events(flow)
    end

    test "an owned subflow has no log of its own" do
      {:ok, root} = Flows.create(%{name: "Licensing", label: "subflows"}, user_id: "demo-admin")
      {:ok, owned} = Flows.create(%{name: "Application", owner_flow_id: root.id})

      assert events(owned) == []
      assert [%{event: "created", user_id: "demo-admin"}] = events(root)
    end

    test "update_status/3 logs the status the flow had at the write, not the one loaded" do
      {:ok, flow} = Flows.create(%{name: "Dog License"})
      {:ok, _} = Flows.update_status(flow, "open", [])

      # A second admin still holds the draft struct
      {:ok, _} = Flows.update_status(flow, "winding_down", user_id: "late-admin")

      assert [_, _, %{snapshot: %{"from" => "open", "to" => "winding_down"}}] = events(flow)
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
      # /users names no flows, so a winding-down one is neither offered nor
      # announced; a page that names it gets the line (tested below)
      refute html =~ "Dog License 2025"
      refute html =~ "Dog License 2027"
      refute html =~ "No flows are open."
    end

    test "a pre-release flow is open to the users a page names and a draft to the rest",
         %{conn: conn} do
      {:ok, flow} = Flows.create(%{name: "Dog License 2027", status: "pre_release"})
      {:ok, instance} = Instances.Flows.create(%{flow_id: flow.id, user_id: "demo-user"})

      # /users names demo-user: offered, listed, and open
      {:ok, view, html} = live(conn, "/users")
      assert has_element?(view, start_button(flow))
      assert html =~ instance.id
      {:ok, _view, html} = live(conn, "/users/#{instance.id}")
      assert html =~ "Dog License 2027"

      # A page naming nobody: nothing offered, nothing listed, the page refused
      {:ok, view, html} = live_isolated(conn, UnlistedPage, session: %{"path" => []})
      refute has_element?(view, start_button(flow))
      refute html =~ instance.id
      refute html =~ "Dog License 2027"

      {:ok, _view, html} =
        live_isolated(conn, UnlistedPage, session: %{"path" => [instance.id]})

      assert html =~ "This flow is not available right now."
    end

    test "pre_release_user_ids takes a function of the page's context as well as a list",
         %{conn: conn} do
      {:ok, flow} = Flows.create(%{name: "Dog License 2027", status: "pre_release"})
      {:ok, instance} = Instances.Flows.create(%{flow_id: flow.id, user_id: "demo-user"})

      # The function names the viewer: offered, listed, and open
      staff = %{"staff" => true}
      {:ok, view, html} = live_isolated(conn, RolePage, session: Map.put(staff, "path", []))
      assert has_element?(view, start_button(flow))
      assert html =~ instance.id

      {:ok, _view, html} =
        live_isolated(conn, RolePage, session: Map.put(staff, "path", [instance.id]))

      assert html =~ "Dog License 2027"

      # The function does not: a draft to this viewer
      public = %{"staff" => false}
      {:ok, view, html} = live_isolated(conn, RolePage, session: Map.put(public, "path", []))
      refute has_element?(view, start_button(flow))
      refute html =~ instance.id

      {:ok, _view, html} =
        live_isolated(conn, RolePage, session: Map.put(public, "path", [instance.id]))

      assert html =~ "This flow is not available right now."
    end

    test "the winding-down line is drawn for flows the page names, not for every root",
         %{conn: conn} do
      {:ok, winding} = Flows.create(%{name: "Dog License 2025", status: "winding_down"})

      {:ok, _view, html} = live_isolated(conn, UnlistedPage, session: %{"path" => []})
      refute html =~ "Dog License 2025"

      {:ok, _view, html} =
        live_isolated(conn, UnlistedPage, session: %{"path" => [], "flows" => [winding.slug]})

      assert html =~ "Dog License 2025"
      assert html =~ "No longer taking new starts."
    end

    test "with nothing open the listing says so", %{conn: conn} do
      {:ok, _draft} = Flows.create(%{name: "Dog License 2027"})

      {:ok, _view, html} = live(conn, "/users")

      assert html =~ "No flows are open."
    end

    test "a start is refused at the click once the flow stops taking them", %{conn: conn} do
      {:ok, flow} = Flows.create(%{name: "Cat License", status: "open"})

      {:ok, view, _html} = live(conn, "/users")
      assert has_element?(view, start_button(flow))

      # The flow winds down after the page drew; the page asks again at the
      # click, from the row as it now is
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

    test "a status the flow cannot have is ignored by the edit page, not a crash", %{conn: conn} do
      {:ok, flow} = Flows.create(%{name: "Dog License"})

      {:ok, view, _html} = live(conn, "/admin/flows/#{flow.id}/edit")

      view
      |> element("#flows-edit-flow-form-form")
      |> render_change(%{"dynamic_form" => %{"status" => "closed"}})

      # The choice is dropped; the page and its Save carry on
      assert render(view) =~ "Not offered to users"
      view |> element("button", "Save") |> render_click()
      assert Flows.get(flow.id).status == "draft"
      assert [%{event: "created"}] = events(flow)
    end

    test "a flow made on the New page has its creator; a duplicate has its copier", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/flows/new")
      view |> element("form") |> render_submit(%{"name" => "Dog License", "label" => "forms"})
      {path, _flash} = assert_redirect(view)
      ["", "admin", "flows", id, "edit"] = String.split(path, "/")

      assert [%{event: "created", user_id: "demo-admin"}] = events(Flows.get(id))

      {:ok, view, _html} = live(conn, "/admin/flows/#{id}")
      view |> element("button", "Duplicate Flow") |> render_click()
      view |> element("form[phx-submit=copy]") |> render_submit(%{"name" => "", "slug" => ""})
      {path, _flash} = assert_redirect(view)
      "/admin/flows/" <> copy_id = path

      assert [%{event: "created", user_id: "demo-admin"}] = events(Flows.get(copy_id))
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
      assert has_element?(view, "option[value=read_only]", "Read-only")
      assert has_element?(view, "option[value=pre_release]", "Pre-release")
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

    test "the index puts archived flows away until asked", %{conn: conn} do
      {:ok, open} = Flows.create(%{name: "Dog License", status: "open"})
      {:ok, archived} = Flows.create(%{name: "Dog License 2024", status: "archived"})

      {:ok, view, html} = live(conn, "/admin/flows")
      assert html =~ "Dog License"
      refute html =~ "Dog License 2024"
      assert has_element?(view, "#flows-archived-toggle", "1 archived flow hidden.")

      # Show archived patches the URL; the archived row is listed, greyed
      html = view |> element("#flows-archived-toggle a", "Show archived") |> render_click()
      assert_patch(view, "/admin/flows?archived=true")
      assert html =~ "Dog License 2024"
      assert has_element?(view, "a.text-zinc-400[href='/admin/flows/#{archived.id}']")
      assert has_element?(view, "#flows-archived-toggle a", "Hide archived")

      # The URL keeps it, with the sort; Hide archived takes it off and keeps the sort
      {:ok, view, html} = live(conn, "/admin/flows?archived=true&sort=name")
      assert html =~ "Dog License 2024"
      view |> element("#flows-archived-toggle a", "Hide archived") |> render_click()
      assert_patch(view, "/admin/flows?sort=name")
      refute render(view) =~ "Dog License 2024"

      # Nothing but archived flows: no table, a sentence, and the link
      {:ok, _flow} = Flows.update_status(open, "archived", [])
      {:ok, view, html} = live(conn, "/admin/flows")
      assert html =~ "Every flow here is archived."
      refute html =~ "<table"
      refute has_element?(view, "#flows-archived-toggle")
      html = view |> element("a", "Show archived") |> render_click()
      assert_patch(view, "/admin/flows?archived=true")
      assert html =~ "<table"
      assert html =~ "Dog License 2024"
    end

    test "leaving pre-release offers to delete the trial run, and deleting is logged",
         %{conn: conn} do
      {:ok, flow} = Flows.create(%{name: "Dog License 2027", status: "open"})
      {:ok, real} = Instances.Flows.create(%{flow_id: flow.id, user_id: "a"})
      {:ok, flow} = Flows.update_status(flow, "pre_release", [])
      {:ok, trial_1} = Instances.Flows.create(%{flow_id: flow.id, user_id: "demo-user"})
      {:ok, trial_2} = Instances.Flows.create(%{flow_id: flow.id, user_id: "b"})

      {:ok, view, _html} = live(conn, "/admin/flows/#{flow.id}")
      html = view |> element("button[phx-click=request_status]") |> render_click()

      # No offer until another status is picked; picking back withdraws it
      refute html =~ "started during pre-release"
      form = element(view, "form[phx-submit=save_status]")
      html = render_change(form, %{"status" => "open"})
      assert html =~ "2 instances were started during pre-release."

      assert has_element?(
               view,
               "#status-dialog-pre-release input[type=checkbox][name=delete_pre_release]"
             )

      refute has_element?(view, "#status-dialog-delete-pre-release[checked]")
      refute render_change(form, %{"status" => "pre_release"}) =~ "started during pre-release"

      # Ticking survives the redraw
      render_change(form, %{"status" => "open", "delete_pre_release" => "true"})
      assert has_element?(view, "#status-dialog-delete-pre-release[checked]")

      # Save with the box: the trial run is gone, the real instance stays, and
      # the log has both the change and the deletion
      render_submit(form, %{"status" => "open", "delete_pre_release" => "true"})
      assert Flows.get(flow.id).status == "open"
      assert Instances.Flows.get(real.id)
      refute Instances.Flows.get(trial_1.id)
      refute Instances.Flows.get(trial_2.id)

      assert [
               %{event: "created"},
               %{event: "status_changed"},
               %{event: "status_changed", snapshot: %{"from" => "pre_release", "to" => "open"}},
               %{
                 event: "pre_release_instances_deleted",
                 snapshot: %{"count" => 2},
                 user_id: "demo-admin"
               }
             ] = events(flow)

      {:ok, _view, html} = live(conn, "/admin/flows/#{flow.id}/history")
      assert html =~ "Deleted 2 instances started during pre-release"
    end

    test "the box left unticked deletes nothing, and no other move offers it", %{conn: conn} do
      {:ok, flow} = Flows.create(%{name: "Dog License 2027", status: "pre_release"})
      {:ok, trial} = Instances.Flows.create(%{flow_id: flow.id, user_id: "demo-user"})
      menu = "#flow-#{flow.id}-actions"

      # From the index's dialog, the offer made and declined
      {:ok, view, _html} = live(conn, "/admin/flows")
      view |> element("#{menu} button", "Change status") |> render_click()
      form = element(view, "form[phx-submit=save_status]")

      assert render_change(form, %{"status" => "open"}) =~
               "1 instance was started during pre-release."

      render_submit(form, %{"status" => "open"})
      assert_redirect(view)
      assert Flows.get(flow.id).status == "open"
      assert Instances.Flows.get(trial.id)
      assert [%{event: "created"}, %{event: "status_changed"}] = events(flow)

      # An open flow with a marked instance left over: no offer on any move,
      # and a box sent anyway deletes nothing
      {:ok, view, _html} = live(conn, "/admin/flows/#{flow.id}")
      view |> element("button[phx-click=request_status]") |> render_click()
      form = element(view, "form[phx-submit=save_status]")

      refute render_change(form, %{"status" => "winding_down", "delete_pre_release" => "true"}) =~
               "started during pre-release"

      render_submit(form, %{"status" => "winding_down", "delete_pre_release" => "true"})
      assert Flows.get(flow.id).status == "winding_down"
      assert Instances.Flows.get(trial.id)
    end

    test "the history page lists the log newest first, reached from the show page and the index",
         %{conn: conn} do
      {:ok, flow} = Flows.create(%{name: "Dog License"}, user_id: "demo-admin")
      {:ok, flow} = Flows.update_status(flow, "open", user_id: "demo-admin")
      {:ok, _flow} = Flows.update_status(flow, "winding_down", [])

      {:ok, view, html} = live(conn, "/admin/flows/#{flow.id}/history")

      assert has_element?(view, "h2", "Dog License")
      assert has_element?(view, "h2", "History")
      assert has_element?(view, "nav", "History")

      # Newest first, each with what happened and who did it
      positions =
        for line <- ["Open → Winding down", "Draft → Open", "Created"] do
          {position, _length} = :binary.match(html, line)
          position
        end

      assert positions == Enum.sort(positions)
      assert has_element?(view, "#flows-history-events li", "Open → Winding down")

      assert html =~ "by demo-admin"
      assert html =~ "by nobody recorded"
      assert html =~ "just now"

      # An owned subflow's history is its root's
      {:ok, owned} = Flows.create(%{name: "Application", owner_flow_id: flow.id})
      {:ok, view, _html} = live(conn, "/admin/flows/#{owned.id}/history")
      assert has_element?(view, "h2", "Dog License")

      # A row written past the data layer — a seed, a host — has no log, and
      # the page says so rather than drawing an empty list
      {:ok, seeded} = FormFlowRepo.insert(Flow.changeset(%Flow{}, %{name: "Seeded"}))
      {:ok, _view, html} = live(conn, "/admin/flows/#{seeded.id}/history")
      assert html =~ "Nothing has been recorded for this flow."

      # Reached from the show page and the index's menu; a missing flow says so
      {:ok, view, _html} = live(conn, "/admin/flows/#{flow.id}")
      assert has_element?(view, ~s(a[href="/admin/flows/#{flow.id}/history"]), "History")
      {:ok, view, _html} = live(conn, "/admin/flows")

      assert has_element?(
               view,
               ~s(#flow-#{flow.id}-actions a[href="/admin/flows/#{flow.id}/history"]),
               "History"
             )

      {:ok, _view, html} = live(conn, "/admin/flows/#{Ecto.UUID.generate()}/history")
      assert html =~ "Flow not found."
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
