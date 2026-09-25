defmodule Demo.FormFlowNextPositionsPagesTest do
  @moduledoc """
  The pages' side of the next-position cache
  (`archive/plans/next-position.md` §5.4): the flow editor sweeps every
  open journey after a save that changed the flow's structure and after no
  other, the flow instance's page repairs a stale row when it is opened,
  and the listing marks a row a sweep has not reached.
  """

  use DemoWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias FormFlow.Data.Instances
  alias FormFlow.Data.Instances.Flow.NextPosition
  alias FormFlow.Data.Repo, as: FormFlowRepo
  alias FormFlow.Data.Templates.Flow
  alias FormFlow.Data.Templates.Flows
  alias FormFlow.Data.Templates.Forms

  describe "the editor's save" do
    @describetag user: "admin"

    test "sweeps the open journeys after a structural save, and not after a rename",
         %{conn: conn} do
      %{flow: flow, journey: journey, forms: [name, address]} = flow_of_two()
      flow = Flows.get(flow.id)
      start = Enum.find(flow.nodes, &("Start" in &1.labels))
      stop = Enum.find(flow.nodes, &("End" in &1.labels))
      computed_at = journey.next_computed_at

      {:ok, view, _html} = live(conn, "/demo/admin/flows/#{flow.id}/edit")

      # A rename: the same steps and edges, a new name
      view
      |> element("#flows-edit-editor")
      |> render_hook("form_flow:flow_changed", canvas(flow, [start, name, address, stop]))

      view
      |> element("#flows-edit-flow-form-form")
      |> render_change(%{"dynamic_form" => %{"name" => "Renamed"}})

      view |> element("button", "Save") |> render_click()
      assert render(view) =~ "Saved."

      assert reload(journey).next_computed_at == computed_at

      # A structural save: Address is removed. With a journey in flight this
      # asks first (`Demo.FormFlowFlowSaveConfirmationTest`), so the sweep
      # runs on "Save anyway"
      view
      |> element("#flows-edit-editor")
      |> render_hook("form_flow:flow_changed", canvas(flow, [start, name, stop]))

      view |> element("button", "Save") |> render_click()
      assert render(view) =~ "Save anyway"

      view |> element("button", "Save anyway") |> render_click()
      assert render(view) =~ "Saved."

      swept = reload(journey)
      assert DateTime.compare(swept.next_computed_at, computed_at) == :gt
      assert swept.forms_total == 1
      assert swept.next_path == [name.id]
    end
  end

  describe "the flow instance's page" do
    @describetag user: "dog_owner"

    test "repairs a row no refresh has reached, and one older than the flow's last save",
         %{conn: conn} do
      %{flow: flow, journey: journey, forms: [name, _address]} = flow_of_two()

      # Never refreshed
      FormFlowRepo.update_all(from(i in Instances.Flow, where: i.id == ^journey.id),
        set: [next_path: nil, next_node_id: nil, next_computed_at: nil]
      )

      FormFlowRepo.delete_all(from(p in NextPosition, where: p.instance_flow_id == ^journey.id))

      {:ok, _view, _html} = live(conn, "/demo/pet-licenses/applications/#{journey.id}")

      repaired = reload(journey)
      assert repaired.next_path == [name.id]
      assert %DateTime{} = repaired.next_computed_at
      assert [_row] = rows_of(journey)

      # Refreshed before the flow was last saved: the cached value is wrong
      # and the timestamps say so
      FormFlowRepo.update_all(from(i in Instances.Flow, where: i.id == ^journey.id),
        set: [next_path: ["gone"], next_node_id: "gone"]
      )

      # Saved a moment after the refresh - in the past, so the repair that
      # follows is newer than it
      later = DateTime.add(repaired.next_computed_at, 1, :millisecond)
      FormFlowRepo.update_all(from(f in Flow, where: f.id == ^flow.id), set: [updated_at: later])

      {:ok, _view, _html} = live(conn, "/demo/pet-licenses/applications/#{journey.id}")

      assert reload(journey).next_path == [name.id]

      # A fresh row is left alone
      fresh = reload(journey)
      {:ok, _view, _html} = live(conn, "/demo/pet-licenses/applications/#{journey.id}")
      assert reload(journey).next_computed_at == fresh.next_computed_at
    end
  end

  describe "a completed journey's page" do
    @describetag user: "dog_owner"

    test "says Completed, offers nothing to continue, and still lists the forms",
         %{conn: conn} do
      %{journey: journey, forms: [name, address]} = flow_of_two()

      submit(journey, [name.id])
      submit(journey, [address.id])
      assert reload(journey).status == "completed"

      {:ok, _view, html} = live(conn, "/demo/pet-licenses/applications/#{journey.id}")

      assert html =~ "Completed"
      assert html =~ "2 of 2 forms done"
      # Both rows are still there to read back
      assert html =~ "Name"
      assert html =~ "Address"
      # Nothing to pick up: no next-up line, no Continue or Start
      refute html =~ "nothing for you right now"
      refute html =~ ">Continue<"
      refute html =~ ">Start<"
    end

    test "counts the forms it had when it completed, not the ones added since",
         %{conn: conn} do
      %{flow: flow, journey: journey, forms: [name, address]} = flow_of_two()

      submit(journey, [name.id])
      submit(journey, [address.id])

      # A step added to the template after this journey finished. It is not
      # this journey's to answer, so the page must not count it or list it.
      extra = build_form_node(flow, "Extra")
      edge(flow, address, extra)

      {:ok, _view, html} = live(conn, "/demo/pet-licenses/applications/#{journey.id}")

      assert html =~ "2 of 2 forms done"
      refute html =~ "3 forms"
      refute html =~ "Extra"
    end

    test "a journey completed with no snapshot renders live rather than renders nothing",
         %{conn: conn} do
      %{journey: journey, forms: [name, address]} = flow_of_two()

      submit(journey, [name.id])
      submit(journey, [address.id])

      # As every journey completed before the snapshot column existed
      FormFlowRepo.update_all(from(i in Instances.Flow, where: i.id == ^journey.id),
        set: [completed_template_snapshot: nil]
      )

      {:ok, _view, html} = live(conn, "/demo/pet-licenses/applications/#{journey.id}")

      assert html =~ "2 of 2 forms done"
      assert html =~ "Name"
      assert html =~ "Address"
    end
  end

  describe "the listing" do
    @describetag user: "dog_owner"

    test "marks a row the flow was edited after, quietly, and not a fresh one", %{conn: conn} do
      %{flow: flow, journey: journey} = flow_of_two()

      {:ok, _view, html} = live(conn, "/demo/pet-licenses/applications")
      refute html =~ "may have changed"

      later = DateTime.add(journey.next_computed_at, 60, :second)
      FormFlowRepo.update_all(from(f in Flow, where: f.id == ^flow.id), set: [updated_at: later])

      {:ok, _view, html} = live(conn, "/demo/pet-licenses/applications")
      assert html =~ "may have changed"
    end

    test "opening a completed journey does not recount it against the flow as it is now",
         %{conn: conn} do
      %{flow: flow, journey: journey, forms: [name, address]} = flow_of_two()

      submit(journey, [name.id])
      submit(journey, [address.id])
      assert reload(journey).forms_total == 2

      # A step added to the template after this journey finished, and the
      # flow saved - which is what makes the cache look stale to a reader
      extra = build_form_node(flow, "Extra")
      edge(flow, address, extra)
      later = DateTime.add(reload(journey).next_computed_at, 60, :second)
      FormFlowRepo.update_all(from(f in Flow, where: f.id == ^flow.id), set: [updated_at: later])

      # Reading back a finished application is exactly what used to trigger
      # the read-repair, rewriting its final 2 of 2 into 2 of 3
      {:ok, _view, _html} = live(conn, "/demo/pet-licenses/applications/#{journey.id}")

      after_viewing = reload(journey)
      assert after_viewing.completed_forms == 2
      assert after_viewing.forms_total == 2

      # And the listing still says so
      {:ok, _view, html} = live(conn, "/demo/pet-licenses/applications")
      assert html =~ "2 of 2"
      refute html =~ "2 of 3"
    end

    test "never marks a completed journey - its cache is final, not behind", %{conn: conn} do
      %{flow: flow, journey: journey, forms: [name, address]} = flow_of_two()

      submit(journey, [name.id])
      submit(journey, [address.id])
      journey = reload(journey)
      assert journey.status == "completed"

      # The same flow edit that marks a journey still in progress
      later = DateTime.add(journey.next_computed_at, 60, :second)
      FormFlowRepo.update_all(from(f in Flow, where: f.id == ^flow.id), set: [updated_at: later])

      {:ok, _view, html} = live(conn, "/demo/pet-licenses/applications")
      refute html =~ "may have changed"
    end
  end

  # ── fixtures ────────────────────────────────────────────────────────────

  # The canvas as the hook reports it, kept to these nodes and wired in
  # their order: what the editor loaded (`ReactFlow.to_data/1`), with the
  # dropped steps and every edge gone, and the kept ones joined up again
  defp canvas(flow, nodes) do
    kept = MapSet.new(nodes, & &1.id)
    data = FormFlow.Web.Helpers.ReactFlow.to_data(Flows.get(flow.id))

    %{
      "nodes" => Enum.filter(data.nodes, &MapSet.member?(kept, &1["id"])),
      "edges" =>
        nodes
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.map(fn [a, b] ->
          %{"id" => "#{a.id}-#{b.id}", "source" => a.id, "target" => b.id}
        end)
    }
  end

  defp submit(journey, path) do
    {:ok, _started} = Instances.Forms.update_status(journey, path, :in_progress)
    {:ok, done} = Instances.Forms.update_status(journey, path, :completed, data: %{})
    done
  end

  # Start → Name → Address → End, open, and a journey of it
  defp flow_of_two do
    {:ok, flow} =
      Flows.create(%{flow_group: "pet-licensing", name: "Dog License", status: "open"})

    first_node = build_node(flow, ["Start"], "Start")
    name = build_form_node(flow, "Name")
    address = build_form_node(flow, "Address")
    last_node = build_node(flow, ["End"], "End")

    edge(flow, first_node, name)
    edge(flow, name, address)
    edge(flow, address, last_node)

    {:ok, journey} = Instances.Flows.create(%{template_flow_id: flow.id, user_id: "dog_owner"})

    %{flow: flow, journey: journey, forms: [name, address]}
  end

  defp reload(journey), do: Instances.Flows.get(journey.id)

  defp rows_of(journey),
    do: FormFlowRepo.all(from(p in NextPosition, where: p.instance_flow_id == ^journey.id))

  # `kind` rides in the data as the editor puts it there: a canvas save
  # derives a node's labels from it (`FormFlow.Data.Templates.Flow.Node`)
  defp build_node(flow, [kind] = labels, label, attrs \\ %{}) do
    data = %{"label" => label, "kind" => String.downcase(kind)}

    attrs =
      Map.merge(
        %{flow_id: flow.id, labels: labels, properties: %{"data" => data}},
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

  # A published form with one text question, "name", owned by the flow so
  # the canvas save keeps it as the step's own
  defp build_form_node(flow, label) do
    {:ok, form} =
      Forms.create(%{
        name: "#{label} #{System.unique_integer([:positive])}",
        owner_flow_id: flow.id
      })

    [draft] = form.versions

    definition = %{"elements" => [%{"type" => "text", "name" => "name", "title" => "Name"}]}
    {:ok, draft} = Forms.update_draft(draft, %{definition: definition})
    {:ok, _published} = Forms.update_status(draft, :published)

    build_node(flow, ["Form"], label, %{form_id: form.id})
  end
end
