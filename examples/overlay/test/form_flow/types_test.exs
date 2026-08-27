defmodule Demo.FormFlowTypesTest do
  @moduledoc """
  Exercises the user-facing pages — the journey listing and the form fill
  page — against a real database and a real LiveView mount.

  The library's own tests stop at the `FormFlow.Flows.Types` modules and the
  `FormFlow.Data.Instances.FlowProgress` list they reason about; this is where
  a stored `form_flow_type` is proven to actually change what a filler sees:
  which forms offer to open, which of them are navigable, and where
  submitting leads. It covers the demo's own type too, which is the only
  place the whole `FormFlow.Config` → `FormFlow.Flows.Types` path runs end to
  end.
  """

  use DemoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias FormFlow.Data.Instances
  alias FormFlow.Data.Repo, as: FormFlowRepo
  alias FormFlow.Data.Templates.Flow
  alias FormFlow.Data.Templates.Flows
  alias FormFlow.Data.Templates.Forms

  describe "one flow: the journey listing" do
    test "in order offers the first form only", %{conn: conn} do
      %{journey: journey, forms: [name, address]} = flow_of_two("wizard_in_order")

      {:ok, view, html} = live(conn, "/users/journeys/#{journey.id}")

      assert html =~ "Available"
      assert html =~ "Pending"
      assert has_element?(view, "button[phx-value-path='#{name.id}']")
      refute has_element?(view, "button[phx-value-path='#{address.id}']")
    end

    test "any order offers every form, so a filler can start anywhere", %{conn: conn} do
      %{journey: journey, forms: [name, address]} = flow_of_two("wizard_any_order")

      {:ok, view, _html} = live(conn, "/users/journeys/#{journey.id}")

      assert has_element?(view, "button[phx-value-path='#{name.id}']")
      assert has_element?(view, "button[phx-value-path='#{address.id}']")
    end
  end

  describe "one flow: the form fill page" do
    test "in order draws the progress, none of it navigable", %{conn: conn} do
      %{journey: journey, forms: [name, address]} = flow_of_two("wizard_in_order")

      {:ok, view, html} = live(conn, fill_path(journey, open_form(journey, name)))

      assert html =~ "Name"
      assert html =~ "Address"
      assert html =~ ~s(aria-current="step")
      assert has_element?(view, "button[phx-value-path='#{name.id}'][disabled]")
      assert has_element?(view, "button[phx-value-path='#{address.id}'][disabled]")
    end

    test "any order makes the other forms navigable, and jumping opens them", %{conn: conn} do
      %{journey: journey, forms: [name, address]} = flow_of_two("wizard_any_order")

      {:ok, view, _html} = live(conn, fill_path(journey, open_form(journey, name)))

      # The form being filled is never a link to itself — only the others are.
      assert has_element?(view, "button[phx-value-path='#{name.id}'][disabled]")
      refute has_element?(view, "button[phx-value-path='#{address.id}'][disabled]")

      view |> element("button[phx-value-path='#{address.id}']") |> render_click()

      # Jumping ahead is what created the form's instance — create-on-open
      assert {path, _flash} = assert_redirect(view)
      assert path == fill_path(journey, instance_at(journey, [address.id]))
    end

    test "a lone form is no sequence, so nothing is drawn", %{conn: conn} do
      %{journey: journey, form: only} = flow_of_one("wizard_in_order")

      {:ok, _view, html} = live(conn, fill_path(journey, open_form(journey, only)))

      refute html =~ "open_form"
    end
  end

  describe "several flows in one journey" do
    test "each subflow's own type answers for its own forms", %{conn: conn} do
      {:ok, root} = Flows.create(%{name: "Onboarding", label: "subflows"})

      %{flow: documents, forms: [doc_first, doc_second]} =
        owned_flow_of_two(root, "Documents", "wizard_in_order")

      %{flow: details, forms: [detail_first, detail_second]} =
        owned_flow_of_two(root, "Details", "wizard_any_order")

      start = build_node(root, ["Start"], "Start")
      documents_node = subflow_node(root, documents, "Documents")
      details_node = subflow_node(root, details, "Details")

      edge(root, start, documents_node)
      edge(root, documents_node, details_node)

      journey = journey(root)

      {:ok, view, html} = live(conn, "/users/journeys/#{journey.id}")

      # Forms are labeled by the subflow they were reached through
      assert html =~ "Documents / First"
      assert html =~ "Details / Second"

      # The in-order subflow gates its second form; the any-order one doesn't
      assert has_element?(view, "button[phx-value-path='#{documents_node.id},#{doc_first.id}']")
      refute has_element?(view, "button[phx-value-path='#{documents_node.id},#{doc_second.id}']")
      assert has_element?(view, "button[phx-value-path='#{details_node.id},#{detail_first.id}']")
      assert has_element?(view, "button[phx-value-path='#{details_node.id},#{detail_second.id}']")
    end
  end

  describe "the demo's own type" do
    test "the users config resolves \"demo_checklist\" to the demo's module", %{conn: conn} do
      %{journey: journey, forms: [name, address]} = flow_of_two("demo_checklist")

      {:ok, view, _html} = live(conn, "/users/journeys/#{journey.id}")

      # openable?/2: nothing is gated on the flow's order
      assert has_element?(view, "button[phx-value-path='#{name.id}']")
      assert has_element?(view, "button[phx-value-path='#{address.id}']")
    end

    test "its show_progress?/1 draws the list even for a single form", %{conn: conn} do
      %{journey: journey, form: only} = flow_of_one("demo_checklist")

      {:ok, view, html} = live(conn, fill_path(journey, open_form(journey, only)))

      # Where a wizard would draw nothing, the checklist draws its one entry
      assert html =~ "open_form"
      assert has_element?(view, "button[phx-value-path='#{only.id}'][disabled]")
    end
  end

  # ── fixtures ────────────────────────────────────────────────────────────

  # Start → Name → Address → End, one "forms" flow of the given type
  defp flow_of_two(type) do
    {:ok, flow} = Flows.create(%{name: "Application", properties: %{"form_flow_type" => type}})

    start = build_node(flow, ["Start"], "Start")
    name = build_form_node(flow, "Name")
    address = build_form_node(flow, "Address")
    stop = build_node(flow, ["End"], "End")

    edge(flow, start, name)
    edge(flow, name, address)
    edge(flow, address, stop)

    %{flow: flow, journey: journey(flow), forms: [name, address]}
  end

  defp flow_of_one(type) do
    {:ok, flow} = Flows.create(%{name: "Single", properties: %{"form_flow_type" => type}})

    start = build_node(flow, ["Start"], "Start")
    only = build_form_node(flow, "Only")

    edge(flow, start, only)

    %{flow: flow, journey: journey(flow), form: only}
  end

  # A private child flow of `root`: Start → First → Second → End
  defp owned_flow_of_two(root, name, type) do
    {:ok, flow} =
      Flows.create(%{
        name: name,
        label: "forms",
        owner_flow_id: root.id,
        properties: %{"form_flow_type" => type}
      })

    start = build_node(flow, ["Start"], "Start")
    first = build_form_node(flow, "First")
    second = build_form_node(flow, "Second")
    stop = build_node(flow, ["End"], "End")

    edge(flow, start, first)
    edge(flow, first, second)
    edge(flow, second, stop)

    %{flow: flow, forms: [first, second]}
  end

  defp journey(flow) do
    {:ok, journey} = Instances.Flows.create(%{flow_id: flow.id, user_id: "demo-user"})

    journey
  end

  # Opens a root-level form the way clicking Open does — creating its
  # instance, which is what the fill page is addressed by
  defp open_form(journey, node) do
    {:ok, instance} = Instances.Forms.update_status(journey, [node.id], :in_progress)

    instance
  end

  defp instance_at(journey, path) do
    Enum.find(Instances.Flows.form_instances(journey), &(&1.path == path))
  end

  defp fill_path(journey, instance) do
    "/users/journeys/#{journey.id}/instances/#{instance.id}"
  end

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

  defp build_form_node(flow, label) do
    build_node(flow, ["Form"], label, %{form_id: published_form(label).id})
  end

  defp subflow_node(flow, subflow, label) do
    build_node(flow, ["Subflow"], label, %{subflow_id: subflow.id})
  end

  defp published_form(name) do
    {:ok, form} = Forms.create(%{name: "#{name} #{System.unique_integer([:positive])}"})
    [draft] = form.versions
    {:ok, draft} = Forms.update_draft(draft, %{definition: %{"fields" => []}})
    {:ok, _published} = Forms.update_status(draft, :published)

    form
  end
end
