defmodule Demo.FormFlowFlowSaveConfirmationTest do
  @moduledoc """
  The flow editor asks before any save of a flow with journeys in flight:
  leave them on the snapshot they started with (the default), or move them
  to the new snapshot and recompute where each stands
  (`FormFlow.Data.Instances.Flows.move_to_snapshot/3`). A flow nobody has
  started is the admin's to reshape freely. When the save deletes an owned
  form template, Move is the only answer offered: a journey left behind
  would still name a form that no longer exists.

  Save & Continue asks the same question, and navigates once it is
  answered.
  """

  use DemoWeb.ConnCase

  @moduletag user: "admin"

  import Phoenix.LiveViewTest

  alias FormFlow.Data.Instances
  alias FormFlow.Data.Repo, as: FormFlowRepo
  alias FormFlow.Data.Templates.Flow
  alias FormFlow.Data.Templates.Flows
  alias FormFlow.Data.Templates.Flows.Snapshots
  alias FormFlow.Data.Templates.Forms

  describe "a flow nobody has started" do
    test "a save goes straight through", %{conn: conn} do
      flow = flow_of_one()

      {:ok, view, _html} = live(conn, edit_path(flow))
      add_a_step(view, flow)

      view |> element("button", "Save") |> render_click()

      assert render(view) =~ "Saved."
      refute has_element?(view, "#flows-edit-confirm-save")
    end
  end

  describe "a flow with a journey in flight" do
    setup %{conn: conn} do
      flow = flow_of_one()
      {:ok, journey} = Instances.Flows.create(%{template_flow_id: flow.id, user_id: "u1"})

      {:ok, view, _html} = live(conn, edit_path(flow))

      %{flow: flow, journey: journey, view: view}
    end

    test "a save asks first, Leave checked, and says what each answer does", %{
      view: view,
      flow: flow
    } do
      add_a_step(view, flow)

      view |> element("button", "Save") |> render_click()

      html = render(view)

      refute html =~ "Saved."
      assert html =~ "1 flow instance still in progress."
      assert html =~ "Leave them on the snapshot they started with"
      assert html =~ "Move them to the new snapshot"
      assert has_element?(view, "#flows-edit-confirm-save-leave[checked]")
      refute has_element?(view, "#flows-edit-confirm-save-move[checked]")
      refute html =~ "This save removes a form"

      # One journey sweeps in milliseconds, so no time is quoted
      refute html =~ "Recomputing takes"
    end

    test "a rename asks too: any save is a new snapshot", %{view: view} do
      view
      |> form("#flows-edit-flow-form-form", %{"dynamic_form" => %{"name" => "A different name"}})
      |> render_change()

      view |> element("button", "Save") |> render_click()

      refute render(view) =~ "Saved."
      assert render(view) =~ "1 flow instance still in progress."
    end

    test "Keep editing leaves the flow alone", %{view: view, flow: flow} do
      add_a_step(view, flow)
      view |> element("button", "Save") |> render_click()

      view |> element("button", "Keep editing") |> render_click()

      refute has_element?(view, "#flows-edit-confirm-save")
      refute render(view) =~ "Saved."
      assert length(Flows.get(flow.id).nodes) == 3
    end

    test "Leave saves and leaves the journey on its snapshot, unswept",
         %{view: view, flow: flow, journey: journey} do
      add_a_step(view, flow)
      view |> element("button", "Save") |> render_click()

      view |> form("#flows-edit-confirm-save", %{"journeys" => "leave"}) |> render_submit()

      assert render(view) =~ "Saved."
      assert length(Flows.get(flow.id).nodes) == 4

      same = Instances.Flows.get(journey.id)
      assert same.template_flow_snapshot_id == journey.template_flow_snapshot_id
      assert same.next_computed_at == journey.next_computed_at
      assert same.forms_total == 1
      assert [_started] = Instances.Flows.list_events(same)
    end

    test "Move saves, moves the journey to the new snapshot, and sweeps it",
         %{view: view, flow: flow, journey: journey} do
      add_a_step(view, flow)
      view |> element("button", "Save") |> render_click()

      view |> form("#flows-edit-confirm-save", %{"journeys" => "move"}) |> render_submit()

      assert render(view) =~ "Saved."

      moved = Instances.Flows.get(journey.id)
      refute moved.template_flow_snapshot_id == journey.template_flow_snapshot_id
      assert Snapshots.get(moved.template_flow_snapshot_id).number == 2
      assert DateTime.compare(moved.next_computed_at, journey.next_computed_at) == :gt
      assert moved.forms_total == 2

      [_started, event] = Instances.Flows.list_events(moved) |> Enum.map(& &1.event)
      assert event.event == "moved"
      assert event.user_id == "demo-admin"
      assert event.snapshot["form_flow"] == %{"from_snapshot" => 1, "to_snapshot" => 2}
    end

    test "a save that deletes an owned form offers Move only, and moves",
         %{conn: conn, journey: journey} do
      # A flow whose one step owns its form: the step's removal deletes it
      flow = flow_with_owned_form()
      {:ok, journey} = Instances.Flows.create(%{template_flow_id: flow.id, user_id: "u2"})
      {:ok, view, _html} = live(conn, edit_path(flow))
      remove_the_form_step(view, flow)

      view |> element("button", "Save") |> render_click()

      html = render(view)
      assert html =~ "This save removes a form"
      refute has_element?(view, "#flows-edit-confirm-save-leave")
      assert has_element?(view, "#flows-edit-confirm-save-move[checked]")

      view |> form("#flows-edit-confirm-save", %{}) |> render_submit()

      assert render(view) =~ "Saved."
      moved = Instances.Flows.get(journey.id)
      refute moved.template_flow_snapshot_id == journey.template_flow_snapshot_id
      assert [_started, %{event: %{event: "moved"}}] = Instances.Flows.list_events(moved)
    end

    test "a save that removes a subflow whose steps own forms offers Move only too",
         %{conn: conn} do
      # The owned form sits on the subflow's step, not on the edited flow:
      # the collector deletes it with the subflow, and the page has to know
      %{root: root, documents_node: documents_node} = nested_flow_with_owned_form()
      {:ok, journey} = Instances.Flows.create(%{template_flow_id: root.id, user_id: "u3"})
      {:ok, view, _html} = live(conn, edit_path(root))
      remove_the_step(view, root, documents_node)

      view |> element("button", "Save") |> render_click()

      assert render(view) =~ "This save removes a form"
      refute has_element?(view, "#flows-edit-confirm-save-leave")

      view |> form("#flows-edit-confirm-save", %{}) |> render_submit()

      assert render(view) =~ "Saved."
      moved = Instances.Flows.get(journey.id)
      refute moved.template_flow_snapshot_id == journey.template_flow_snapshot_id
      assert Snapshots.tree(moved).subflows == %{}
    end

    test "Save & Continue asks the same question, then leaves", %{
      view: view,
      flow: flow,
      journey: journey
    } do
      add_a_step(view, flow)

      # Leaving with unsaved changes asks to save first
      view
      |> element("#flows-edit-editor")
      |> render_hook("navigate", %{"to" => "/demo/admin/flows/#{flow.id}"})

      assert render(view) =~ "unsaved changes"

      view |> element("button", "Save & Continue") |> render_click()

      # The first dialog gives way to the second
      html = render(view)
      refute html =~ "unsaved changes"
      assert html =~ "1 flow instance still in progress."

      view |> form("#flows-edit-confirm-save", %{"journeys" => "leave"}) |> render_submit()

      assert_redirect(view, "/demo/admin/flows/#{flow.id}")
      assert length(Flows.get(flow.id).nodes) == 4

      assert Instances.Flows.get(journey.id).template_flow_snapshot_id ==
               journey.template_flow_snapshot_id
    end

    test "Keep editing on the second dialog forgets the navigation too", %{view: view, flow: flow} do
      add_a_step(view, flow)

      view
      |> element("#flows-edit-editor")
      |> render_hook("navigate", %{"to" => "/demo/admin/flows/#{flow.id}"})

      view |> element("button", "Save & Continue") |> render_click()

      view |> element("button", "Keep editing") |> render_click()

      refute has_element?(view, "#flows-edit-confirm-save")
      refute render(view) =~ "unsaved changes"
      assert length(Flows.get(flow.id).nodes) == 3
    end
  end

  # Start → Name → End, the form published so a journey can be worked
  defp flow_of_one do
    {:ok, flow} =
      Flows.create(%{name: "Licence #{System.unique_integer([:positive])}", status: "open"})

    first_node = build_node(flow, ["Start"], "Start")
    name = build_form_node(flow, "Name")
    last_node = build_node(flow, ["End"], "End")

    edge(flow, first_node, name)
    edge(flow, name, last_node)

    Flows.get(flow.id)
  end

  # Start → Name → End, where Name's form is the flow's own - the save
  # gives a new form step one - and published so a journey can be worked
  defp flow_with_owned_form do
    {:ok, flow} =
      Flows.create(%{name: "Owned #{System.unique_integer([:positive])}", status: "open"})

    {:ok, form} = Forms.create(%{name: "Name", owner_flow_id: flow.id})
    [draft] = form.versions

    {:ok, draft} =
      Forms.update_draft(draft, %{
        definition: %{"elements" => [%{"type" => "text", "name" => "name", "title" => "Name"}]}
      })

    {:ok, _published} = Forms.update_status(draft, :published)

    first_node = build_node(flow, ["Start"], "Start")
    name = build_node(flow, ["Form"], "Name", %{form_id: form.id})
    last_node = build_node(flow, ["End"], "End")

    edge(flow, first_node, name)
    edge(flow, name, last_node)

    Flows.get(flow.id)
  end

  # Start → [Documents] → End, Documents being Start → W-2 → End with W-2
  # a form the root owns; both flows open so a journey can be worked
  defp nested_flow_with_owned_form do
    {:ok, root} =
      Flows.create(%{
        name: "Onboarding #{System.unique_integer([:positive])}",
        label: "subflows",
        status: "open"
      })

    {:ok, documents} = Flows.create(%{name: "Documents", label: "forms", owner_flow_id: root.id})

    {:ok, form} = Forms.create(%{name: "W-2", owner_flow_id: root.id})
    [draft] = form.versions

    {:ok, draft} =
      Forms.update_draft(draft, %{
        definition: %{"elements" => [%{"type" => "text", "name" => "name", "title" => "Name"}]}
      })

    {:ok, _published} = Forms.update_status(draft, :published)

    first_node = build_node(documents, ["Start"], "Start")
    w2 = build_node(documents, ["Form"], "W-2", %{form_id: form.id})
    last_node = build_node(documents, ["End"], "End")
    edge(documents, first_node, w2)
    edge(documents, w2, last_node)

    root_start = build_node(root, ["Start"], "Start")
    documents_node = build_node(root, ["Subflow"], "Documents", %{subflow_id: documents.id})
    root_end = build_node(root, ["End"], "End")
    edge(root, root_start, documents_node)
    edge(root, documents_node, root_end)

    %{root: Flows.get(root.id), documents_node: documents_node}
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

  defp build_form_node(flow, label) do
    {:ok, form} = Forms.create(%{name: "#{label} #{System.unique_integer([:positive])}"})
    [draft] = form.versions

    {:ok, draft} =
      Forms.update_draft(draft, %{
        definition: %{"elements" => [%{"type" => "text", "name" => "name", "title" => "Name"}]}
      })

    {:ok, _published} = Forms.update_status(draft, :published)

    build_node(flow, ["Form"], label, %{form_id: form.id})
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

  defp edit_path(flow), do: "/demo/admin/flows/#{flow.id}/edit"

  # A new step on the canvas, wired in after the form step: a node and an
  # edge the saved flow does not have
  defp add_a_step(view, flow) do
    nodes = Flows.get(flow.id).nodes
    form_step = Enum.find(nodes, &("Form" in &1.labels))

    view
    |> element("#flows-edit-editor")
    |> render_hook("form_flow:flow_changed", %{
      "nodes" =>
        Enum.map(nodes, &node_data(&1, 0)) ++
          [
            %{
              "id" => "new-1",
              "type" => "step",
              "position" => %{"x" => 450, "y" => 0},
              "data" => %{"label" => "Address", "kind" => "form"}
            }
          ],
      "edges" =>
        edge_data(flow) ++ [%{"id" => "new-edge", "source" => form_step.id, "target" => "new-1"}]
    })
  end

  # The canvas without its form step: Start → End
  defp remove_the_form_step(view, flow) do
    flow = Flows.get(flow.id)
    remove_the_step(view, flow, Enum.find(flow.nodes, &("Form" in &1.labels)))
  end

  # The canvas without `step`: Start → End
  defp remove_the_step(view, flow, step) do
    flow = Flows.get(flow.id)
    kept = Enum.reject(flow.nodes, &(&1.id == step.id))
    [first_node, last_node] = kept

    view
    |> element("#flows-edit-editor")
    |> render_hook("form_flow:flow_changed", %{
      "nodes" => Enum.map(kept, &node_data(&1, 0)),
      "edges" => [
        %{"id" => "new-edge", "source" => first_node.id, "target" => last_node.id}
      ]
    })
  end

  # As the canvas holds a saved node: the kind rides in `data`, and the
  # save reads the labels back off it
  defp node_data(node, y) do
    %{
      "id" => node.id,
      "type" => "step",
      "position" => %{"x" => 0, "y" => y},
      "data" => Map.put(node.properties["data"], "kind", kind(node)),
      "form_id" => node.form_id,
      "subflow_id" => node.subflow_id
    }
  end

  defp kind(%{labels: labels}) do
    cond do
      "Start" in labels -> "start"
      "End" in labels -> "end"
      true -> "form"
    end
  end

  defp edge_data(flow) do
    Enum.map(Flows.get(flow.id).relationships, fn relationship ->
      %{
        "id" => relationship.id,
        "source" => relationship.source_id,
        "target" => relationship.target_id
      }
    end)
  end
end
