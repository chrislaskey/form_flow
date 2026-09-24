defmodule Demo.FormFlowInstancesTest do
  @moduledoc """
  Exercises the user-facing pages — the flow instance's listing and the form
  pages — against a real database and a real LiveView mount.

  Two things are proven here that the library's own tests can't reach. First,
  that a stored `flow_type` changes what a user sees: which forms offer
  to start, which of them are navigable, and where the flow's progress is
  drawn — the demo's own type included, which is the only place the whole
  `FormFlow.Config` → `FormFlow.Config.Flows.Type` path runs end to end.
  Second, that the URLs address *positions*: `/edit` starts the form it
  names, on an ordinary page load, and only where the flow's type allows work
  — so the address bar can't walk around the flow.
  """

  use DemoWeb.ConnCase, async: false

  # /demo/pet-licenses/applications is the user experience
  @moduletag user: "dog_owner"

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest

  alias FormFlow.Config.Flows.Allowed
  alias FormFlow.Config.Property
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
    def snapshot(context, _callback_data) do
      Phoenix.PubSub.broadcast(Demo.PubSub, "form_flow_test", {:snapshot, context})
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
    def snapshot(_context, _callback_data), do: raise("nothing to record")
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
      do: {:redirect, "/demo/pet-licenses/applications"}

    def on_mount(%Context{flow: %{name: "Decorated"}}, _callback_data),
      do: {:ok, %{flow_name: "Renamed by the host"}}

    def on_mount(%Context{flow: nil}, %{"listing" => "refused"}),
      do: {:error, "No listing for you."}

    def on_mount(%Context{flow: nil}, %{"listing" => "elsewhere"}),
      do: {:redirect, "/demo/pet-licenses/applications"}

    def on_mount(_context, _callback_data), do: {:ok, %{}}
  end

  # The users page as `DemoWeb.FormFlowLive.Users` renders it, with the test
  # types and gate in place of the demo's — mounted without a route
  # (live_isolated/3). The session's "callback_data" is the page's
  # callback_data, and also picks the listing's `instances` ("listing" =>
  # "everyone") and `flows` ("offer" => slug or "offer_id" => id, with
  # "start" and "continue" for what the page allows), the way a host page
  # would build those attrs from what it knows.
  defmodule TestPage do
    use Phoenix.LiveView

    @impl true
    def mount(_params, %{"path" => path} = session, socket) do
      callback_data = Map.get(session, "callback_data", %{})

      {:ok,
       Phoenix.Component.assign(socket,
         path: path,
         uri: "http://localhost/demo/pet-licenses/applications/#{Enum.join(path, "/")}",
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

    defp flows(%{"offer" => slug} = callback_data),
      do: [allowed([flow_slug: slug], callback_data)]

    defp flows(%{"offer_id" => id} = callback_data), do: [allowed([flow_id: id], callback_data)]

    defp flows(_callback_data), do: nil

    defp allowed(handle, callback_data) do
      Allowed.new(
        handle ++
          [
            start: Map.get(callback_data, "start", true),
            continue: Map.get(callback_data, "continue", true)
          ]
      )
    end

    @impl true
    def render(assigns) do
      ~H"""
      <FormFlow.Web.router
        user_id="dog_owner"
        tenant_id={@tenant_id}
        perspectives={@perspectives}
        uri={@uri}
        params={@params}
        path={@path}
        base="/demo/pet-licenses/applications"
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
      # offered, on a version of another flow's form
      refute instance_at(instance, [elsewhere.id])
      assert %{status: "completed"} = instance_at(instance, [name.id])
    end
  end

  describe "an instance's host identities" do
    test "starting a form stamps the user on it", %{conn: conn} do
      %{instance: instance, forms: [name, _address]} = flow_of_two()

      {:ok, _view, _html} = live(conn, edit_path(instance, [name.id]))

      form_instance = instance_at(instance, [name.id])
      assert form_instance.user_id == "dog_owner"
      assert form_instance.tenant_id == nil
    end

    test "a tenant is stamped on the journey and its forms, and narrows the listing" do
      %{flow: flow, forms: [name, _address]} = flow_of_two()

      {:ok, tenant_instance} =
        Instances.Flows.create(%{
          template_flow_id: flow.id,
          user_id: "dog_owner",
          tenant_id: "acme"
        })

      {:ok, form_instance} =
        Instances.Forms.update_status(tenant_instance, [name.id], :in_progress,
          user_id: "dog_owner",
          tenant_id: "acme"
        )

      assert tenant_instance.tenant_id == "acme"
      assert form_instance.tenant_id == "acme"

      assert [%{id: id}] = Instances.Flows.list(user_id: "dog_owner", tenant_id: "acme")
      assert id == tenant_instance.id
      assert Instances.Flows.list(user_id: "dog_owner", tenant_id: "other") == []
      assert length(Instances.Flows.list(user_id: "dog_owner")) == 2
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
      {:ok, root} = Flows.create(%{name: "Licensing", label: "subflows", status: "open"})

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
      %{instance: instance, intake: intake} = licensing()

      {:ok, _view, applicant} = as(conn, "applicant", [instance.id])
      assert applicant =~ "Application / Intake"
      refute applicant =~ "Review / Review"

      # The reviewer's own step is shut on the applicant, who has not
      # finished, so there is nothing of theirs to list yet; once the
      # applicant is done it is theirs and no other's
      {:ok, _view, waiting} = as(conn, "reviewer", [instance.id])
      assert waiting =~ "Nothing in this flow is for you to fill out."

      complete(instance, intake, %{"name" => "Ada"})

      {:ok, _view, reviewer} = as(conn, "reviewer", [instance.id])
      assert reviewer =~ "Review / Review"
      refute reviewer =~ "Application / Intake"

      # A viewer of both sees everything - as a card per subflow, its name in
      # the head and its forms unprefixed
      {:ok, _view, both} = as(conn, ["applicant", "reviewer"], [instance.id])
      assert both =~ "Application"
      assert both =~ "Intake"
      assert both =~ "Review"
      refute both =~ "Application / Intake"

      # A viewer with no perspective sees only the flows for everyone, and
      # every flow here is for someone
      {:ok, _view, nobody} = isolated(conn, [instance.id])
      assert nobody =~ "Nothing in this flow is for you to fill out."
      refute nobody =~ "Intake"
      refute nobody =~ "Review / Review"
    end

    test "the flow's page says where the viewer stands, and its history what happened",
         %{conn: conn} do
      %{instance: instance, intake: intake} = licensing()

      {:ok, _view, html} = as(conn, "applicant", [instance.id])
      assert html =~ "Your turn"
      assert html =~ "0 of 1 forms done"
      assert html =~ ~s(href="#{flow_path(instance)}/history")

      {:ok, _view, html} = as(conn, "applicant", [instance.id, "history"])
      assert html =~ "Started"
      assert html =~ "Licensing"
      assert html =~ ~s(href="#{flow_path(instance)}")
      refute html =~ "Submitted"

      complete(instance, intake, %{"name" => "Ada"})

      {:ok, _view, html} = as(conn, "applicant", [instance.id])
      assert html =~ "Waiting on others"
      assert html =~ "1 of 1 forms done"

      {:ok, _view, html} = as(conn, "reviewer", [instance.id])
      assert html =~ "Your turn"

      {:ok, _view, html} = as(conn, "applicant", [instance.id, "history"])
      assert html =~ "Submitted"
      assert html =~ "Application / Intake"
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

    test "a viewer of both perspectives moves on to the next form, whoever it is for",
         %{conn: conn} do
      %{instance: instance, intake: intake, review: review} = licensing()

      {:ok, view, _html} =
        as(conn, ["applicant", "reviewer"], [instance.id, "forms"] ++ intake ++ ["edit"])

      submit(view, instance_at(instance, intake), %{"name" => "Ada"})

      assert {path, _flash} = assert_redirect(view)
      assert path == edit_path(instance, review)
    end

    test "a viewer with no perspective is refused a form that is for someone", %{conn: conn} do
      %{instance: instance, intake: intake} = licensing()

      {:ok, _view, html} = isolated_edit(conn, instance, intake)

      assert html =~ "This form is not part of your work here."
      refute instance_at(instance, intake)
    end

    # Licensing with a closing form of the applicant's own behind the
    # review: Start → Application (applicant) → Review (reviewer) →
    # Feedback (everyone) → End
    defp licensing_with_feedback(root_properties \\ %{}) do
      {:ok, root} =
        Flows.create(%{
          name: "Licensing",
          label: "subflows",
          status: "open",
          properties: root_properties
        })

      application = owned_forms_flow(root, "Application", ["applicant"], "Intake")
      review = owned_forms_flow(root, "Review", ["reviewer"], "Review")
      feedback = owned_forms_flow(root, "Feedback", [], "Feedback")

      first_node = build_node(root, ["Start"], "Start")
      application_node = subflow_node(root, application.flow, "Application")
      review_node = subflow_node(root, review.flow, "Review")
      feedback_node = subflow_node(root, feedback.flow, "Feedback")
      last_node = build_node(root, ["End"], "End")

      edge(root, first_node, application_node)
      edge(root, application_node, review_node)
      edge(root, review_node, feedback_node)
      edge(root, feedback_node, last_node)

      %{
        instance: start_flow(root),
        intake: [application_node.id, application.form.id],
        review: [review_node.id, review.form.id]
      }
    end

    test "a form behind another perspective's step is not listed until that side finishes",
         %{conn: conn} do
      %{instance: instance, intake: intake, review: review} = licensing_with_feedback()

      # The applicant's own closing form is for everyone, but only the
      # reviewer can open the step it sits behind, so it is not a row
      {:ok, _view, html} = as(conn, "applicant", [instance.id])
      assert html =~ "Intake"
      refute html =~ "Feedback"

      complete(instance, intake, %{"name" => "Ada"})

      {:ok, _view, html} = as(conn, "applicant", [instance.id])
      assert html =~ "Waiting on others"
      refute html =~ "Feedback"

      complete(instance, review, %{"name" => "Rex"})

      {:ok, _view, html} = as(conn, "applicant", [instance.id])
      assert html =~ "Feedback"
      assert html =~ "Your turn"
    end

    test "the rule reads the same from the other side of the handoff", %{conn: conn} do
      %{instance: instance, intake: intake} = licensing_with_feedback()

      # The reviewer waits on the applicant exactly as the applicant waits
      # on them: nothing to list while the step in front is another
      # perspective's and unfinished
      {:ok, _view, html} = as(conn, "reviewer", [instance.id])
      assert html =~ "Nothing in this flow is for you to fill out."

      complete(instance, intake, %{"name" => "Ada"})

      # Now everything in front of the review is done, so it is listed - and
      # so is the closing form, which nothing of another perspective's shuts
      # for a reviewer
      {:ok, _view, html} = as(conn, "reviewer", [instance.id])
      assert html =~ "Review"
      assert html =~ "Feedback"
      assert html =~ "Your turn"
    end

    test "a root worked in any order holds nobody back", %{conn: conn} do
      %{instance: instance} = licensing_with_feedback(%{"flow_type" => "any_order"})

      # Any unfinished step can be entered whatever comes before it, so no
      # step is shut on anyone and the closing form is listed from the start
      {:ok, _view, html} = as(conn, "applicant", [instance.id])
      assert html =~ "Intake"
      assert html =~ "Feedback"
    end
  end

  describe "a form's page draws the flow's progress" do
    test "in order draws it, with nothing ahead navigable", %{conn: conn} do
      %{instance: instance, forms: [name, address]} = flow_of_two("wizard_in_order")

      {:ok, view, html} = live(conn, edit_path(instance, [name.id]))

      assert has_element?(view, "#instance-forms-edit-flow-progress")
      assert html =~ "Name"
      assert html =~ "Address"
      assert html =~ ~s(aria-current="step")
      refute has_element?(view, "a[href='#{edit_path(instance, [address.id])}']")
      refute has_element?(view, "a[href='#{form_path(instance, [address.id])}']")
    end

    test "in order links a form behind the user to its answers", %{conn: conn} do
      %{instance: instance, forms: [name, address]} = flow_of_two("wizard_in_order")

      complete(instance, [name.id])

      {:ok, view, _html} = live(conn, edit_path(instance, [address.id]))

      # A submitted form's edit page only says it was submitted, so the step
      # goes to the answers instead
      assert has_element?(view, "a[href='#{form_path(instance, [name.id])}']")
      refute has_element?(view, "a[href='#{edit_path(instance, [name.id])}']")
    end

    test "any order makes the other forms navigable", %{conn: conn} do
      %{instance: instance, forms: [name, address]} = flow_of_two("wizard_any_order")

      {:ok, view, _html} = live(conn, edit_path(instance, [name.id]))

      # The form being filled is never a link to itself — only the others are.
      refute has_element?(view, "a[href='#{edit_path(instance, [name.id])}']")
      assert has_element?(view, "a[href='#{edit_path(instance, [address.id])}']")
    end

    test "any order sends a form already submitted to its answers", %{conn: conn} do
      %{instance: instance, forms: [name, address]} = flow_of_two("wizard_any_order")

      complete(instance, [address.id])

      {:ok, view, _html} = live(conn, edit_path(instance, [name.id]))

      assert has_element?(view, "a[href='#{form_path(instance, [address.id])}']")
      refute has_element?(view, "a[href='#{edit_path(instance, [address.id])}']")
    end

    test "the summary names the step either side, linked where the list links it",
         %{conn: conn} do
      %{instance: instance, forms: [name, address]} = flow_of_two("wizard_any_order")

      # Folded shut, the card names the next step - and links it, because
      # this flow lets the user work it
      {:ok, view, _html} = live(conn, edit_path(instance, [name.id]))

      assert has_element?(
               view,
               "#instance-forms-edit-flow-progress-summary a[href='#{edit_path(instance, [address.id])}']"
             )

      # From the second form, the step behind is named instead, and a
      # submitted form goes to its answers as the unfolded list sends it
      complete(instance, [name.id])
      {:ok, view, _html} = live(conn, edit_path(instance, [address.id]))

      assert has_element?(
               view,
               "#instance-forms-edit-flow-progress-summary a[href='#{form_path(instance, [name.id])}']"
             )

      # In order, the step ahead is named but is no link: the same answer
      # the unfolded list gives it
      %{instance: instance, forms: [name, address]} = flow_of_two("wizard_in_order")
      {:ok, view, _html} = live(conn, edit_path(instance, [name.id]))

      refute has_element?(
               view,
               "#instance-forms-edit-flow-progress-summary a[href='#{edit_path(instance, [address.id])}']"
             )
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

      # Reopen is offered twice on this page: in the header with the tabs,
      # and inline in the sentence the alert makes
      assert view
             |> element(~s(button.btn-ghost[phx-click="request_reopen"]))
             |> render_click() =~ "Reopen form"
    end

    test "reopen lives with the answers, on show, and lands on edit", %{conn: conn} do
      %{instance: instance, forms: [name, _address]} = flow_of_two()
      complete(instance, [name.id])

      {:ok, view, _html} = live(conn, form_path(instance, [name.id]))

      # Selected by phx-click, not text: the modal's confirm button also
      # reads "Reopen", the trigger's own label
      view |> element(~s(button[phx-click="request_reopen"])) |> render_click()
      assert render(view) =~ "Reopen form"

      view |> element(~s(button[phx-click="confirm_reopen"])) |> render_click()

      assert {path, _flash} = assert_redirect(view)
      assert path == edit_path(instance, [name.id])
      assert %{status: "in_progress"} = instance_at(instance, [name.id])
    end
  end

  describe "the Edit tab asks to reopen a submitted form" do
    test "from View: cancel stays, confirm reopens and lands on Edit", %{conn: conn} do
      %{instance: instance, forms: [name, _address]} = flow_of_two()
      complete(instance, [name.id])

      {:ok, view, _html} = live(conn, form_path(instance, [name.id]))

      # The Edit tab is the ask, not a link to a page with nothing to edit
      refute has_element?(view, "a[href='#{edit_path(instance, [name.id])}']")
      assert has_element?(view, ~s(button[phx-click="request_reopen"]), "Edit")

      # The other tabs are still ordinary links: naming Edit in `events`
      # does not route the whole control through the page
      assert has_element?(view, "a[href='#{history_path(instance, [name.id])}']")

      view |> element(~s(button[phx-click="request_reopen"])) |> render_click()
      assert render(view) =~ "Reopen form"

      # Cancel leaves the reader where they were, and the form submitted
      view |> element(~s(button[phx-click="cancel_reopen"])) |> render_click()
      refute render(view) =~ "Reopen form"
      assert %{status: "completed"} = instance_at(instance, [name.id])

      view |> element(~s(button[phx-click="request_reopen"])) |> render_click()
      view |> element(~s(button[phx-click="confirm_reopen"])) |> render_click()

      assert {path, _flash} = assert_redirect(view)
      assert path == edit_path(instance, [name.id])
      assert %{status: "in_progress"} = instance_at(instance, [name.id])
    end

    test "from History too", %{conn: conn} do
      %{instance: instance, forms: [name, _address]} = flow_of_two()
      complete(instance, [name.id])

      {:ok, view, _html} = live(conn, history_path(instance, [name.id]))

      view |> element(~s(button[phx-click="request_reopen"])) |> render_click()
      view |> element(~s(button[phx-click="confirm_reopen"])) |> render_click()

      assert {path, _flash} = assert_redirect(view)
      assert path == edit_path(instance, [name.id])
      assert %{status: "in_progress"} = instance_at(instance, [name.id])
    end

    test "a form still in progress keeps an ordinary Edit link", %{conn: conn} do
      %{instance: instance, forms: [name, _address]} = flow_of_two()

      {:ok, view, _html} = live(conn, form_path(instance, [name.id]))

      assert has_element?(view, "a[href='#{edit_path(instance, [name.id])}']")
      refute has_element?(view, ~s(button[phx-click="request_reopen"]))
    end
  end

  describe "reopen and the flow's status" do
    test "a reopen drawn before the year closed is refused at the click, on both pages",
         %{conn: conn} do
      %{flow: flow, instance: instance, form: only} = flow_of_one()
      complete(instance, [only.id])

      # The form's show page offers it on the Edit tab while continuing is
      # allowed: there is nothing to edit until the form is reopened
      {:ok, form_view, _html} = live(conn, form_path(instance, [only.id]))
      assert has_element?(form_view, ~s(button[phx-click="request_reopen"]), "Edit")
      # So does the instance page
      {:ok, flow_view, _html} = live(conn, flow_path(instance))
      assert has_element?(flow_view, "button", "Reopen")

      # The year closes; both clicks arrive after
      {:ok, _} = Flows.update_status(flow, "read_only", [])

      form_view |> element(~s(button[phx-click="request_reopen"])) |> render_click()
      html = form_view |> element(~s(button[phx-click="confirm_reopen"])) |> render_click()
      assert html =~ "This flow is read-only now."

      flow_view |> element(~s(button[phx-click="request_reopen"])) |> render_click()
      html = flow_view |> element(~s(button[phx-click="confirm_reopen"])) |> render_click()
      assert html =~ "This flow is read-only now."

      assert %{status: "completed"} = instance_at(instance, [only.id])
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

      view |> element(~s(button[phx-click="request_reopen"])) |> render_click()
      view |> element(~s(button[phx-click="confirm_reopen"])) |> render_click()
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
    # Onboarding: Start → Documents (in-order wizard) → Details (any-order
    # wizard). `properties` are the root's - its own type goes there.
    defp onboarding(properties \\ %{}) do
      {:ok, root} =
        Flows.create(%{
          name: "Onboarding",
          label: "subflows",
          status: "open",
          properties: properties
        })

      %{flow: documents, forms: [doc_first, doc_second]} =
        owned_flow_of_two(root, "Documents", "wizard_in_order")

      %{flow: details, forms: [detail_first, detail_second]} =
        owned_flow_of_two(root, "Details", "wizard_any_order")

      first_node = build_node(root, ["Start"], "Start")
      documents_node = subflow_node(root, documents, "Documents")
      details_node = subflow_node(root, details, "Details")

      edge(root, first_node, documents_node)
      edge(root, documents_node, details_node)

      %{
        instance: start_flow(root),
        documents: [[documents_node.id, doc_first.id], [documents_node.id, doc_second.id]],
        details: [[details_node.id, detail_first.id], [details_node.id, detail_second.id]]
      }
    end

    test "each subflow's own type answers for its own forms, behind the root's door",
         %{conn: conn} do
      %{
        instance: instance,
        documents: [doc_first, doc_second],
        details: [detail_first, detail_second]
      } =
        onboarding()

      {:ok, view, html} = live(conn, flow_path(instance))

      # A card per subflow, named in its head, its forms unprefixed inside
      assert html =~ "Documents"
      assert html =~ "Details"
      assert html =~ "First"
      assert html =~ "Second"
      refute html =~ "Documents / First"

      # The in-order subflow gates its second form. The root is In order too
      # (the default for a "subflows" flow), so the whole of Details waits
      # for Documents - whatever the any-order wizard inside would allow
      assert offered?(view, instance, doc_first)
      refute offered?(view, instance, doc_second)
      refute offered?(view, instance, detail_first)
      refute offered?(view, instance, detail_second)

      {:ok, _view, html} = live(conn, edit_path(instance, detail_first))
      assert html =~ "isn&#39;t available yet"

      complete(instance, doc_first)
      complete(instance, doc_second)

      # Documents done, the Details door opens, and the any-order wizard
      # offers both of its forms
      {:ok, view, _html} = live(conn, flow_path(instance))
      assert offered?(view, instance, detail_first)
      assert offered?(view, instance, detail_second)
    end

    test "a form behind a shut door reads Pending, not Available", %{conn: conn} do
      %{
        instance: instance,
        documents: [doc_first, doc_second],
        details: [detail_first, detail_second]
      } = onboarding()

      {:ok, view, _html} = live(conn, flow_path(instance))

      # Details' first form is available inside Details - its Start is - but
      # the root's Details step is shut, so the row offers nothing and says so
      assert badge?(view, doc_first, "Available")
      assert badge?(view, detail_first, "Pending")
      assert badge?(view, detail_second, "Pending")

      complete(instance, doc_first)
      complete(instance, doc_second)

      {:ok, view, _html} = live(conn, flow_path(instance))
      assert badge?(view, detail_first, "Available")
    end

    test "an any-order root opens every subflow from the start", %{conn: conn} do
      %{
        instance: instance,
        documents: [doc_first, doc_second],
        details: [detail_first, detail_second]
      } =
        onboarding(%{"flow_type" => "any_order"})

      {:ok, view, _html} = live(conn, flow_path(instance))

      # Every door open; the in-order wizard inside Documents still gates
      # its own second form
      assert offered?(view, instance, doc_first)
      refute offered?(view, instance, doc_second)
      assert offered?(view, instance, detail_first)
      assert offered?(view, instance, detail_second)
    end

    test "finishing a subflow's last form lands in the next subflow the root opens",
         %{conn: conn} do
      %{instance: instance, documents: [doc_first, doc_second], details: [detail_first, _]} =
        onboarding()

      complete(instance, doc_first)

      {:ok, view, _html} = live(conn, edit_path(instance, doc_second))
      submit(view, instance_at(instance, doc_second), %{"name" => "Ada"})

      # Documents has nothing left; the root, In order, names Details next
      assert {path, _flash} = assert_redirect(view)
      assert path == edit_path(instance, detail_first)
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

  describe "prefilling with answers from another flow" do
    test "the form starts with this user's own answers at the form the property names",
         %{conn: conn} do
      # Last year: a flow with one form
      {:ok, last_year} =
        Flows.create(%{name: "Dog License 2026", slug: "dla2026", status: "open"})

      owner = build_form_node(last_year, "Owner", owner_flow_id: last_year.id)
      edge(last_year, build_node(last_year, ["Start"], "Start"), owner)

      # This year points at it because an admin said so — no copy, no lineage
      this_year = renewing_flow(Property.flow_position(last_year.id, [owner.id]))
      this_instance = start_flow(this_year.flow)

      # Nobody has filed last year yet: the form starts empty
      {:ok, _view, html} = live(conn, edit_path(this_instance, [this_year.form.id]))
      refute html =~ "Rex"

      # The user filed last year. Someone else filed too, and the user also
      # started a later journey they never submitted — neither is theirs to
      # renew from
      complete(start_flow(last_year), [owner.id], %{"name" => "Rex"})

      {:ok, theirs} =
        Instances.Flows.create(%{template_flow_id: last_year.id, user_id: "someone-else"})

      complete(theirs, [owner.id], %{"name" => "Fido"})
      abandoned = start_flow(last_year)
      {:ok, _started} = Instances.Forms.update_status(abandoned, [owner.id], :in_progress)

      {:ok, _view, html} = live(conn, edit_path(this_instance, [this_year.form.id]))
      assert html =~ "Rex"
      refute html =~ "Fido"

      # An answer given this year wins over last year's
      complete(this_instance, [this_year.form.id], %{"name" => "Rex II"})

      {:ok, _reopened} =
        Instances.Forms.update_status(this_instance, [this_year.form.id], :in_progress)

      {:ok, _view, html} = live(conn, edit_path(this_instance, [this_year.form.id]))
      assert html =~ "Rex II"
    end

    test "a pointer that resolves to nothing prefills nothing, and says nothing", %{conn: conn} do
      gone = Property.flow_position(Ecto.UUID.generate(), [Ecto.UUID.generate()])
      renewal = renewing_flow(gone)

      {:ok, view, html} = live(conn, edit_path(start_flow(renewal.flow), [renewal.form.id]))

      # The form opens as any other unanswered form does: no prefill, no
      # word of one — the admin hears about it from the health page instead
      assert html =~ "Name"
      refute html =~ "Missing"
      refute html =~ "Prefill with answers from"
      assert has_element?(view, "button[type=\'submit\']")
    end

    test "an unset property is one query short of nothing: the form starts empty", %{conn: conn} do
      %{instance: instance, form: only} = flow_of_one()

      {:ok, _view, html} = live(conn, edit_path(instance, [only.id]))

      assert html =~ "Name"
      refute html =~ "Rex"
    end
  end

  describe "the library's review form type" do
    test "shows the related form's answers read-only beside the editable form", %{conn: conn} do
      # Start → Intake → Review; Review's form is a "review" of Intake
      {:ok, flow} = Flows.create(%{name: "Application", status: "open"})
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
        {:ok, flow} = Flows.create(%{name: "Application", status: "open"})
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

      {:ok, theirs} =
        Instances.Flows.create(%{template_flow_id: flow.id, user_id: "someone-else"})

      {:ok, _view, html} = isolated(conn, [])

      assert html =~ mine.id
      refute html =~ theirs.id
    end

    test "a host's query lists whoever it says; the tenant is applied on top", %{conn: conn} do
      %{flow: flow, instance: mine} = flow_of_one()

      {:ok, theirs} =
        Instances.Flows.create(%{template_flow_id: flow.id, user_id: "someone-else"})

      {:ok, acme} =
        Instances.Flows.create(%{
          template_flow_id: flow.id,
          user_id: "someone-else",
          tenant_id: "acme"
        })

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
      {:ok, dog} = Flows.create(%{name: "Dog License", status: "open"})
      {:ok, cat} = Flows.create(%{name: "Cat License", status: "open"})
      {:ok, acme} = Flows.create(%{name: "Elsewhere", tenant_id: "acme", status: "open"})

      {:ok, view, _html} = isolated(conn, [])

      assert has_element?(view, start_button(dog))
      assert has_element?(view, start_button(cat))
      assert has_element?(view, start_button(acme))

      {:ok, view, _html} = isolated(conn, [], %{}, "acme")
      assert has_element?(view, start_button(acme))
      refute has_element?(view, start_button(dog))
    end

    test "a host offers what it names; the page refuses to start anything else", %{conn: conn} do
      {:ok, dog} = Flows.create(%{name: "Dog License", status: "open"})
      {:ok, cat} = Flows.create(%{name: "Cat License", status: "open"})

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
      {:ok, acme} = Flows.create(%{name: "Dog License", tenant_id: "acme", status: "open"})

      {:ok, view, _html} = isolated(conn, [], %{"offer" => "dog-license"}, "globex")

      refute has_element?(view, start_button(acme))
    end

    test "the instance pages refuse an instance of a flow the page did not name", %{conn: conn} do
      %{instance: cat_instance, form: only} = flow_of_one(nil, name: "Cat License")
      {:ok, _dog} = Flows.create(%{name: "Dog License", status: "open"})

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
      {:ok, dog} = Flows.create(%{name: "Dog License", status: "open"})
      {:ok, cat} = Flows.create(%{name: "Cat License", status: "open"})

      {:ok, dog_instance} =
        Instances.Flows.create(%{template_flow_id: dog.id, user_id: "dog_owner"})

      {:ok, cat_instance} =
        Instances.Flows.create(%{template_flow_id: cat.id, user_id: "dog_owner"})

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

    test "a flow named by id is the same flow named by slug", %{conn: conn} do
      {:ok, dog} = Flows.create(%{name: "Dog License", status: "open"})
      {:ok, cat} = Flows.create(%{name: "Cat License", status: "open"})

      {:ok, view, _html} = isolated(conn, [], %{"offer_id" => dog.id})

      assert has_element?(view, start_button(dog))
      refute has_element?(view, start_button(cat))
    end
  end

  describe "the flows attr says what a page allows" do
    test "start: false lists the flow, draws no Start section, and still opens journeys",
         %{conn: conn} do
      %{flow: flow, instance: instance, form: only} = flow_of_one(nil, name: "Dog License")
      offer = %{"offer" => "dog-license", "start" => false}

      {:ok, view, html} = isolated(conn, [], offer)

      refute has_element?(view, start_button(flow))
      refute html =~ "Start a new flow"
      refute html =~ "No flows are open."
      assert html =~ instance.id

      # The journey itself is still workable: continue defaults to true
      {:ok, _view, html} = isolated(conn, [instance.id, "forms", only.id, "edit"], offer)
      refute html =~ "not available"
      assert html =~ "Only"
    end

    test "continue: false opens a journey read-only and refuses the edit page", %{conn: conn} do
      %{instance: instance, form: only} = flow_of_one(nil, name: "Dog License")
      read_only = %{"offer" => "dog-license", "start" => false, "continue" => false}

      {:ok, _view, html} = isolated(conn, [instance.id], read_only)
      assert html =~ "Dog License"

      {:ok, view, html} = isolated(conn, [instance.id, "forms", only.id, "edit"], read_only)
      assert html =~ "This flow is read-only now; your answers are kept as they are."
      refute has_element?(view, "fieldset")
      assert Instances.Flows.form_instances(instance) == []

      # The answers page still renders: seeing is what naming the flow allows
      {:ok, _view, html} = isolated(conn, [instance.id, "forms", only.id], read_only)
      refute html =~ "not available"
    end

    test "the flow's status is asked as well as the page's answer", %{conn: conn} do
      {:ok, winding} =
        Flows.create(%{name: "Dog License", status: "winding_down"})

      {:ok, view, html} = isolated(conn, [], %{"offer" => "dog-license"})

      refute has_element?(view, start_button(winding))
      assert html =~ "No longer taking new starts."
    end

    test "with nothing started, the empty line points at no Start section", %{conn: conn} do
      {:ok, _dog} = Flows.create(%{name: "Dog License", status: "open"})
      offer = %{"offer" => "dog-license", "start" => false}

      {:ok, _view, html} = isolated(conn, [], offer)

      assert html =~ "Nothing started yet."
      refute html =~ "start a flow below"

      # The page that does offer one says so
      {:ok, _view, html} = isolated(conn, [], %{"offer" => "dog-license"})
      assert html =~ "start a flow below"
    end

    test "a host's own listing names the user of each journey; the default does not",
         %{conn: conn} do
      {:ok, dog} = Flows.create(%{name: "Dog License", status: "open"})

      {:ok, mine} = Instances.Flows.create(%{template_flow_id: dog.id, user_id: "dog_owner"})
      {:ok, theirs} = Instances.Flows.create(%{template_flow_id: dog.id, user_id: "cat_owner"})

      # The default listing is the viewer's own, so the column would repeat
      # the viewer's id on every row
      {:ok, _view, html} = isolated(conn, [])
      refute html =~ "User ID"
      assert html =~ mine.id
      refute html =~ theirs.id

      # A host query may hold anyone's, so the column is drawn and names them
      {:ok, _view, html} = isolated(conn, [], %{"listing" => "everyone"})
      assert html =~ "User ID"
      assert html =~ mine.id
      assert html =~ theirs.id
      assert html =~ "cat_owner"
    end

    test "a page offering no starts names no winding-down flow either", %{conn: conn} do
      {:ok, _winding} = Flows.create(%{name: "Dog License", status: "winding_down"})

      {:ok, _view, html} =
        isolated(conn, [], %{"offer" => "dog-license", "start" => false})

      refute html =~ "Start a new flow"
      refute html =~ "No longer taking new starts."
    end
  end

  describe "Instances.Flows.list_query/1 narrows by flow" do
    test "by struct, id, or slug, alone or in a list; [] matches nothing" do
      {:ok, dog} = Flows.create(%{name: "Dog License", status: "open"})
      {:ok, cat} = Flows.create(%{name: "Cat License", status: "open"})
      {:ok, acme_dog} = Flows.create(%{name: "Dog License", tenant_id: "acme", status: "open"})
      {:ok, d} = Instances.Flows.create(%{template_flow_id: dog.id, user_id: "u"})
      {:ok, c} = Instances.Flows.create(%{template_flow_id: cat.id, user_id: "u"})

      {:ok, a} =
        Instances.Flows.create(%{template_flow_id: acme_dog.id, user_id: "u", tenant_id: "acme"})

      ids = fn opts ->
        opts
        |> Instances.Flows.list_query()
        |> FormFlowRepo.all()
        |> Enum.map(& &1.id)
        |> Enum.sort()
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

    test "by the journey's own status, with the other options" do
      {:ok, dog} = Flows.create(%{name: "Dog License", status: "open"})
      {:ok, done} = Instances.Flows.create(%{template_flow_id: dog.id, user_id: "u"})
      {:ok, _open} = Instances.Flows.create(%{template_flow_id: dog.id, user_id: "u"})
      {:ok, theirs} = Instances.Flows.create(%{template_flow_id: dog.id, user_id: "v"})
      {:ok, done} = Instances.Flows.complete(done, [])
      {:ok, _theirs} = Instances.Flows.complete(theirs, [])

      ids = fn opts ->
        opts
        |> Instances.Flows.list_query()
        |> FormFlowRepo.all()
        |> Enum.map(& &1.id)
        |> Enum.sort()
      end

      assert ids.(status: "completed") == Enum.sort([done.id, theirs.id])
      assert ids.(status: "completed", user_id: "u", flow: dog) == [done.id]
      assert length(ids.(status: "in_progress")) == 1
      assert length(ids.(status: nil)) == 3

      # list/1 takes it too, newest first
      assert [%{id: id}] = Instances.Flows.list(status: "completed", user_id: "u")
      assert id == done.id
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
      assert has_element?(view, "a[href='/demo/pet-licenses/applications']")
    end

    test "a redirect renders nothing, navigates, and starts nothing", %{conn: conn} do
      %{instance: instance, form: only} = flow_of_one(nil, name: "Elsewhere")

      {:ok, view, html} = isolated(conn, [instance.id, "forms", only.id, "edit"])

      # The first render, before the navigation lands, draws nothing of the page
      refute html =~ "Name"
      refute html =~ "<form"
      assert {"/demo/pet-licenses/applications", _flash} = assert_redirect(view)
      refute instance_at(instance, [only.id])

      {:ok, view, _html} = isolated(conn, [instance.id])
      assert {"/demo/pet-licenses/applications", _flash} = assert_redirect(view)
    end

    test "the listing asks too: a refusal draws the message, a redirect navigates",
         %{conn: conn} do
      %{instance: instance} = flow_of_one()

      {:ok, view, html} = isolated(conn, [], %{"listing" => "refused"})

      assert html =~ "No listing for you."
      refute html =~ instance.id
      refute has_element?(view, "button", "Start")

      {:ok, view, _html} = isolated(conn, [], %{"listing" => "elsewhere"})
      assert {"/demo/pet-licenses/applications", _flash} = assert_redirect(view)
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

  describe "submitting says so in the host's flash" do
    test "the form's name and the word the button used", %{conn: conn} do
      %{instance: instance, form: only} = flow_of_one()
      {:ok, view, _html} = isolated_edit(conn, instance, [only.id])

      submit(view, instance_at(instance, [only.id]), %{"name" => "Ada"})

      # FormFlow is a LiveComponent, and a component's flash reaches the
      # host only when the component navigates - which a submit always does
      assert {_path, flash} = assert_redirect(view)
      assert flash == %{"info" => "Only submitted."}
    end
  end

  describe "submitting runs the form type's completion callbacks" do
    setup do
      :ok = Phoenix.PubSub.subscribe(Demo.PubSub, "form_flow_test")
    end

    test "snapshot/2 lands on the event; handle_complete/2 sees the form done",
         %{conn: conn} do
      %{instance: instance, form: only} = flow_of_one(nil, form_type: "recording")
      {:ok, only} = Flows.update_node(only, %{slug: "recorded-step"})
      {:ok, view, _html} = isolated_edit(conn, instance, [only.id])
      form_instance = instance_at(instance, [only.id])

      submit(view, form_instance, %{"name" => "Ada"})

      # The snapshot saw the form as the page did: still in progress
      assert_receive {:snapshot, %Context{form_instance: %{status: "in_progress"}}}

      # The reaction saw the completed row and the flow instance's fresh progress
      assert_receive {:handle_complete, %Context{} = fresh}
      # The step is in the context by its node, and its slug is the handle a
      # host names it by — the step's own, not the form's, which a catalog
      # form shares with every flow reusing it
      assert fresh.form_node.id == List.last(fresh.form_progress.path)
      assert fresh.form_node.slug == "recorded-step"
      refute fresh.form_node.slug == fresh.form.slug
      assert fresh.form_instance.id == form_instance.id
      assert fresh.form_instance.status == "completed"

      assert %{status: :completed} =
               FlowProgress.find_form(fresh.flow_instance_progress, [only.id])

      # The template side is as at mount
      assert fresh.form.id ==
               Forms.get_version(form_instance.template_form_version_id).form_id

      assert {_path, _flash} = assert_redirect(view)

      assert %{snapshot: %{"seen" => %{"status" => "in_progress"}}} =
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

      assert %{snapshot: %{"reviewed" => reviewed}} =
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

      assert %{snapshot: %{"reviewed" => %{"path" => path, "instance_id" => nil}}} =
               Instances.Forms.latest_event(review_instance, "status_changed")

      assert path == intake.id

      {:ok, flow} = Flows.create(%{name: "Application", status: "open"})
      first_node = build_node(flow, ["Start"], "Start")

      review_form =
        published_form("Review", form_type: "review", property_values: %{"source" => "gone"})

      review = build_node(flow, ["Form"], "Review", %{form_id: review_form.id})
      edge(flow, first_node, review)
      instance = start_flow(flow)

      review_instance = reviewed(conn, %{instance: instance, review: review})

      assert %{snapshot: %{"reviewed" => %{"path" => "gone", "instance_id" => nil}}} =
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
      assert html =~ "Intake is being edited - reopened on"
      refute html =~ "submitted again"
    end

    test "a publish that reopens the source is a migration, not a user's reopen", %{conn: conn} do
      %{instance: instance, intake: intake, review: review} = fixture = review_flow()
      source = complete(instance, [intake.id], %{"name" => "Ada"})
      reviewed(conn, fixture)

      published = Forms.get_version(source.template_form_version_id)
      {:ok, draft} = Forms.create_draft(published.form_id, based_on: published.id)

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

      assert %{snapshot: %{"reviewed" => %{"data" => %{}, "redacted_at" => _at}}} =
               Instances.Forms.latest_event(review_instance, "status_changed")

      {:ok, _view, html} = live(conn, form_path(instance, [review.id]))
      assert html =~ "The record of what was reviewed has been erased."
      refute html =~ "Ada"
    end
  end

  describe "reopening a form stamps reopened_at" do
    test "set by a reopen, cleared by the next submit" do
      %{instance: instance, form: only} = flow_of_one()

      completed = complete(instance, [only.id], %{"name" => "Ada"})
      assert completed.reopened_at == nil

      {:ok, reopened} = Instances.Forms.update_status(instance, [only.id], :in_progress)
      assert %DateTime{} = reopened.reopened_at
      assert reopened.completed_at == nil

      {:ok, resubmitted} =
        Instances.Forms.update_status(instance, [only.id], :completed, data: %{"name" => "Ada"})

      assert resubmitted.reopened_at == nil
      assert %DateTime{} = resubmitted.completed_at
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
        Flows.create(%{
          name: "Application",
          properties: properties("wizard_any_order"),
          status: "open"
        })

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
          complete(instance, [review_a.id], %{"name" => "Looks right"}, snapshot: snapshot)

        review_b =
          complete(instance, [review_b.id], %{"name" => "Agreed"}, snapshot: snapshot)

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

        assert %{"reviewed" => reviewed} = event.snapshot
        assert reviewed["data"] == %{}
        assert {:ok, _at, 0} = DateTime.from_iso8601(reviewed["redacted_at"])
        # Identity kept: what was reviewed stays on record, only the answers go
        assert reviewed["instance_id"] == journey.source.id
        assert reviewed["version_id"] == journey.source.template_form_version_id
        # The row is otherwise the row it was
        assert Map.drop(event, [:snapshot, :__meta__]) ==
                 Map.drop(was, [:snapshot, :__meta__])
      end

      # The other journey's copies are of its own Intake, and stay
      for review <- other.reviews do
        assert %{"reviewed" => %{"data" => %{"name" => "Ada"}} = reviewed} =
                 Instances.Forms.latest_event(review, "status_changed").snapshot

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
                 Instances.Forms.latest_event(review, "status_changed").snapshot
      end
    end

    test "deleting the whole journey takes the copies with it, and touches no other journey" do
      %{journey: journey, other: other} = reviewed_journeys()

      assert {:ok, _deleted} = Instances.Flows.delete_instance(journey.instance)

      refute Instances.Flows.get(journey.instance.id)
      assert Instances.Flows.form_instances(journey.instance) == []

      for review <- other.reviews do
        assert %{"reviewed" => %{"data" => %{"name" => "Ada"}}} =
                 Instances.Forms.latest_event(review, "status_changed").snapshot
      end
    end
  end

  # ── URLs ────────────────────────────────────────────────────────────────

  describe "prefills" do
    test "a flow being tried out offers the form's prefills, and one fills the form in",
         %{conn: conn} do
      %{flow: flow, instance: instance, form: node} = flow_of_one()
      {:ok, _flow} = Flows.update_status(flow, "pre_release")

      {:ok, _form} =
        Forms.create_prefill(Forms.get(node.form_id), %{
          name: "Happy path",
          data: %{"name" => "Rex"}
        })

      {:ok, view, html} = live(conn, edit_path(instance, [node.id]))

      assert html =~ ~s(placeholder="Prefill")
      assert html =~ "This flow isn&#39;t open yet"

      # Choosing one names it in the URL, the way the template pages do
      assert {:error, {:live_redirect, %{to: to}}} =
               view
               |> element(~s(form[phx-change="pick_prefill"]))
               |> render_change(%{"prefill" => "Happy path"})

      assert to == edit_path(instance, [node.id]) <> "?prefill=Happy+path"

      {:ok, _view, html} = live(conn, to)
      assert html =~ ~s(value="Rex")
    end

    test "what the user has answered wins over the prefill", %{conn: conn} do
      %{flow: flow, instance: instance, form: node} = flow_of_one()
      {:ok, _flow} = Flows.update_status(flow, "pre_release")

      {:ok, _form} =
        Forms.create_prefill(Forms.get(node.form_id), %{
          name: "Happy path",
          data: %{"name" => "Rex"}
        })

      complete(instance, [node.id], %{"name" => "Typed by hand"})
      {:ok, _reopened} = Instances.Forms.update_status(instance, [node.id], :in_progress)

      {:ok, _view, html} =
        live(conn, edit_path(instance, [node.id]) <> "?prefill=Happy+path")

      assert html =~ ~s(value="Typed by hand")
      refute html =~ ~s(value="Rex")
    end

    test "an open flow offers none — this is for a flow not open yet", %{conn: conn} do
      %{instance: instance, form: node} = flow_of_one()

      {:ok, _form} =
        Forms.create_prefill(Forms.get(node.form_id), %{
          name: "Happy path",
          data: %{"name" => "Rex"}
        })

      {:ok, view, html} = live(conn, edit_path(instance, [node.id]))

      refute html =~ ~s(placeholder="Prefill")
      refute html =~ "Happy path"

      # Nor the menu that writes them: every write event is guarded on the
      # same status this is
      refute has_element?(view, "#instance-forms-edit-prefill-actions button", "New prefill")
      refute has_element?(view, "#instance-forms-edit-prefill-actions-capture")
    end

    test "a flow being tried out writes them too", %{conn: conn} do
      %{flow: flow, instance: instance, form: node} = flow_of_one()
      {:ok, _flow} = Flows.update_status(flow, "pre_release")

      {:ok, view, _html} = live(conn, edit_path(instance, [node.id]))

      # New and Capture write a prefill that need not exist yet, so both are
      # there with nothing selected; the other two act on a selection
      assert has_element?(view, "#instance-forms-edit-prefill-actions button", "New prefill")
      assert has_element?(view, "#instance-forms-edit-prefill-actions-capture")
      refute has_element?(view, "#instance-forms-edit-prefill-actions button", "Edit prefill")
      refute has_element?(view, "#instance-forms-edit-prefill-actions button", "Delete prefill")

      # Capture reads the form the user is filling in — the one the form type
      # drew under the id this page handed it
      form_id = "instance-forms-edit-#{instance_at(instance, [node.id]).id}-form"

      assert has_element?(view, "form##{form_id}")

      assert has_element?(
               view,
               ~s(#instance-forms-edit-prefill-actions-capture[data-form-id="#{form_id}"])
             )
    end

    test "capturing a journey walked by hand saves it as a prefill", %{conn: conn} do
      %{flow: flow, instance: instance, form: node} = flow_of_one()
      {:ok, _flow} = Flows.update_status(flow, "pre_release")

      {:ok, view, _html} = live(conn, edit_path(instance, [node.id]))

      view
      |> element("#instance-forms-edit-prefill-actions-capture")
      |> render_hook("capture_prefill", %{"params" => "dynamic_form%5Bname%5D=Rex"})

      html = render(view)
      assert html =~ "New prefill"
      assert html =~ "Rex"

      # The note that makes this safe to offer here: a prefill is everyone's
      assert html =~ "Prefills are shared"

      assert {:error, {:live_redirect, %{to: to}}} =
               view
               |> element(~s(form[phx-submit="save_prefill"]))
               |> render_submit(%{"name" => "Happy path", "data" => ~s({"name": "Rex"})})

      assert to == edit_path(instance, [node.id]) <> "?prefill=Happy+path"

      assert [prefill] = Forms.list_prefills(Forms.get(node.form_id))
      assert prefill.name == "Happy path"
      assert prefill.data == %{"name" => "Rex"}
      assert prefill.user_id == "dog_owner"
    end

    test "updating the selected one re-fills the form with it", %{conn: conn} do
      %{flow: flow, instance: instance, form: node} = flow_of_one()
      {:ok, _flow} = Flows.update_status(flow, "pre_release")

      {:ok, _form} =
        Forms.create_prefill(Forms.get(node.form_id), %{
          name: "Happy path",
          data: %{"name" => "Rex"}
        })

      {:ok, view, html} =
        live(conn, edit_path(instance, [node.id]) <> "?prefill=Happy+path")

      assert html =~ ~s(value="Rex")

      view
      |> element("#instance-forms-edit-prefill-actions button", "Edit prefill")
      |> render_click()

      # Same name, so the selection does not move and the page stays put —
      # and the form is filled from what was just written
      view
      |> element(~s(form[phx-submit="save_prefill"]))
      |> render_submit(%{"name" => "Happy path", "data" => ~s({"name": "Rexington"})})

      assert Forms.get_prefill(Forms.get(node.form_id), "Happy path").data == %{
               "name" => "Rexington"
             }

      assert render(view) =~ ~s(value="Rexington")
    end

    test "deleting the selected one takes its answers off the form", %{conn: conn} do
      %{flow: flow, instance: instance, form: node} = flow_of_one()
      {:ok, _flow} = Flows.update_status(flow, "pre_release")

      {:ok, _form} =
        Forms.create_prefill(Forms.get(node.form_id), %{
          name: "Happy path",
          data: %{"name" => "Rex"}
        })

      {:ok, view, _html} =
        live(conn, edit_path(instance, [node.id]) <> "?prefill=Happy+path")

      view
      |> element("#instance-forms-edit-prefill-actions button", "Delete prefill")
      |> render_click()

      assert Forms.list_prefills(Forms.get(node.form_id)) == []
      refute render(view) =~ ~s(value="Rex")
    end
  end

  describe "drafts" do
    test "Save draft keeps the form as it stands, and the next visit draws it", %{conn: conn} do
      %{instance: instance, form: node} = flow_of_one()

      {:ok, view, html} = live(conn, edit_path(instance, [node.id]))
      form_instance = instance_at(instance, [node.id])

      # The button reads the form the user is filling in - the same form
      # Capture reads, by the same id - and there is no draft yet
      form_id = "instance-forms-edit-#{form_instance.id}-form"
      assert has_element?(view, ~s(#instance-forms-edit-save-draft[data-form-id="#{form_id}"]))
      refute html =~ "Draft saved"

      view
      |> element("#instance-forms-edit-save-draft")
      |> render_hook("save_draft", %{"params" => "dynamic_form%5Bname%5D=Re"})

      # The header says so, from the draft itself
      html = render(view)
      assert html =~ "Draft saved"
      assert html =~ "just now"
      assert html =~ "dog_owner"

      # Stored as typed, beside the answers and not in them; status unmoved
      saved = instance_at(instance, [node.id])
      assert saved.status == "in_progress"
      assert saved.data == %{}
      assert saved.draft["data"] == %{"name" => "Re"}
      assert saved.draft["user_id"] == "dog_owner"

      draft = Instances.Forms.get_draft(saved)
      assert draft.data == %{"name" => "Re"}
      assert draft.user_id == "dog_owner"
      assert %DateTime{} = draft.saved_at

      # No event: the trail says what happened to the form, and nothing did
      assert Enum.map(Instances.Forms.list_events(saved), & &1.event) == ["created"]

      # The next visit draws it
      {:ok, _view, html} = live(conn, edit_path(instance, [node.id]))
      assert html =~ ~s(value="Re")
      assert html =~ "Draft saved"
    end

    test "Save draft turns the button green, since it never leaves the page", %{conn: conn} do
      %{instance: instance, form: node} = flow_of_one()

      {:ok, view, _html} = live(conn, edit_path(instance, [node.id]))
      assert has_element?(view, "#instance-forms-edit-save-draft.btn-ghost")

      view
      |> element("#instance-forms-edit-save-draft")
      |> render_hook("save_draft", %{"params" => "dynamic_form%5Bname%5D=Re"})

      # Green for a moment - a save writes without navigating, so there is no
      # flash to carry the news. A timed send_update takes it off again.
      assert has_element?(view, "#instance-forms-edit-save-draft.btn-success")
      refute has_element?(view, "#instance-forms-edit-save-draft.btn-ghost")
    end

    test "a draft need not be valid, and submitting clears it", %{conn: conn} do
      %{instance: instance, form: node} =
        flow_of_one(nil,
          definition: %{
            "elements" => [
              %{"type" => "text", "name" => "name", "title" => "Name", "isRequired" => true}
            ]
          }
        )

      {:ok, view, _html} = live(conn, edit_path(instance, [node.id]))
      form_instance = instance_at(instance, [node.id])

      # The required question left blank - a submit would refuse this
      view
      |> element("#instance-forms-edit-save-draft")
      |> render_hook("save_draft", %{"params" => "dynamic_form%5Bname%5D="})

      assert instance_at(instance, [node.id]).draft["data"] == %{"name" => ""}

      # A second save replaces the first
      {:ok, saved} = Instances.Forms.save_draft(instance, [node.id], %{"name" => "Rex"})
      assert saved.draft["data"] == %{"name" => "Rex"}

      submit(view, form_instance, %{"name" => "Rex"})

      completed = instance_at(instance, [node.id])
      assert completed.status == "completed"
      assert completed.data == %{"name" => "Rex"}
      assert completed.draft == nil
      assert Instances.Forms.get_draft(completed) == nil
    end

    test "save_draft/4 refuses a position with no instance, and a submitted one" do
      %{instance: instance, form: node} = flow_of_one()

      # A draft never starts a form
      assert {:error, :not_found} =
               Instances.Forms.save_draft(instance, [node.id], %{"name" => "R"})

      complete(instance, [node.id], %{"name" => "Rex"})

      assert {:error, :completed} =
               Instances.Forms.save_draft(instance, [node.id], %{"name" => "R"})

      assert instance_at(instance, [node.id]).draft == nil
    end

    test "the draft is drawn over the stored answers and a prefill; Show keeps the answers",
         %{conn: conn} do
      %{flow: flow, instance: instance, form: node} = flow_of_one()
      {:ok, _flow} = Flows.update_status(flow, "pre_release")

      {:ok, _form} =
        Forms.create_prefill(Forms.get(node.form_id), %{
          name: "Happy path",
          data: %{"name" => "Prefilled"}
        })

      complete(instance, [node.id], %{"name" => "Submitted"})
      {:ok, _reopened} = Instances.Forms.update_status(instance, [node.id], :in_progress)

      {:ok, _saved} =
        Instances.Forms.save_draft(instance, [node.id], %{"name" => "Drafted"},
          user_id: "dog_owner"
        )

      {:ok, _view, html} = live(conn, edit_path(instance, [node.id]) <> "?prefill=Happy+path")

      assert html =~ ~s(value="Drafted")
      refute html =~ ~s(value="Submitted")
      refute html =~ ~s(value="Prefilled")

      # The status badge is the form's status word, not the button: Reopened
      assert html =~ "Reopened"

      # Show renders the answers, never the draft
      {:ok, _view, html} = live(conn, form_path(instance, [node.id]))

      assert html =~ ~s(value="Submitted")
      refute html =~ ~s(value="Drafted")
      refute html =~ "Draft saved"
    end

    test "Discard changes removes the draft and puts the form back to its answers",
         %{conn: conn} do
      %{instance: instance, form: node} = flow_of_one()

      {:ok, view, _html} = live(conn, edit_path(instance, [node.id]))
      {:ok, _saved} = Instances.Forms.save_draft(instance, [node.id], %{"name" => "Drafted"})

      # Never submitted: it asks, then the form comes back empty
      view |> element("#instance-forms-edit-discard") |> render_click()
      assert render(view) =~ "Discard changes?"

      view |> element("#instance-forms-edit-confirm-discard") |> render_click()

      assert {to, flash} = assert_redirect(view)
      assert to == edit_path(instance, [node.id])
      assert flash == %{"info" => "Changes discarded."}
      assert instance_at(instance, [node.id]).draft == nil

      {:ok, _view, html} = live(conn, to)
      refute html =~ ~s(value="Drafted")
      refute html =~ "Draft saved"

      # Submitted, reopened, drafted: back to the submitted answers
      complete(instance, [node.id], %{"name" => "Submitted"})
      {:ok, _reopened} = Instances.Forms.update_status(instance, [node.id], :in_progress)
      {:ok, _saved} = Instances.Forms.save_draft(instance, [node.id], %{"name" => "Drafted"})

      {:ok, view, html} = live(conn, edit_path(instance, [node.id]))
      assert html =~ ~s(value="Drafted")

      view |> element("#instance-forms-edit-discard") |> render_click()

      assert {:error, {:live_redirect, %{to: to}}} =
               view |> element("#instance-forms-edit-confirm-discard") |> render_click()

      {:ok, _view, html} = live(conn, to)
      assert html =~ ~s(value="Submitted")
      refute html =~ ~s(value="Drafted")

      # Keep editing closes the dialog and changes nothing
      {:ok, _saved} = Instances.Forms.save_draft(instance, [node.id], %{"name" => "Again"})
      {:ok, view, _html} = live(conn, edit_path(instance, [node.id]))
      view |> element("#instance-forms-edit-discard") |> render_click()
      view |> element("button", "Keep editing") |> render_click()
      refute render(view) =~ "Discard changes?"
      assert instance_at(instance, [node.id]).draft["data"] == %{"name" => "Again"}

      # No event for any of it
      assert Enum.map(Instances.Forms.list_events(instance_at(instance, [node.id])), & &1.event) ==
               ["created", "status_changed", "reopened"]
    end

    test "delete_draft/2 refuses a position with no instance, and is a no-op without a draft" do
      %{instance: instance, form: node} = flow_of_one()

      assert {:error, :not_found} = Instances.Forms.delete_draft(instance, [node.id])

      {:ok, started} = Instances.Forms.update_status(instance, [node.id], :in_progress)
      assert {:ok, ^started} = Instances.Forms.delete_draft(instance, [node.id])
    end
  end

  defp flow_path(instance), do: "/demo/pet-licenses/applications/#{instance.id}"

  defp form_path(instance, path), do: "#{flow_path(instance)}/forms/#{Enum.join(path, "/")}"

  defp edit_path(instance, path), do: "#{form_path(instance, path)}/edit"

  defp history_path(instance, path), do: "#{form_path(instance, path)}/history"

  defp offered?(view, instance, path) do
    has_element?(view, "a[href='#{edit_path(instance, path)}']")
  end

  # The badge word on one form's row of a flow instance's page
  defp badge?(view, path, word) do
    has_element?(view, "[data-path='#{Enum.join(path, ",")}'] .badge", word)
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
    {:ok, flow} =
      Flows.create(%{name: "Application", properties: properties(type), status: "open"})

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
    {:ok, flow} = Flows.create(%{name: name, properties: properties(type), status: "open"})

    first_node = build_node(flow, ["Start"], "Start")
    only = build_form_node(flow, "Only", opts)

    edge(flow, first_node, only)

    %{flow: flow, instance: start_flow(flow), form: only}
  end

  # The same, with the form left in draft: the position exists and the flow's
  # type allows work there, but there is no published version to start on
  defp flow_of_one_unpublished do
    {:ok, flow} = Flows.create(%{name: "Unpublished", status: "open"})

    {:ok, form} = Forms.create(%{name: "Draft #{System.unique_integer([:positive])}"})

    first_node = build_node(flow, ["Start"], "Start")
    only = build_node(flow, ["Form"], "Only", %{form_id: form.id})

    edge(flow, first_node, only)

    %{flow: flow, instance: start_flow(flow), form: only}
  end

  # One subflow node wrapping a two-form child flow, so its positions are two
  # segments deep
  defp nested_flow do
    {:ok, root} = Flows.create(%{name: "Onboarding", label: "subflows", status: "open"})

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
  defp properties(type), do: %{"flow_type" => type}

  defp start_flow(flow) do
    {:ok, instance} = Instances.Flows.create(%{template_flow_id: flow.id, user_id: "dog_owner"})

    instance
  end

  # Starts and submits the form at `path`; `opts` reach the completion
  # (`snapshot:` writes a payload on its `status_changed` event)
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
    {:ok, flow} =
      Flows.create(%{
        name: "Application",
        properties: properties("wizard_any_order"),
        status: "open"
      })

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

  # An open flow of one form typed "default" with `value` set as the form it
  # prefills from — this year's licence, pointing at last year's
  defp renewing_flow(value) do
    {:ok, flow} = Flows.create(%{name: "Dog License 2027", slug: "dla2027", status: "open"})

    form =
      build_form_node(flow, "Owner",
        owner_flow_id: flow.id,
        form_type: "default",
        property_values: %{"prefill_with_answers_from" => value}
      )

    edge(flow, build_node(flow, ["Start"], "Start"), form)

    %{flow: flow, form: form}
  end

  defp subflow_node(flow, subflow, label) do
    build_node(flow, ["Subflow"], label, %{subflow_id: subflow.id})
  end

  # A published form with one text question, "name"; `form_type:` picks a
  # form type for it and `property_values:` its property values — for the
  # demo's prefill type, "Demo User" as the name to prefill unless given.
  # `owner_flow_id:` makes it a flow's own form rather than a catalog one.
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
        properties: properties,
        owner_flow_id: opts[:owner_flow_id]
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
