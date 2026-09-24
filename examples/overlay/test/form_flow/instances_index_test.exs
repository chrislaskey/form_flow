defmodule Demo.FormFlowInstancesIndexTest do
  @moduledoc """
  Exercises the user-facing flow listing's `Slab.table` against a real
  database — query mode, so the sorting and pagination the URL asks for have
  to compile into real SQL rather than being applied to a list in memory.

  The template indexes get the same treatment in `flows_crud_test.exs` and
  `forms_crud_test.exs`; this is the third of the three, and the one whose
  rows carry a preloaded association Slab resolves after counting.

  Two things to know about asserting on these. Slab keeps its `id` on the
  LiveComponent and derives ids for the parts it renders, so the table's
  presence is probed through one of those — here the page-size control the
  `<:pagination>` slot brings — rather than through the id passed to it, the
  same trick `install_check_live_test.exs` documents. And
  presence of a *row* is asserted through the instance id in its link: a
  flow's name also appears in the "start a new flow" picker beside the table,
  so matching on names alone would pass with no row rendered at all.
  """

  @table "#flow-instances-table-per-page"

  use DemoWeb.ConnCase, async: false

  # /demo/pet-licenses/applications is the user experience
  @moduletag user: "dog_owner"

  import Phoenix.LiveViewTest

  alias FormFlow.Data.Instances
  alias FormFlow.Data.Repo, as: FormFlowRepo
  alias FormFlow.Data.Templates.Flow
  alias FormFlow.Data.Templates.Flows
  alias FormFlow.Data.Templates.Forms

  test "lists the current user's flow instances, newest first", %{conn: conn} do
    older = start_flow("Older", "dog_owner")
    newer = start_flow("Newer", "dog_owner")

    {:ok, view, html} = live(conn, "/demo/pet-licenses/applications")

    assert has_element?(view, @table)
    assert has_element?(view, row_link(older), "Older")
    assert has_element?(view, row_link(newer), "Newer")
    assert row_order(html, [newer, older]) == :in_order
  end

  test "the flow's name comes from the preloaded template", %{conn: conn} do
    instance = start_flow("Benefits Application", "dog_owner")

    {:ok, view, _html} = live(conn, "/demo/pet-licenses/applications")

    # A joined value, rendered per row — so the preload survived Slab's count
    assert has_element?(view, row_link(instance), "Benefits Application")
  end

  test "another user's instances are not listed", %{conn: conn} do
    mine = start_flow("Mine", "dog_owner")
    theirs = start_flow("Theirs", "someone-else")

    {:ok, _view, html} = live(conn, "/demo/pet-licenses/applications")

    assert html =~ mine.id
    refute html =~ theirs.id
  end

  test "an empty listing says so instead of drawing a table", %{conn: conn} do
    {:ok, view, html} = live(conn, "/demo/pet-licenses/applications")

    refute has_element?(view, @table)
    assert html =~ "Nothing started yet"
  end

  test "the URL's sort compiles into the query", %{conn: conn} do
    older = start_flow("Older", "dog_owner")
    newer = start_flow("Newer", "dog_owner")

    {:ok, _view, html} =
      live(conn, "/demo/pet-licenses/applications?sort=inserted_at&sort_direction=asc")

    assert row_order(html, [older, newer]) == :in_order
  end

  test "pagination splits the rows instead of rendering them all", %{conn: conn} do
    instances = for i <- 1..11, do: start_flow("Flow #{i}", "dog_owner")

    {:ok, _view, page_one} = live(conn, "/demo/pet-licenses/applications")
    {:ok, _view, page_two} = live(conn, "/demo/pet-licenses/applications?page=2")

    assert rows_on_page(page_one, instances) == 10
    assert rows_on_page(page_two, instances) == 1
  end

  test "the start-a-flow picker is a plain list beside the table", %{conn: conn} do
    {:ok, flow} = Flows.create(%{name: "Startable", status: "open"})

    {:ok, view, _html} = live(conn, "/demo/pet-licenses/applications")

    view |> element("button[phx-value-flow-id='#{flow.id}']") |> render_click()

    assert {path, _flash} = assert_redirect(view)
    assert path =~ ~r|^/demo/pet-licenses/applications/[0-9a-f-]{36}$|
  end

  describe "where each journey stands" do
    test "the badge says whose turn it is, from the cache", %{conn: conn} do
      %{journey: yours} = licensing("Dog License")
      %{journey: theirs, intake: intake} = licensing("Cat License")
      complete(theirs, intake)
      %{journey: done} = licensing("Fish License")
      {:ok, _done} = Instances.Flows.complete(done)

      {:ok, view, _html} = live(conn, "/demo/pet-licenses/applications")

      assert has_element?(view, row_badge(yours), "Your turn")
      assert has_element?(view, row_badge(theirs), "Waiting on others")
      assert has_element?(view, row_badge(done), "Completed")
    end

    test "Next names the first open position and Flow progress counts the whole flow",
         %{conn: conn} do
      %{journey: journey, intake: intake} = licensing("Dog License")

      {:ok, view, _html} = live(conn, "/demo/pet-licenses/applications")

      assert has_element?(view, row(journey), "Application / Intake")
      assert has_element?(view, row(journey), "0 of 2")

      complete(journey, intake)

      {:ok, view, _html} = live(conn, "/demo/pet-licenses/applications")

      assert has_element?(view, row(journey), "Review / Review")
      assert has_element?(view, row(journey), "1 of 2")
    end

    test "Continue goes straight to the next position's Edit page when it is the viewer's",
         %{conn: conn} do
      %{journey: journey, intake: intake} = licensing("Dog License")

      {:ok, view, _html} = live(conn, "/demo/pet-licenses/applications")

      # Edit, not View: nobody has started this position yet, and View
      # there would only say so
      assert has_element?(
               view,
               "a[href='/demo/pet-licenses/applications/#{journey.id}/forms/#{Enum.join(intake, "/")}/edit']",
               "Continue"
             )

      # Once the next position is the reviewer's, Continue goes to the journey
      complete(journey, intake)

      {:ok, view, _html} = live(conn, "/demo/pet-licenses/applications")

      assert has_element?(view, row_link(journey), "Continue")
    end
  end

  describe "a user who works other people's journeys" do
    @describetag user: "reviewer"

    test "lists only the journeys open at one of their forms", %{conn: conn} do
      # Fresh: the applicant's turn. Submitted: the reviewer's. Reviewed: the
      # applicant's again, for the closing feedback.
      %{journey: fresh, root: root, intake: intake} = licensing("Dog License")
      submitted = another_journey(root)
      complete(submitted, intake)
      %{journey: reviewed, intake: intake, review: review} = licensing("Cat License")
      complete(reviewed, intake)
      complete(reviewed, review)

      {:ok, view, html} = live(conn, "/demo/pet-licenses/reviews")

      assert has_element?(view, @table)
      assert html =~ submitted.id
      assert has_element?(view, "a[href='/demo/pet-licenses/reviews/#{submitted.id}']")
      refute html =~ fresh.id
      refute html =~ reviewed.id

      # And the one listed is theirs to act on
      assert has_element?(view, row_badge(submitted, "reviews"), "Your turn")
    end

    test "a journey of a flow with nothing for them is not listed, where the applicant sees it",
         %{conn: conn} do
      # No reviewer step at all: the flow is never open at a reviewer's form
      theirs = start_flow("Dog License", "dog_owner")

      {:ok, view, html} = live(conn, "/demo/pet-licenses/reviews")

      refute has_element?(view, @table)
      refute html =~ theirs.id
      assert html =~ "Nothing is waiting for you."
    end

    test "an empty queue says nothing is waiting, not that nothing started",
         %{conn: conn} do
      {:ok, view, html} = live(conn, "/demo/pet-licenses/reviews")

      refute has_element?(view, @table)
      assert html =~ "Nothing is waiting for you."
      refute html =~ "Nothing started yet"
    end
  end

  defp row_link(instance), do: "a[href='/demo/pet-licenses/applications/#{instance.id}']"

  # A row, found through the link every row carries
  defp row(instance), do: "tr:has(#{row_link(instance)})"

  defp row_badge(instance, section \\ "applications"),
    do: "tr:has(a[href='/demo/pet-licenses/#{section}/#{instance.id}']) span"

  defp start_flow(name, user_id) do
    {:ok, flow} = Flows.create(%{name: name, status: "open"})
    {:ok, instance} = Instances.Flows.create(%{template_flow_id: flow.id, user_id: user_id})

    instance
  end

  # Start → Application (for applicants: Intake) → Review (for reviewers:
  # Review) → End, named `name` so the reviews page's `flows` finds it by
  # slug, and a journey of it started by the dog owner
  defp licensing(name) do
    {:ok, root} = Flows.create(%{name: name, label: "subflows", status: "open"})

    application = owned_forms_flow(root, "Application", ["applicant"], "Intake")
    review = owned_forms_flow(root, "Review", ["reviewer"], "Review")

    first_node = build_node(root, ["Start"], "Start")

    application_node =
      build_node(root, ["Subflow"], "Application", %{subflow_id: application.flow.id})

    review_node = build_node(root, ["Subflow"], "Review", %{subflow_id: review.flow.id})
    last_node = build_node(root, ["End"], "End")

    edge(root, first_node, application_node)
    edge(root, application_node, review_node)
    edge(root, review_node, last_node)

    %{
      root: root,
      journey: another_journey(root),
      intake: [application_node.id, application.form.id],
      review: [review_node.id, review.form.id]
    }
  end

  defp another_journey(root) do
    {:ok, journey} = Instances.Flows.create(%{template_flow_id: root.id, user_id: "dog_owner"})

    journey
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

  # Starts and submits the form at `path`
  defp complete(journey, path) do
    {:ok, _opened} = Instances.Forms.update_status(journey, path, :in_progress)
    {:ok, completed} = Instances.Forms.update_status(journey, path, :completed, data: %{})

    completed
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

  # A published form with one text question, "name"
  defp build_form_node(flow, label) do
    {:ok, form} = Forms.create(%{name: "#{label} #{System.unique_integer([:positive])}"})
    [draft] = form.versions

    definition = %{"elements" => [%{"type" => "text", "name" => "name", "title" => "Name"}]}
    {:ok, draft} = Forms.update_draft(draft, %{definition: definition})
    {:ok, _published} = Forms.update_status(draft, :published)

    build_node(flow, ["Form"], label, %{form_id: form.id})
  end

  # Whether the rows appear in the order listed. Ids reach the page through
  # each row's link, so their positions are the row order.
  defp row_order(html, instances) do
    positions =
      for instance <- instances do
        case :binary.match(html, instance.id) do
          {position, _length} -> position
          :nomatch -> flunk("no row rendered for #{instance.id}")
        end
      end

    if positions == Enum.sort(positions), do: :in_order, else: :out_of_order
  end

  defp rows_on_page(html, instances) do
    Enum.count(instances, &String.contains?(html, &1.id))
  end
end
