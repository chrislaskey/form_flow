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

  import Phoenix.LiveViewTest

  alias FormFlow.Data.Instances
  alias FormFlow.Data.Repo, as: FormFlowRepo
  alias FormFlow.Data.Templates.Flow
  alias FormFlow.Data.Templates.Flows
  alias FormFlow.Data.Templates.Forms

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

  # ── URLs ────────────────────────────────────────────────────────────────

  defp flow_path(instance), do: "/users/flows/#{instance.id}"

  defp form_path(instance, path), do: "#{flow_path(instance)}/forms/#{Enum.join(path, "/")}"

  defp edit_path(instance, path), do: "#{form_path(instance, path)}/edit"

  defp offered?(view, instance, path) do
    has_element?(view, "a[href='#{edit_path(instance, path)}']")
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

  defp flow_of_one(type \\ nil, opts \\ []) do
    {:ok, flow} = Flows.create(%{name: "Single", properties: properties(type)})

    first_node = build_node(flow, ["Start"], "Start")
    only = build_form_node(flow, "Only", opts)

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

  defp complete(instance, path, data \\ %{}) do
    {:ok, _opened} = Instances.Forms.update_status(instance, path, :in_progress)
    {:ok, completed} = Instances.Forms.update_status(instance, path, :completed, data: data)

    completed
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
  # demo's prefill type, "Demo User" as the name to prefill unless given
  defp published_form(name, opts \\ []) do
    properties =
      case opts[:form_type] do
        nil ->
          %{}

        type ->
          values = Keyword.get(opts, :property_values, %{"name" => "Demo User"})
          %{"form_type" => type, "form_type_property_values" => values}
      end

    {:ok, form} =
      Forms.create(%{
        name: "#{name} #{System.unique_integer([:positive])}",
        properties: properties
      })

    [draft] = form.versions

    definition = %{"elements" => [%{"type" => "text", "name" => "name", "title" => "Name"}]}
    {:ok, draft} = Forms.update_draft(draft, %{definition: definition})
    {:ok, _published} = Forms.update_status(draft, :published)

    form
  end
end
