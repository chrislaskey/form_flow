defmodule Demo.FormFlowInstancesTest do
  @moduledoc """
  Exercises the user-facing pages — the flow instance's listing and the form
  pages — against a real database and a real LiveView mount.

  Two things are proven here that the library's own tests can't reach. First,
  that a stored `form_flow_type` changes what a user sees: which forms offer
  to start, which of them are navigable, and where the flow's progress is
  drawn — the demo's own type included, which is the only place the whole
  `FormFlow.Config` → `FormFlow.Config.Flows.Type` path runs end to end.
  Second, that the URLs address *positions*: `/edit` starts the form it
  names, on an ordinary page load, and only where the flow's type allows work
  — so the address bar can't walk around the flow.
  """

  use DemoWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest

  alias FormFlow.Context
  alias FormFlow.Data.Instances
  alias FormFlow.Data.Instances.FlowProgress
  alias FormFlow.Data.Repo, as: FormFlowRepo
  alias FormFlow.Data.Templates.Flow
  alias FormFlow.Data.Templates.Flows
  alias FormFlow.Data.Templates.Forms

  # ── a host's form types, for the completion callbacks ───────────────────

  # Broadcasts what each completion callback received, so a test can see the
  # context the library handed it, and records what it saw of the form
  defmodule Recording do
    use FormFlow.Config.Forms.Type

    @impl true
    def snapshot_data(context, _callback_data) do
      Phoenix.PubSub.broadcast(Demo.PubSub, "form_flow_test", {:snapshot_data, context})
      %{"seen" => %{"status" => context.form_instance.status}}
    end

    @impl true
    def handle_complete(context, _callback_data) do
      Phoenix.PubSub.broadcast(Demo.PubSub, "form_flow_test", {:handle_complete, context})
    end
  end

  defmodule RefusingRecord do
    use FormFlow.Config.Forms.Type

    @impl true
    def snapshot_data(_context, _callback_data), do: raise("nothing to record")
  end

  defmodule FailingReaction do
    use FormFlow.Config.Forms.Type

    @impl true
    def handle_complete(_context, _callback_data), do: raise("the host's job queue is down")
  end

  # The demo's type lists with the three types above beside the library's —
  # every flow type for applicants or reviewers, the vocabulary being the
  # type's, set on the library's wizards too
  defmodule TestTypes do
    def flow_types do
      perspectives = [
        %FormFlow.Config.Flows.Perspective{id: "applicant", name: "Applicant"},
        %FormFlow.Config.Flows.Perspective{id: "reviewer", name: "Reviewer"}
      ]

      Enum.map(FormFlow.Config.Flows.Type.defaults(), &%{&1 | perspectives: perspectives})
    end

    def form_types do
      FormFlow.Config.Forms.Type.defaults() ++
        [
          %FormFlow.Config.Forms.Type{id: "recording", module: Recording, name: "Recording"},
          %FormFlow.Config.Forms.Type{id: "refusing", module: RefusingRecord, name: "Refusing"},
          %FormFlow.Config.Forms.Type{id: "failing", module: FailingReaction, name: "Failing"}
        ]
    end
  end

  # The test page's gate: refuses, redirects, or decorates by the flow's name,
  # so one function exercises every answer on_mount can give; on the listing,
  # which has no flow in scope, the page's callback_data drives it — the
  # host's own data reaching the host's own gate
  defmodule TestGate do
    def on_mount(%Context{flow: %{name: "Refused"}}, _callback_data),
      do: {:error, "You may not see this flow."}

    def on_mount(%Context{flow: %{name: "Elsewhere"}}, _callback_data),
      do: {:redirect, "/users"}

    def on_mount(%Context{flow: %{name: "Decorated"}}, _callback_data),
      do: {:ok, %{flow_name: "Renamed by the host"}}

    def on_mount(%Context{flow: nil}, %{"listing" => "refused"}),
      do: {:error, "No listing for you."}

    def on_mount(%Context{flow: nil}, %{"listing" => "elsewhere"}),
      do: {:redirect, "/users"}

    def on_mount(_context, _callback_data), do: {:ok, %{}}
  end

  # The users page as `DemoWeb.FormFlowLive.Users` renders it, with the test
  # types and gate in place of the demo's — mounted without a route
  # (live_isolated/3). The session's "callback_data" is the page's
  # callback_data, and also picks the listing's `instances` ("listing" =>
  # "everyone") and `flows` ("offer" => slug), the way a host page would
  # build those attrs from what it knows.
  defmodule TestPage do
    use Phoenix.LiveView

    @impl true
    def mount(_params, %{"path" => path} = session, socket) do
      callback_data = Map.get(session, "callback_data", %{})

      {:ok,
       Phoenix.Component.assign(socket,
         path: path,
         uri: "http://localhost/users/#{Enum.join(path, "/")}",
         params: %{},
         tenant_id: Map.get(session, "tenant_id"),
         perspectives: Map.get(session, "perspectives", []),
         callback_data: callback_data,
         instances: instances(callback_data),
         flows: flows(callback_data)
       )}
    end

    defp instances(%{"listing" => "everyone"}), do: Instances.Flows.list_query()
    defp instances(_callback_data), do: nil

    defp flows(%{"offer" => slug}), do: [slug]
    defp flows(_callback_data), do: nil

    @impl true
    def render(assigns) do
      ~H"""
      <FormFlow.Web.router
        user_id="demo-user"
        tenant_id={@tenant_id}
        perspectives={@perspectives}
        uri={@uri}
        params={@params}
        path={@path}
        base="/users"
        flow_types={TestTypes.flow_types()}
        form_types={TestTypes.form_types()}
        callback_data={@callback_data}
        on_mount={&TestGate.on_mount/2}
        instances={@instances}
        flows={@flows}
      />
      """
    end
  end

  describe "a flow instance's page" do
    test "in order offers the first form only", %{conn: conn} do
      %{instance: instance, forms: [name, address]} = flow_of_two("wizard_in_order")

      {:ok, view, html} = live(conn, flow_path(instance))

      assert html =~ "Available"
      assert html =~ "Pending"
      assert has_element?(view, "a[href='#{edit_path(instance, [name.id])}']")
      refute has_element?(view, "a[href='#{edit_path(instance, [address.id])}']")
    end

    test "any order offers every form, so a user can start anywhere", %{conn: conn} do
      %{instance: instance, forms: [name, address]} = flow_of_two("wizard_any_order")

      {:ok, view, _html} = live(conn, flow_path(instance))

      assert has_element?(view, "a[href='#{edit_path(instance, [name.id])}']")
      assert has_element?(view, "a[href='#{edit_path(instance, [address.id])}']")
    end

    test "a completed form links to its answers, not to its form", %{conn: conn} do
      %{instance: instance, forms: [name, _address]} = flow_of_two()
      complete(instance, [name.id])

      {:ok, view, _html} = live(conn, flow_path(instance))

      assert has_element?(view, "a[href='#{form_path(instance, [name.id])}']")
      refute has_element?(view, "a[href='#{edit_path(instance, [name.id])}']")
    end

    test "reopen refuses a position the page never drew", %{conn: conn} do
      %{instance: instance, forms: [name, _address]} = flow_of_two("wizard_any_order")
      complete(instance, [name.id])

      # A form node of an unrelated flow, published and so startable
      %{form: elsewhere} = flow_of_one(nil, name: "Somewhere else")

      {:ok, view, _html} = live(conn, flow_path(instance))

      view
      |> element("button[phx-value-path='#{name.id}']")
      |> render_click(%{"path" => elsewhere.id})

      # Unguarded this is not a reopen at all: the write falls through to the
      # create, which would start a form at a position this page never
      # offered, pinned to a version of another flow's form
      refute instance_at(instance, [elsewhere.id])
      assert %{status: "completed"} = instance_at(instance, [name.id])
    end
  end

  describe "an instance's host identities" do
    test "starting a form stamps the user on it", %{conn: conn} do
      %{instance: instance, forms: [name, _address]} = flow_of_two()

      {:ok, _view, _html} = live(conn, edit_path(instance, [name.id]))

      form_instance = instance_at(instance, [name.id])
      assert form_instance.user_id == "demo-user"
      assert form_instance.tenant_id == nil
    end

    test "a tenant is stamped on the journey and its forms, and narrows the listing" do
      %{flow: flow, forms: [name, _address]} = flow_of_two()

      {:ok, tenant_instance} =
        Instances.Flows.create(%{flow_id: flow.id, user_id: "demo-user", tenant_id: "acme"})

      {:ok, form_instance} =
        Instances.Forms.update_status(tenant_instance, [name.id], :in_progress,
          user_id: "demo-user",
          tenant_id: "acme"
        )

      assert tenant_instance.tenant_id == "acme"
      assert form_instance.tenant_id == "acme"

      assert [%{id: id}] = Instances.Flows.list(user_id: "demo-user", tenant_id: "acme")
      assert id == tenant_instance.id
      assert Instances.Flows.list(user_id: "demo-user", tenant_id: "other") == []
      assert length(Instances.Flows.list(user_id: "demo-user")) == 2
    end
  end

  describe "a form's URL addresses its position" do
    test "edit starts the form it names, on an ordinary page load", %{conn: conn} do
      %{instance: instance, forms: [name, _address]} = flow_of_two()

      refute instance_at(instance, [name.id])

      {:ok, _view, html} = live(conn, edit_path(instance, [name.id]))

      assert %{status: "in_progress"} = instance_at(instance, [name.id])
      assert html =~ "Name"
    end

    test "starting twice is the same instance, not a second one", %{conn: conn} do
      %{instance: instance, forms: [name, _address]} = flow_of_two()

      {:ok, _view, _html} = live(conn, edit_path(instance, [name.id]))
      started = instance_at(instance, [name.id])

      {:ok, _view, _html} = live(conn, edit_path(instance, [name.id]))

      assert instance_at(instance, [name.id]).id == started.id
      assert length(Instances.Flows.form_instances(instance)) == 1
    end

    test "show never starts anything — it offers the start instead", %{conn: conn} do
      %{instance: instance, forms: [name, _address]} = flow_of_two()

      {:ok, view, html} = live(conn, form_path(instance, [name.id]))

      refute instance_at(instance, [name.id])
      assert html =~ "haven&#39;t started this form yet"
      assert has_element?(view, "a[href='#{edit_path(instance, [name.id])}']")
    end

    test "the address bar cannot walk around the flow's type", %{conn: conn} do
      %{instance: instance, forms: [_name, address]} = flow_of_two("wizard_in_order")

      {:ok, _view, html} = live(conn, edit_path(instance, [address.id]))

      # The in-order wizard gates it, so nothing was created and nothing is
      # rendered but the explanation
      refute instance_at(instance, [address.id])
      assert html =~ "isn&#39;t available yet"
    end

    test "a form inside a subflow carries the whole path", %{conn: conn} do
      %{instance: instance, subflow_node: node, forms: [first, _second]} = nested_flow()

      {:ok, view, _html} = live(conn, flow_path(instance))

      assert has_element?(view, "a[href='#{edit_path(instance, [node.id, first.id])}']")

      {:ok, _view, _html} = live(conn, edit_path(instance, [node.id, first.id]))

      assert %{path: path} = instance_at(instance, [node.id, first.id])
      assert path == [node.id, first.id]
    end
  end

  describe "perspectives" do
    # Licensing: Start → Application (for applicants: Intake) → Review (for
    # reviewers: Review) → End
    defp licensing do
      {:ok, root} = Flows.create(%{name: "Licensing", label: "subflows"})

      application = owned_forms_flow(root, "Application", ["applicant"], "Intake")
      review = owned_forms_flow(root, "Review", ["reviewer"], "Review")

      first_node = build_node(root, ["Start"], "Start")
      application_node = subflow_node(root, application.flow, "Application")
      review_node = subflow_node(root, review.flow, "Review")
      last_node = build_node(root, ["End"], "End")

      edge(root, first_node, application_node)
      edge(root, application_node, review_node)
      edge(root, review_node, last_node)

      %{
        instance: start_flow(root),
        intake: [application_node.id, application.form.id],
        review: [review_node.id, review.form.id]
      }
    end

    defp owned_forms_flow(root, name, perspectives, form_label) do
      {:ok, flow} =
        Flows.create(%{
          name: name,
          label: "forms",
          owner_flow_id: root.id,
          properties: %{"perspectives" => perspectives}
        })

      first_node = build_node(flow, ["Start"], "Start")
      form = build_form_node(flow, form_label)
      last_node = build_node(flow, ["End"], "End")

      edge(flow, first_node, form)
      edge(flow, form, last_node)

      %{flow: flow, form: form}
    end

    test "the flow's page lists only the forms for the viewer's perspective", %{conn: conn} do
      %{instance: instance} = licensing()

      {:ok, _view, applicant} = as(conn, "applicant", [instance.id])
      assert applicant =~ "Application / Intake"
      refute applicant =~ "Review / Review"

      {:ok, _view, reviewer} = as(conn, "reviewer", [instance.id])
      assert reviewer =~ "Review / Review"
      refute reviewer =~ "Application / Intake"

      # A viewer with no perspective, and a viewer of both, sees everything
      {:ok, _view, everyone} = isolated(conn, [instance.id])
      assert everyone =~ "Application / Intake"
      assert everyone =~ "Review / Review"

      {:ok, _view, both} = as(conn, ["applicant", "reviewer"], [instance.id])
      assert both =~ "Application / Intake"
      assert both =~ "Review / Review"
    end

    test "a position for another perspective is refused, started or not", %{conn: conn} do
      %{instance: instance, intake: intake} = licensing()

      {:ok, _view, html} =
        as(conn, "reviewer", [instance.id, "forms"] ++ intake ++ ["edit"])

      assert html =~ "This form is not part of your work here."
      refute instance_at(instance, intake)

      complete(instance, intake, %{"name" => "Ada"})

      {:ok, _view, html} = as(conn, "reviewer", [instance.id, "forms"] ++ intake)
      assert html =~ "This form is not part of your work here."
      refute html =~ "Ada"

      # The applicant, whose form it is, sees the answers
      {:ok, _view, html} = as(conn, "applicant", [instance.id, "forms"] ++ intake)
      assert html =~ "Ada"
    end

    test "finishing your last form lands on the flow, which says your part is done",
         %{conn: conn} do
      %{instance: instance, intake: intake} = licensing()

      {:ok, view, _html} =
        as(conn, "applicant", [instance.id, "forms"] ++ intake ++ ["edit"])

      submit(view, instance_at(instance, intake), %{"name" => "Ada"})

      # Review is the next actionable position in the flow, but not the
      # applicant's — so the flow's page, not Review's edit page
      assert {path, _flash} = assert_redirect(view)
      assert path == flow_path(instance)

      {:ok, _view, html} = as(conn, "applicant", [instance.id])
      assert html =~ "Your part is done"
      assert html =~ "Done"

      # The reviewer's page has work waiting and no such notice
      {:ok, _view, html} = as(conn, "reviewer", [instance.id])
      refute html =~ "Your part is done"
      assert html =~ "Available"
    end

    test "a viewer with no perspective moves on to the next form, whoever it is for",
         %{conn: conn} do
      %{instance: instance, intake: intake, review: review} = licensing()

      {:ok, view, _html} = isolated_edit(conn, instance, intake)

      submit(view, instance_at(instance, intake), %{"name" => "Ada"})

      assert {path, _flash} = assert_redirect(view)
      assert path == edit_path(instance, review)
    end
  end

  describe "a form's page draws the flow's progress" do
    test "in order draws it, none of it navigable", %{conn: conn} do
      %{instance: instance, forms: [name, address]} = flow_of_two("wizard_in_order")

      {:ok, view, html} = live(conn, edit_path(instance, [name.id]))

      assert has_element?(view, "#instance-forms-edit-flow-progress")
      assert html =~ "Name"
      assert html =~ "Address"
      assert html =~ ~s(aria-current="step")
      refute has_element?(view, "a[href='#{edit_path(instance, [address.id])}']")
    end

    test "any order makes the other forms navigable", %{conn: conn} do
      %{instance: instance, forms: [name, address]} = flow_of_two("wizard_any_order")

      {:ok, view, _html} = live(conn, edit_path(instance, [name.id]))

      # The form being filled is never a link to itself — only the others are.
      refute has_element?(view, "a[href='#{edit_path(instance, [name.id])}']")
      assert has_element?(view, "a[href='#{edit_path(instance, [address.id])}']")
    end

    test "a lone form is no sequence, so nothing is drawn", %{conn: conn} do
      %{instance: instance, form: only} = flow_of_one()

      {:ok, view, _html} = live(conn, edit_path(instance, [only.id]))

      refute has_element?(view, "#instance-forms-edit-flow-progress")
    end
  end

  describe "show and edit are separate pages" do
    test "show renders the answers with no way to submit them", %{conn: conn} do
      %{instance: instance, forms: [name, _address]} = flow_of_two()
      {:ok, _view, _html} = live(conn, edit_path(instance, [name.id]))

      {:ok, view, html} = live(conn, form_path(instance, [name.id]))

      assert html =~ "Name"
      refute has_element?(view, "button[type='submit']")
      assert has_element?(view, "fieldset[disabled]")
      assert has_element?(view, "a[href='#{edit_path(instance, [name.id])}']")
    end

    test "edit renders a submittable form", %{conn: conn} do
      %{instance: instance, forms: [name, _address]} = flow_of_two()

      {:ok, view, _html} = live(conn, edit_path(instance, [name.id]))

      assert has_element?(view, "button[type='submit']")
      refute has_element?(view, "fieldset[disabled]")
    end

    test "edit sends an already-submitted form back to show", %{conn: conn} do
      %{instance: instance, forms: [name, _address]} = flow_of_two()
      complete(instance, [name.id])

      {:ok, view, html} = live(conn, edit_path(instance, [name.id]))

      assert html =~ "already been submitted"
      refute has_element?(view, "button[type='submit']")
      assert has_element?(view, "a[href='#{form_path(instance, [name.id])}']")
    end

    test "reopen lives with the answers, on show, and lands on edit", %{conn: conn} do
      %{instance: instance, forms: [name, _address]} = flow_of_two()
      complete(instance, [name.id])

      {:ok, view, _html} = live(conn, form_path(instance, [name.id]))

      view |> element("button", "Reopen") |> render_click()

      assert {path, _flash} = assert_redirect(view)
      assert path == edit_path(instance, [name.id])
      assert %{status: "in_progress"} = instance_at(instance, [name.id])
    end
  end

  describe "what a form page draws when there are no answers to draw" do
    test "a position the flow no longer has says so", %{conn: conn} do
      %{instance: instance, forms: [_name, address]} = flow_of_two()
      {:ok, _node} = Flows.delete_node(address)

      {:ok, _view, html} = live(conn, form_path(instance, [address.id]))
      assert html =~ "This form is not part of this flow."

      {:ok, _view, html} = live(conn, edit_path(instance, [address.id]))
      assert html =~ "This form is not part of this flow."
      refute instance_at(instance, [address.id])
    end

    test "a stranded position that was filled in still shows its answers", %{conn: conn} do
      %{instance: instance, forms: [_name, address]} = flow_of_two()
      complete(instance, [address.id], %{"name" => "Ada"})
      {:ok, _node} = Flows.delete_node(address)

      {:ok, view, html} = live(conn, form_path(instance, [address.id]))

      assert html =~ "Ada"
      refute html =~ "This form is not part of this flow."

      # Everything the page draws here works: a button that does nothing
      # when clicked is the thing the page's state is there to prevent
      assert has_element?(view, "button", "Download PDF")

      view |> element("button", "Reopen") |> render_click()
      assert %{status: "in_progress"} = instance_at(instance, [address.id])
    end

    test "the flow instance's page lists no stranded position, and offers none", %{conn: conn} do
      %{instance: instance, forms: [_name, address]} = flow_of_two()
      complete(instance, [address.id], %{"name" => "Ada"})
      {:ok, _node} = Flows.delete_node(address)

      {:ok, view, html} = live(conn, flow_path(instance))

      # Reopening a stranded position is reachable from its own page, not
      # from here: this page counts them and sends the user to an admin
      refute has_element?(view, "button", "Reopen")
      assert html =~ "positions this flow no longer has"
    end

    test "a form that comes later in the flow says so, on show as on edit", %{conn: conn} do
      %{instance: instance, forms: [_name, address]} = flow_of_two("wizard_in_order")

      {:ok, _view, html} = live(conn, form_path(instance, [address.id]))

      assert html =~ "isn&#39;t available yet"
      refute instance_at(instance, [address.id])
    end

    test "edit says why it could not start the form", %{conn: conn} do
      %{instance: instance, form: only} = flow_of_one_unpublished()

      {:ok, _view, html} = live(conn, edit_path(instance, [only.id]))

      assert html =~ "has no published version yet"
      refute instance_at(instance, [only.id])
    end

    test "a definition that will not parse is an inline error, not a crash", %{conn: conn} do
      # A question with no name: the parser raises on it, which is what a
      # malformed stored definition looks like from the page's side
      %{instance: instance, form: only} =
        flow_of_one(nil, definition: %{"elements" => [%{"type" => "text"}]})

      {:ok, _started} = Instances.Forms.update_status(instance, [only.id], :in_progress)

      {:ok, _view, html} = live(conn, form_path(instance, [only.id]))
      assert html =~ "This form can&#39;t be rendered."

      {:ok, _view, html} = live(conn, edit_path(instance, [only.id]))
      assert html =~ "This form can&#39;t be rendered."
    end

    test "a submitted form with a broken definition says so, not that it was submitted",
         %{conn: conn} do
      # The parse error outranks "already submitted" on edit: there is
      # nothing to edit either way, and this is the more informative of the
      # two. Show has said the parse error all along.
      %{instance: instance, form: only} =
        flow_of_one(nil, definition: %{"elements" => [%{"type" => "text"}]})

      complete(instance, [only.id])

      {:ok, _view, html} = live(conn, edit_path(instance, [only.id]))

      assert html =~ "This form can&#39;t be rendered."
      refute html =~ "already been submitted"
    end
  end

  describe "several flows in one instance" do
    test "each subflow's own type answers for its own forms", %{conn: conn} do
      {:ok, root} = Flows.create(%{name: "Onboarding", label: "subflows"})

      %{flow: documents, forms: [doc_first, doc_second]} =
        owned_flow_of_two(root, "Documents", "wizard_in_order")

      %{flow: details, forms: [detail_first, detail_second]} =
        owned_flow_of_two(root, "Details", "wizard_any_order")

      first_node = build_node(root, ["Start"], "Start")
      documents_node = subflow_node(root, documents, "Documents")
      details_node = subflow_node(root, details, "Details")

      edge(root, first_node, documents_node)
      edge(root, documents_node, details_node)

      instance = start_flow(root)

      {:ok, view, html} = live(conn, flow_path(instance))

      # Forms are labeled by the subflow they were reached through
      assert html =~ "Documents / First"
      assert html =~ "Details / Second"

      # The in-order subflow gates its second form; the any-order one doesn't
      assert offered?(view, instance, [documents_node.id, doc_first.id])
      refute offered?(view, instance, [documents_node.id, doc_second.id])
      assert offered?(view, instance, [details_node.id, detail_first.id])
      assert offered?(view, instance, [details_node.id, detail_second.id])
    end
  end

  describe "the demo's own type" do
    test "the config resolves \"demo_checklist\" to the demo's module", %{conn: conn} do
      %{instance: instance, forms: [name, address]} = flow_of_two("demo_checklist")

      {:ok, view, _html} = live(conn, flow_path(instance))

      # editable?/2: nothing is gated on the flow's order
      assert offered?(view, instance, [name.id])
      assert offered?(view, instance, [address.id])
    end

    test "its progress_component/1 draws the list even for a single form", %{conn: conn} do
      %{instance: instance, form: only} = flow_of_one("demo_checklist")

      {:ok, view, _html} = live(conn, edit_path(instance, [only.id]))

      # Where a wizard would draw nothing, the checklist draws its one entry
      assert has_element?(view, "#instance-forms-edit-flow-progress")
    end
  end

  describe "the demo's own form type" do
    test "starts the form with the host's data filled in, under the user's answers", %{conn: conn} do
      %{instance: instance, form: only} = flow_of_one(nil, form_type: "demo_prefill")

      {:ok, _view, html} = live(conn, edit_path(instance, [only.id]))

      # initial_data/2: the name question renders prefilled on first start,
      # with the type's property value an admin entered
      assert html =~ "Demo User"

      # An answer the user has given wins over the prefill: submit one, then
      # reopen the form and it renders the answer, not the prefill
      {:ok, _done} =
        Instances.Forms.update_status(instance, [only.id], :completed, data: %{"name" => "Grace"})

      {:ok, _reopened} = Instances.Forms.update_status(instance, [only.id], :in_progress)

      {:ok, _view, html} = live(conn, edit_path(instance, [only.id]))
      assert html =~ "Grace"
      refute html =~ "Demo User"
    end
  end

  describe "the library's review form type" do
    test "shows the related form's answers read-only beside the editable form", %{conn: conn} do
      # Start → Intake → Review; Review's form is a "review" of Intake
      {:ok, flow} = Flows.create(%{name: "Application"})
      first_node = build_node(flow, ["Start"], "Start")
      intake = build_form_node(flow, "Intake")

      review_form =
        published_form("Review", form_type: "review", property_values: %{"source" => intake.id})

      review = build_node(flow, ["Form"], "Review", %{form_id: review_form.id})
      edge(flow, first_node, intake)
      edge(flow, intake, review)
      instance = start_flow(flow)

      # Until Intake is answered there is nothing to review — and Review isn't
      # editable yet anyway, so the page says so
      complete(instance, [intake.id], %{"name" => "Ada"})

      {:ok, view, html} = live(conn, edit_path(instance, [review.id]))

      assert html =~ "Reviewing: Intake"
      # Intake's answer, inside a disabled fieldset, with no submit of its own
      assert html =~ "Ada"
      assert has_element?(view, "fieldset[disabled]")
      # The review form itself is the editable one
      assert has_element?(view, "button[type='submit']")
    end

    test "a source that doesn't resolve is one error, however it came about", %{conn: conn} do
      for values <- [%{}, %{"source" => ""}, %{"source" => "gone"}] do
        {:ok, flow} = Flows.create(%{name: "Application"})
        first_node = build_node(flow, ["Start"], "Start")
        review_form = published_form("Review", form_type: "review", property_values: values)
        review = build_node(flow, ["Form"], "Review", %{form_id: review_form.id})
        edge(flow, first_node, review)
        instance = start_flow(flow)

        {:ok, view, html} = live(conn, edit_path(instance, [review.id]))

        assert html =~ "The form to review is missing"
        # The review form itself is still editable
        assert has_element?(view, "button[type='submit']")
      end
    end
  end

  describe "the instances attr scopes the listing" do
    test "by default the listing is the user's own", %{conn: conn} do
      %{flow: flow, instance: mine} = flow_of_one()
      {:ok, theirs} = Instances.Flows.create(%{flow_id: flow.id, user_id: "someone-else"})

      {:ok, _view, html} = isolated(conn, [])

      assert html =~ mine.id
      refute html =~ theirs.id
    end

    test "a host's query lists whoever it says; the tenant is applied on top", %{conn: conn} do
      %{flow: flow, instance: mine} = flow_of_one()
      {:ok, theirs} = Instances.Flows.create(%{flow_id: flow.id, user_id: "someone-else"})

      {:ok, acme} =
        Instances.Flows.create(%{flow_id: flow.id, user_id: "someone-else", tenant_id: "acme"})

      {:ok, _view, html} = isolated(conn, [], %{"listing" => "everyone"})
      assert html =~ mine.id
      assert html =~ theirs.id
      assert html =~ acme.id

      {:ok, _view, html} = isolated(conn, [], %{"listing" => "everyone"}, "acme")
      assert html =~ acme.id
      refute html =~ mine.id
      refute html =~ theirs.id
    end
  end

  describe "the flows attr picks the flows to start" do
    test "by default every root of the tenant is offered", %{conn: conn} do
      {:ok, dog} = Flows.create(%{name: "Dog License"})
      {:ok, cat} = Flows.create(%{name: "Cat License"})
      {:ok, reusable} = Flows.create(%{name: "Shared"})
      {:ok, _} = Flows.make_reusable(reusable)
      {:ok, acme} = Flows.create(%{name: "Elsewhere", tenant_id: "acme"})

      {:ok, view, _html} = isolated(conn, [])

      assert has_element?(view, start_button(dog))
      assert has_element?(view, start_button(cat))
      refute has_element?(view, start_button(reusable))
      assert has_element?(view, start_button(acme))

      {:ok, view, _html} = isolated(conn, [], %{}, "acme")
      assert has_element?(view, start_button(acme))
      refute has_element?(view, start_button(dog))
    end

    test "a host offers what it names; the page refuses to start anything else", %{conn: conn} do
      {:ok, dog} = Flows.create(%{name: "Dog License"})
      {:ok, cat} = Flows.create(%{name: "Cat License"})

      {:ok, view, _html} = isolated(conn, [], %{"offer" => "dog-license"})

      assert has_element?(view, start_button(dog))
      refute has_element?(view, start_button(cat))

      # A crafted event for the flow that was not offered starts nothing — the
      # offered button's target, with the other flow's id in its place
      view |> element(start_button(dog)) |> render_click(%{"flow-id" => cat.id})
      assert render(view) =~ "That flow is not available here."
      assert Instances.Flows.list() == []

      # A slug that resolves to nothing offers nothing, and does not fail
      {:ok, view, html} = isolated(conn, [], %{"offer" => "nope"})
      refute has_element?(view, start_button(dog))
      assert html =~ "Nothing started yet"
    end

    test "a flow of another tenant is never offered, whatever the host says", %{conn: conn} do
      {:ok, acme} = Flows.create(%{name: "Dog License", tenant_id: "acme"})

      {:ok, view, _html} = isolated(conn, [], %{"offer" => "dog-license"}, "globex")

      refute has_element?(view, start_button(acme))
    end

    test "the instance pages refuse an instance of a flow the page did not name", %{conn: conn} do
      %{instance: cat_instance, form: only} = flow_of_one(nil, name: "Cat License")
      {:ok, _dog} = Flows.create(%{name: "Dog License"})

      pages = [
        [cat_instance.id],
        [cat_instance.id, "forms", only.id],
        [cat_instance.id, "forms", only.id, "edit"]
      ]

      for segments <- pages do
        {:ok, view, html} = isolated(conn, segments, %{"offer" => "dog-license"})
        assert html =~ "This flow is not available here."
        refute has_element?(view, "fieldset")
      end

      # The refused edit page started nothing
      assert Instances.Flows.form_instances(cat_instance) == []

      # Named, or nothing named in particular: the page renders
      {:ok, _view, html} = isolated(conn, [cat_instance.id], %{"offer" => "cat-license"})
      refute html =~ "not available here"

      {:ok, _view, html} = isolated(conn, [cat_instance.id])
      refute html =~ "not available here"
    end

    test "the flows a host names are also the flows the listing shows", %{conn: conn} do
      {:ok, dog} = Flows.create(%{name: "Dog License"})
      {:ok, cat} = Flows.create(%{name: "Cat License"})
      {:ok, dog_instance} = Instances.Flows.create(%{flow_id: dog.id, user_id: "demo-user"})
      {:ok, cat_instance} = Instances.Flows.create(%{flow_id: cat.id, user_id: "demo-user"})

      # None named: the user's own instances of every flow
      {:ok, _view, html} = isolated(conn, [])
      assert html =~ dog_instance.id
      assert html =~ cat_instance.id

      # One named: the user's own instances of that flow
      {:ok, _view, html} = isolated(conn, [], %{"offer" => "dog-license"})
      assert html =~ dog_instance.id
      refute html =~ cat_instance.id

      # A host's own query is what it says, whatever the page offers to start
      {:ok, _view, html} =
        isolated(conn, [], %{"listing" => "everyone", "offer" => "dog-license"})

      assert html =~ dog_instance.id
      assert html =~ cat_instance.id
    end
  end

  describe "Instances.Flows.list_query/1 narrows by flow" do
    test "by struct, id, or slug, alone or in a list; [] matches nothing" do
      {:ok, dog} = Flows.create(%{name: "Dog License"})
      {:ok, cat} = Flows.create(%{name: "Cat License"})
      {:ok, acme_dog} = Flows.create(%{name: "Dog License", tenant_id: "acme"})
      {:ok, d} = Instances.Flows.create(%{flow_id: dog.id, user_id: "u"})
      {:ok, c} = Instances.Flows.create(%{flow_id: cat.id, user_id: "u"})
      {:ok, a} = Instances.Flows.create(%{flow_id: acme_dog.id, user_id: "u", tenant_id: "acme"})

      ids = fn opts ->
        opts |> Instances.Flows.list_query() |> FormFlowRepo.all() |> Enum.map(& &1.id) |> Enum.sort()
      end

      assert ids.(flow: dog) == [d.id]
      assert ids.(flow: dog.id) == [d.id]
      assert ids.(flow: [dog, "cat-license"]) == Enum.sort([d.id, c.id])
      assert ids.(flow: []) == []
      assert ids.(flow: nil) == Enum.sort([d.id, c.id, a.id])

      # Slugs are per tenant: a slug alone matches it in every tenant
      assert ids.(flow: "dog-license") == Enum.sort([d.id, a.id])
      assert ids.(flow: "dog-license", tenant_id: "acme") == [a.id]
    end
  end

  describe "on_mount gates the pages" do
    test "a refusal on edit renders the message alone and starts nothing", %{conn: conn} do
      %{instance: instance, form: only} = flow_of_one(nil, name: "Refused")

      {:ok, view, html} = isolated(conn, [instance.id, "forms", only.id, "edit"])

      assert html =~ "You may not see this flow."
      assert has_element?(view, "a[href='#{flow_path(instance)}']")
      refute has_element?(view, "form")
      refute instance_at(instance, [only.id])
    end

    test "a refusal on show renders the message alone", %{conn: conn} do
      %{instance: instance, form: only} = flow_of_one(nil, name: "Refused")
      complete(instance, [only.id], %{"name" => "Ada"})

      {:ok, view, html} = isolated(conn, [instance.id, "forms", only.id])

      assert html =~ "You may not see this flow."
      refute html =~ "Ada"
      refute has_element?(view, "fieldset")
      refute has_element?(view, "button", "Reopen")
    end

    test "a refusal on the flow instance's page renders the message alone", %{conn: conn} do
      %{instance: instance} = flow_of_one(nil, name: "Refused")

      {:ok, view, html} = isolated(conn, [instance.id])

      assert html =~ "You may not see this flow."
      refute has_element?(view, "li")
      assert has_element?(view, "a[href='/users']")
    end

    test "a redirect renders nothing, navigates, and starts nothing", %{conn: conn} do
      %{instance: instance, form: only} = flow_of_one(nil, name: "Elsewhere")

      {:ok, view, html} = isolated(conn, [instance.id, "forms", only.id, "edit"])

      # The first render, before the navigation lands, draws nothing of the page
      refute html =~ "Name"
      refute html =~ "<form"
      assert {"/users", _flash} = assert_redirect(view)
      refute instance_at(instance, [only.id])

      {:ok, view, _html} = isolated(conn, [instance.id])
      assert {"/users", _flash} = assert_redirect(view)
    end

    test "the listing asks too: a refusal draws the message, a redirect navigates",
         %{conn: conn} do
      %{instance: instance} = flow_of_one()

      {:ok, view, html} = isolated(conn, [], %{"listing" => "refused"})

      assert html =~ "No listing for you."
      refute html =~ instance.id
      refute has_element?(view, "button", "Start")

      {:ok, view, _html} = isolated(conn, [], %{"listing" => "elsewhere"})
      assert {"/users", _flash} = assert_redirect(view)
    end

    test "an allowance merges its assigns into the page, after the start", %{conn: conn} do
      %{instance: instance, form: only} = flow_of_one(nil, name: "Decorated")

      {:ok, _view, html} = isolated(conn, [instance.id, "forms", only.id, "edit"])

      assert html =~ "Renamed by the host"
      assert %{status: "in_progress"} = instance_at(instance, [only.id])

      {:ok, _view, html} = isolated(conn, [instance.id])
      assert html =~ "Renamed by the host"
    end
  end

  describe "submitting runs the form type's completion callbacks" do
    setup do
      :ok = Phoenix.PubSub.subscribe(Demo.PubSub, "form_flow_test")
    end

    test "snapshot_data/2 lands on the event; handle_complete/2 sees the form done",
         %{conn: conn} do
      %{instance: instance, form: only} = flow_of_one(nil, form_type: "recording")
      {:ok, view, _html} = isolated_edit(conn, instance, [only.id])
      form_instance = instance_at(instance, [only.id])

      submit(view, form_instance, %{"name" => "Ada"})

      # The snapshot saw the form as the page did: still in progress
      assert_receive {:snapshot_data, %Context{form_instance: %{status: "in_progress"}}}

      # The reaction saw the completed row and the flow instance's fresh progress
      assert_receive {:handle_complete, %Context{} = fresh}
      assert fresh.form_instance.id == form_instance.id
      assert fresh.form_instance.status == "completed"

      assert %{status: :completed} =
               FlowProgress.find_form(fresh.flow_instance_progress, [only.id])

      # The template side is as at mount
      assert fresh.form.id ==
               Forms.get_version(form_instance.template_form_version_id).template_form_id

      assert {_path, _flash} = assert_redirect(view)

      assert %{snapshot_data: %{"seen" => %{"status" => "in_progress"}}} =
               Instances.Forms.latest_event(form_instance, "status_changed")
    end

    test "a snapshot that raises refuses the submit, and nothing is completed", %{conn: conn} do
      %{instance: instance, form: only} = flow_of_one(nil, form_type: "refusing")
      {:ok, view, _html} = isolated_edit(conn, instance, [only.id])
      form_instance = instance_at(instance, [only.id])

      submit(view, form_instance, %{"name" => "Ada"})

      assert render(view) =~ "Could not save the form"
      assert %{status: "in_progress", data: %{}} = instance_at(instance, [only.id])
      assert Instances.Forms.list_events(form_instance, event: "status_changed") == []
    end

    test "a reaction that raises is logged; the completion stands and the user moves on",
         %{conn: conn} do
      %{instance: instance, form: only} = flow_of_one(nil, form_type: "failing")
      {:ok, view, _html} = isolated_edit(conn, instance, [only.id])
      form_instance = instance_at(instance, [only.id])

      log =
        capture_log(fn ->
          submit(view, form_instance, %{"name" => "Ada"})
          assert {_path, _flash} = assert_redirect(view)
        end)

      assert log =~ "FailingReaction.handle_complete/2 raised"
      assert log =~ "the host's job queue is down"
      assert %{status: "completed"} = instance_at(instance, [only.id])
    end
  end

  describe "a review records what it reviewed" do
    test "the completion event holds the source's identity and answers", %{conn: conn} do
      %{instance: instance, intake: intake} = fixture = review_flow()
      source = complete(instance, [intake.id], %{"name" => "Ada"})

      review_instance = reviewed(conn, fixture)

      assert %{snapshot_data: %{"reviewed" => reviewed}} =
               Instances.Forms.latest_event(review_instance, "status_changed")

      assert reviewed == %{
               "path" => intake.id,
               "instance_id" => source.id,
               "version_id" => source.template_form_version_id,
               "completed_at" => DateTime.to_iso8601(source.completed_at),
               "data" => %{"name" => "Ada"}
             }
    end

    test "a source not started, or not resolving, records that nothing was reviewed",
         %{conn: conn} do
      %{intake: intake} = fixture = review_flow()

      review_instance = reviewed(conn, fixture)

      assert %{snapshot_data: %{"reviewed" => %{"path" => path, "instance_id" => nil}}} =
               Instances.Forms.latest_event(review_instance, "status_changed")

      assert path == intake.id

      {:ok, flow} = Flows.create(%{name: "Application"})
      first_node = build_node(flow, ["Start"], "Start")

      review_form =
        published_form("Review", form_type: "review", property_values: %{"source" => "gone"})

      review = build_node(flow, ["Form"], "Review", %{form_id: review_form.id})
      edge(flow, first_node, review)
      instance = start_flow(flow)

      review_instance = reviewed(conn, %{instance: instance, review: review})

      assert %{snapshot_data: %{"reviewed" => %{"path" => "gone", "instance_id" => nil}}} =
               Instances.Forms.latest_event(review_instance, "status_changed")
    end
  end

  describe "a review notices when the reviewed form changes" do
    test "right after the review it is current, on both pages", %{conn: conn} do
      %{instance: instance, intake: intake, review: review} = fixture = review_flow()
      complete(instance, [intake.id], %{"name" => "Ada"})
      reviewed(conn, fixture)

      {:ok, _view, html} = live(conn, form_path(instance, [review.id]))
      assert html =~ "Unchanged since."

      {:ok, _reopened} = Instances.Forms.update_status(instance, [review.id], :in_progress)
      {:ok, _view, html} = live(conn, edit_path(instance, [review.id]))
      assert html =~ "Unchanged since."
    end

    test "the source submitted again: the notice and the diff, on Show and on a reopened Edit",
         %{conn: conn} do
      %{instance: instance, intake: intake, review: review} = fixture = review_flow()
      complete(instance, [intake.id], %{"name" => "Ada"})
      reviewed(conn, fixture)
      complete(instance, [intake.id], %{"name" => "Grace"})

      {:ok, _view, html} = live(conn, form_path(instance, [review.id]))
      assert html =~ "Intake was submitted again on"
      assert html =~
               ~r/<td[^>]*>\s*Name\s*<\/td>\s*<td[^>]*><span[^>]*>Ada<\/span><\/td>\s*<td[^>]*><span[^>]*>Grace<\/span><\/td>/

      refute html =~ "structure also changed"

      {:ok, _reopened} = Instances.Forms.update_status(instance, [review.id], :in_progress)
      {:ok, view, html} = live(conn, edit_path(instance, [review.id]))
      assert html =~ "Intake was submitted again on"

      assert html =~
               ~r/Name\s*<\/td>\s*<td[^>]*><span[^>]*>Ada<\/span><\/td>\s*<td[^>]*><span[^>]*>Grace/
      # Still editable: resubmitting is how the review becomes current again
      assert has_element?(view, "button[type='submit']")
    end

    test "the source reopened but not resubmitted", %{conn: conn} do
      %{instance: instance, intake: intake, review: review} = fixture = review_flow()
      complete(instance, [intake.id], %{"name" => "Ada"})
      reviewed(conn, fixture)
      {:ok, _reopened} = Instances.Forms.update_status(instance, [intake.id], :in_progress)

      {:ok, _view, html} = live(conn, form_path(instance, [review.id]))
      assert html =~ "Intake is being edited — reopened on"
      refute html =~ "submitted again"
    end

    test "a publish that reopens the source is a migration, not a user's reopen", %{conn: conn} do
      %{instance: instance, intake: intake, review: review} = fixture = review_flow()
      source = complete(instance, [intake.id], %{"name" => "Ada"})
      reviewed(conn, fixture)

      published = Forms.get_version(source.template_form_version_id)
      {:ok, draft} = Forms.create_draft(published.template_form_id, based_on: published.id)

      {:ok, draft} =
        Forms.update_draft(draft, %{
          definition: %{
            "elements" => [%{"type" => "text", "name" => "name", "title" => "Full name"}]
          }
        })

      {:ok, _published} = Forms.update_status(draft, :published, completed: :reopen_carry)

      {:ok, _view, html} = live(conn, form_path(instance, [review.id]))
      assert html =~ "Intake&#39;s form changed after this review"
      assert html =~ "The form&#39;s structure also changed"
      # Carried answers are the answers reviewed
      assert html =~ "The answers are the same as reviewed."
      refute html =~ "is being edited"
    end

    test "resubmitting the review clears the notice", %{conn: conn} do
      %{instance: instance, intake: intake, review: review} = fixture = review_flow()
      complete(instance, [intake.id], %{"name" => "Ada"})
      reviewed(conn, fixture)
      complete(instance, [intake.id], %{"name" => "Grace"})
      {:ok, _reopened} = Instances.Forms.update_status(instance, [review.id], :in_progress)

      reviewed(conn, fixture, %{"name" => "Still right"})

      {:ok, _view, html} = live(conn, form_path(instance, [review.id]))
      assert html =~ "Unchanged since."
      refute html =~ "submitted again"
    end

    test "deleting the source erases the record; the pages say so", %{conn: conn} do
      %{instance: instance, intake: intake, review: review} = fixture = review_flow()
      source = complete(instance, [intake.id], %{"name" => "Ada"})
      review_instance = reviewed(conn, fixture)

      assert {:ok, _deleted} = Instances.Forms.delete_instance(source)

      assert %{snapshot_data: %{"reviewed" => %{"data" => %{}, "redacted_at" => _at}}} =
               Instances.Forms.latest_event(review_instance, "status_changed")

      {:ok, _view, html} = live(conn, form_path(instance, [review.id]))
      assert html =~ "The record of what was reviewed has been erased."
      refute html =~ "Ada"
    end
  end

  describe "an instance's event trail" do
    test "list_events/2 reads it oldest first, and filters by kind" do
      %{instance: instance, forms: [name, _address]} = flow_of_two()
      complete(instance, [name.id], %{"name" => "Ada"})
      {:ok, _reopened} = Instances.Forms.update_status(instance, [name.id], :in_progress)
      form_instance = instance_at(instance, [name.id])

      events = Instances.Forms.list_events(form_instance)

      assert Enum.map(events, & &1.event) == ["created", "status_changed", "reopened"]

      assert [%{event: "status_changed"}] =
               Instances.Forms.list_events(form_instance, event: "status_changed")

      assert Instances.Forms.list_events(form_instance, event: "migrated") == []
    end

    test "latest_event/2 is the newest of a kind, or nil" do
      %{instance: instance, forms: [name, _address]} = flow_of_two()
      complete(instance, [name.id], %{"name" => "Ada"})
      {:ok, _reopened} = Instances.Forms.update_status(instance, [name.id], :in_progress)
      complete(instance, [name.id], %{"name" => "Grace"})
      form_instance = instance_at(instance, [name.id])

      [first, second] = Instances.Forms.list_events(form_instance, event: "status_changed")
      latest = Instances.Forms.latest_event(form_instance, "status_changed")

      assert latest.id == second.id
      assert DateTime.compare(latest.inserted_at, first.inserted_at) == :gt
      assert is_nil(Instances.Forms.latest_event(form_instance, "migrated"))
    end
  end

  describe "deleting a reviewed form redacts the copies of its answers" do
    # Start → Intake → Review A → Review B, any order; both reviews recorded
    # a copy of Intake's answers on their completion event. A second journey
    # of the same flow did the same with its own Intake.
    defp reviewed_journeys do
      {:ok, flow} =
        Flows.create(%{name: "Application", properties: properties("wizard_any_order")})

      first_node = build_node(flow, ["Start"], "Start")
      intake = build_form_node(flow, "Intake")
      review_a = build_form_node(flow, "Review A")
      review_b = build_form_node(flow, "Review B")

      edge(flow, first_node, intake)
      edge(flow, intake, review_a)
      edge(flow, review_a, review_b)

      review = fn instance ->
        source = complete(instance, [intake.id], %{"name" => "Ada"})

        snapshot = %{
          "reviewed" => %{
            "path" => intake.id,
            "instance_id" => source.id,
            "version_id" => source.template_form_version_id,
            "completed_at" => DateTime.to_iso8601(source.completed_at),
            "data" => %{"name" => "Ada"}
          }
        }

        review_a =
          complete(instance, [review_a.id], %{"name" => "Looks right"}, snapshot_data: snapshot)

        review_b =
          complete(instance, [review_b.id], %{"name" => "Agreed"}, snapshot_data: snapshot)

        %{source: source, reviews: [review_a, supersede(review_b)]}
      end

      journey = start_flow(flow)
      other = start_flow(flow)

      %{
        journey: Map.put(review.(journey), :instance, journey),
        other: Map.put(review.(other), :instance, other)
      }
    end

    test "redact_snapshots/1 blanks every copy in the journey — superseded included — and nothing else" do
      %{journey: journey, other: other} = reviewed_journeys()
      before = Enum.map(journey.reviews, &Instances.Forms.latest_event(&1, "status_changed"))

      assert {:ok, 2} = Instances.Forms.redact_snapshots(journey.source)

      for {review, was} <- Enum.zip(journey.reviews, before) do
        event = Instances.Forms.latest_event(review, "status_changed")

        assert %{"reviewed" => reviewed} = event.snapshot_data
        assert reviewed["data"] == %{}
        assert {:ok, _at, 0} = DateTime.from_iso8601(reviewed["redacted_at"])
        # Identity kept: what was reviewed stays on record, only the answers go
        assert reviewed["instance_id"] == journey.source.id
        assert reviewed["version_id"] == journey.source.template_form_version_id
        # The row is otherwise the row it was
        assert Map.drop(event, [:snapshot_data, :__meta__]) ==
                 Map.drop(was, [:snapshot_data, :__meta__])
      end

      # The other journey's copies are of its own Intake, and stay
      for review <- other.reviews do
        assert %{"reviewed" => %{"data" => %{"name" => "Ada"}} = reviewed} =
                 Instances.Forms.latest_event(review, "status_changed").snapshot_data

        refute Map.has_key?(reviewed, "redacted_at")
      end

      # A standalone instance has no journey, so there is nothing to scan
      assert {:ok, 0} = Instances.Forms.redact_snapshots(standalone_instance(journey.source))
    end

    test "delete_instance/2 redacts before it deletes" do
      %{journey: journey} = reviewed_journeys()

      assert {:ok, _deleted} = Instances.Forms.delete_instance(journey.source)

      refute Instances.Forms.get(journey.source.id)

      for review <- journey.reviews do
        assert %{"reviewed" => %{"data" => %{}, "redacted_at" => _at}} =
                 Instances.Forms.latest_event(review, "status_changed").snapshot_data
      end
    end

    test "deleting the whole journey takes the copies with it, and touches no other journey" do
      %{journey: journey, other: other} = reviewed_journeys()

      assert {:ok, _deleted} = Instances.Flows.delete_instance(journey.instance)

      refute Instances.Flows.get(journey.instance.id)
      assert Instances.Flows.form_instances(journey.instance) == []

      for review <- other.reviews do
        assert %{"reviewed" => %{"data" => %{"name" => "Ada"}}} =
                 Instances.Forms.latest_event(review, "status_changed").snapshot_data
      end
    end
  end

  # ── URLs ────────────────────────────────────────────────────────────────

  defp flow_path(instance), do: "/users/#{instance.id}"

  defp form_path(instance, path), do: "#{flow_path(instance)}/forms/#{Enum.join(path, "/")}"

  defp edit_path(instance, path), do: "#{form_path(instance, path)}/edit"

  defp offered?(view, instance, path) do
    has_element?(view, "a[href='#{edit_path(instance, path)}']")
  end

  # A user-facing page, through the test config's page
  defp start_button(flow), do: "button[phx-value-flow-id='#{flow.id}']"

  defp isolated(conn, segments, callback_data \\ %{}, tenant_id \\ nil, perspectives \\ []) do
    live_isolated(conn, TestPage,
      session: %{
        "path" => segments,
        "callback_data" => callback_data,
        "tenant_id" => tenant_id,
        "perspectives" => perspectives
      }
    )
  end

  # The same pages, seen as one kind of user
  defp as(conn, perspective, segments), do: isolated(conn, segments, %{}, nil, perspective)

  defp isolated_edit(conn, instance, path) do
    isolated(conn, [instance.id, "forms"] ++ path ++ ["edit"])
  end

  # Submits the form's answers the way the user does; the completion runs
  # after the submit event, so read the page again for its result
  defp submit(view, form_instance, answers) do
    view
    |> form("#instance-forms-edit-#{form_instance.id}-form", %{"dynamic_form" => answers})
    |> render_submit()
  end

  # ── fixtures ────────────────────────────────────────────────────────────

  # Start → Name → Address → End, one "forms" flow of the given type
  defp flow_of_two(type \\ nil) do
    {:ok, flow} = Flows.create(%{name: "Application", properties: properties(type)})

    first_node = build_node(flow, ["Start"], "Start")
    name = build_form_node(flow, "Name")
    address = build_form_node(flow, "Address")
    last_node = build_node(flow, ["End"], "End")

    edge(flow, first_node, name)
    edge(flow, name, address)
    edge(flow, address, last_node)

    %{flow: flow, instance: start_flow(flow), forms: [name, address]}
  end

  # `name:` names the flow; the rest of `opts` shapes its one form
  defp flow_of_one(type \\ nil, opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, "Single")
    {:ok, flow} = Flows.create(%{name: name, properties: properties(type)})

    first_node = build_node(flow, ["Start"], "Start")
    only = build_form_node(flow, "Only", opts)

    edge(flow, first_node, only)

    %{flow: flow, instance: start_flow(flow), form: only}
  end

  # The same, with the form left in draft: the position exists and the flow's
  # type allows work there, but there is no version to pin
  defp flow_of_one_unpublished do
    {:ok, flow} = Flows.create(%{name: "Unpublished"})

    {:ok, form} = Forms.create(%{name: "Draft #{System.unique_integer([:positive])}"})

    first_node = build_node(flow, ["Start"], "Start")
    only = build_node(flow, ["Form"], "Only", %{form_id: form.id})

    edge(flow, first_node, only)

    %{flow: flow, instance: start_flow(flow), form: only}
  end

  # One subflow node wrapping a two-form child flow, so its positions are two
  # segments deep
  defp nested_flow do
    {:ok, root} = Flows.create(%{name: "Onboarding", label: "subflows"})

    %{flow: documents, forms: forms} = owned_flow_of_two(root, "Documents")

    first_node = build_node(root, ["Start"], "Start")
    documents_node = subflow_node(root, documents, "Documents")

    edge(root, first_node, documents_node)

    %{instance: start_flow(root), subflow_node: documents_node, forms: forms}
  end

  # A private child flow of `root`: Start → First → Second → End
  defp owned_flow_of_two(root, name, type \\ nil) do
    {:ok, flow} =
      Flows.create(%{
        name: name,
        label: "forms",
        owner_flow_id: root.id,
        properties: properties(type)
      })

    first_node = build_node(flow, ["Start"], "Start")
    first = build_form_node(flow, "First")
    second = build_form_node(flow, "Second")
    last_node = build_node(flow, ["End"], "End")

    edge(flow, first_node, first)
    edge(flow, first, second)
    edge(flow, second, last_node)

    %{flow: flow, forms: [first, second]}
  end

  defp properties(nil), do: %{}
  defp properties(type), do: %{"form_flow_type" => type}

  defp start_flow(flow) do
    {:ok, instance} = Instances.Flows.create(%{flow_id: flow.id, user_id: "demo-user"})

    instance
  end

  # Starts and submits the form at `path`; `opts` reach the completion
  # (`snapshot_data:` writes a payload on its `status_changed` event)
  defp complete(instance, path, data \\ %{}, opts \\ []) do
    {:ok, _opened} = Instances.Forms.update_status(instance, path, :in_progress)

    {:ok, completed} =
      Instances.Forms.update_status(instance, path, :completed, [data: data] ++ opts)

    completed
  end

  # What strand reconciliation will do to a replaced instance: stamp it
  # superseded, keeping its trail
  defp supersede(form_instance) do
    {:ok, superseded} =
      FormFlowRepo.update(Ecto.Changeset.change(form_instance, superseded_at: DateTime.utc_now()))

    superseded
  end

  # Start → Intake → Review → End, any order; Review's form is a "review" of
  # Intake
  defp review_flow do
    {:ok, flow} = Flows.create(%{name: "Application", properties: properties("wizard_any_order")})

    first_node = build_node(flow, ["Start"], "Start")
    intake = build_form_node(flow, "Intake")

    review_form =
      published_form("Review", form_type: "review", property_values: %{"source" => intake.id})

    review = build_node(flow, ["Form"], "Review", %{form_id: review_form.id})
    last_node = build_node(flow, ["End"], "End")

    edge(flow, first_node, intake)
    edge(flow, intake, review)
    edge(flow, review, last_node)

    %{flow: flow, instance: start_flow(flow), intake: intake, review: review}
  end

  # The review submitted through its page, the way the reviewer does it — so
  # its type records what it reviewed
  defp reviewed(
         conn,
         %{instance: instance, review: review},
         answers \\ %{"name" => "Looks right"}
       ) do
    {:ok, view, _html} = live(conn, edit_path(instance, [review.id]))
    review_instance = instance_at(instance, [review.id])
    submit(view, review_instance, answers)
    assert {_path, _flash} = assert_redirect(view)

    review_instance
  end

  # A form instance filled on its own, outside any journey
  defp standalone_instance(form_instance) do
    {:ok, standalone} =
      FormFlowRepo.insert(
        Instances.Form.changeset(%Instances.Form{}, %{
          template_form_version_id: form_instance.template_form_version_id
        })
      )

    standalone
  end

  defp instance_at(instance, path), do: Instances.Forms.get_at(instance, path)

  defp build_node(flow, labels, label, attrs \\ %{}) do
    attrs =
      Map.merge(
        %{flow_id: flow.id, labels: labels, properties: %{"data" => %{"label" => label}}},
        attrs
      )

    {:ok, node} = FormFlowRepo.insert(Flow.Node.changeset(%Flow.Node{}, attrs))

    node
  end

  defp edge(flow, source, target) do
    {:ok, _relationship} =
      FormFlowRepo.insert(
        Flow.Relationship.changeset(%Flow.Relationship{}, %{
          flow_id: flow.id,
          source_id: source.id,
          target_id: target.id,
          label: "CONNECTS_TO"
        })
      )
  end

  defp build_form_node(flow, label, opts \\ []) do
    build_node(flow, ["Form"], label, %{form_id: published_form(label, opts).id})
  end

  defp subflow_node(flow, subflow, label) do
    build_node(flow, ["Subflow"], label, %{subflow_id: subflow.id})
  end

  # A published form with one text question, "name"; `form_type:` picks a
  # form type for it and `property_values:` its property values — for the
  # demo's prefill type, "Demo User" as the name to prefill unless given.
  # `definition:` replaces the question outright, which is how a stored
  # definition that will not parse is published.
  defp published_form(name, opts) do
    properties =
      case opts[:form_type] do
        nil ->
          %{}

        "demo_prefill" ->
          values = Keyword.get(opts, :property_values, %{"name" => "Demo User"})
          %{"form_type" => "demo_prefill", "form_type_property_values" => values}

        type ->
          values = Keyword.get(opts, :property_values, %{})
          %{"form_type" => type, "form_type_property_values" => values}
      end

    {:ok, form} =
      Forms.create(%{
        name: "#{name} #{System.unique_integer([:positive])}",
        properties: properties
      })

    [draft] = form.versions

    definition =
      Keyword.get(opts, :definition, %{
        "elements" => [%{"type" => "text", "name" => "name", "title" => "Name"}]
      })

    {:ok, draft} = Forms.update_draft(draft, %{definition: definition})
    {:ok, _published} = Forms.update_status(draft, :published)

    form
  end
end
