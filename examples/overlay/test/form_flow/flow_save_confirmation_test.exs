defmodule Demo.FormFlowFlowSaveConfirmationTest do
  @moduledoc """
  The flow editor asks before a **structural** save of a flow with journeys
  in flight: the save moves where those journeys stand, and the sweep that
  recomputes them holds the page
  (`FormFlow.Data.Instances.Flows.update_next_positions/2`).

  Both halves have to be true for the question to be asked. A flow nobody
  has started is the admin's to reshape freely; a rename, a status, or a
  node dragged somewhere new asks nothing however many journeys are open.
  """

  use DemoWeb.ConnCase

  @moduletag user: "admin"

  import Phoenix.LiveViewTest

  alias FormFlow.Data.Instances
  alias FormFlow.Data.Repo, as: FormFlowRepo
  alias FormFlow.Data.Templates.Flow
  alias FormFlow.Data.Templates.Flows
  alias FormFlow.Data.Templates.Forms

  describe "a flow nobody has started" do
    test "a structural save goes straight through", %{conn: conn} do
      flow = flow_of_one()

      {:ok, view, _html} = live(conn, edit_path(flow))
      add_a_step(view, flow)

      view |> element("button", "Save") |> render_click()

      assert render(view) =~ "Saved."
      refute render(view) =~ "Save anyway"
    end
  end

  describe "a flow with a journey in flight" do
    setup %{conn: conn} do
      flow = flow_of_one()
      {:ok, journey} = Instances.Flows.create(%{template_flow_id: flow.id, user_id: "u1"})

      {:ok, view, _html} = live(conn, edit_path(flow))

      %{flow: flow, journey: journey, view: view}
    end

    test "a structural save asks first, and says what it will do", %{view: view, flow: flow} do
      add_a_step(view, flow)

      view |> element("button", "Save") |> render_click()

      html = render(view)

      refute html =~ "Saved."
      assert html =~ "1 flow instance still in progress."
      assert html =~ "changes the shape of the flow"
      assert html =~ "Consider copying the flow instead"
      assert html =~ "Save anyway"

      # One journey sweeps in milliseconds, so no time is quoted
      refute html =~ "this page\n            waits"
    end

    test "Keep editing leaves the flow alone", %{view: view, flow: flow} do
      add_a_step(view, flow)
      view |> element("button", "Save") |> render_click()

      view |> element("button", "Keep editing") |> render_click()

      refute render(view) =~ "Save anyway"
      refute render(view) =~ "Saved."
      assert length(Flows.get(flow.id).nodes) == 3
    end

    test "Save anyway saves and sweeps", %{view: view, flow: flow, journey: journey} do
      add_a_step(view, flow)
      view |> element("button", "Save") |> render_click()

      view |> element("button", "Save anyway") |> render_click()

      assert render(view) =~ "Saved."
      assert length(Flows.get(flow.id).nodes) == 4

      # The sweep ran: the journey's cache was rewritten against the new tree
      refreshed = Instances.Flows.get(journey.id)
      assert DateTime.compare(refreshed.next_computed_at, journey.next_computed_at) == :gt
    end

    test "a rename asks nothing", %{view: view} do
      view
      |> form("#flows-edit-flow-form-form", %{"dynamic_form" => %{"name" => "A different name"}})
      |> render_change()

      view |> element("button", "Save") |> render_click()

      assert render(view) =~ "Saved."
      refute render(view) =~ "Save anyway"
    end

    test "moving a step on the canvas asks nothing", %{view: view, flow: flow} do
      nodes = Flows.get(flow.id).nodes

      view
      |> element("#flows-edit-editor")
      |> render_hook("form_flow:flow_changed", %{
        "nodes" => Enum.map(nodes, &node_data(&1, 111)),
        "edges" => edge_data(flow)
      })

      view |> element("button", "Save") |> render_click()

      assert render(view) =~ "Saved."
      refute render(view) =~ "Save anyway"
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

  # A new step on the canvas: a node the saved flow does not have
  defp add_a_step(view, flow) do
    nodes = Flows.get(flow.id).nodes

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
      "edges" => edge_data(flow)
    })
  end

  defp node_data(node, y) do
    %{
      "id" => node.id,
      "type" => "step",
      "position" => %{"x" => 0, "y" => y},
      "data" => node.properties["data"],
      "form_id" => node.form_id,
      "subflow_id" => node.subflow_id
    }
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
