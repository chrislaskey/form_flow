defmodule Demo.FormFlowJourneysTest do
  @moduledoc """
  Drives the user-facing journey pages end-to-end through the dedicated
  `live "/users/*path", FormFlowLive.Users` route (mounted with
  `base="/users"`): starting a journey from the index, opening a form
  (create-on-open, which pins the published version), submitting it,
  viewing it completed, and reopening it.
  """

  use DemoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias FormFlow.Data.Instances
  alias FormFlow.Data.Templates.Flows
  alias FormFlow.Data.Templates.Forms

  @definition %{
    "title" => "Enrollment",
    "elements" => [
      %{"type" => "text", "name" => "full_name", "title" => "Full name"}
    ]
  }

  test "a journey end to end: start, open, submit, view completed, reopen", %{conn: conn} do
    flow = journey_ready_flow()

    # Start a journey from the index
    {:ok, view, _html} = live(conn, "/users/journeys")

    {:error, {:live_redirect, %{to: journey_path}}} =
      view
      |> element(~s(button[phx-value-flow-id="#{flow.id}"]), "Start")
      |> render_click()

    [_, journey_id] = Regex.run(~r|/users/journeys/([^/]+)$|, journey_path)

    # The journey page offers the form as Available; opening creates the
    # instance and navigates to it
    {:ok, view, html} = live(conn, journey_path)
    assert html =~ "Available"

    {:error, {:live_redirect, %{to: instance_path}}} =
      view |> element("button", "Open") |> render_click()

    [_, instance_id] = Regex.run(~r|/instances/([^/]+)$|, instance_path)

    {:ok, view, html} = live(conn, instance_path)
    assert html =~ "Full name"

    # Submit: answers land, the instance completes, and — with no further
    # positions in this flow — the user is sent back to the journey page
    view
    |> form(
      ~s(#instance-forms-show-#{instance_id}-in_progress-form),
      %{"dynamic_form" => %{"full_name" => "Maria"}}
    )
    |> render_submit()

    assert_redirect(view, journey_path)

    journey = Instances.Flows.get(journey_id)
    assert [instance] = Instances.Flows.form_instances(journey)
    assert instance.status == "completed"
    assert instance.data["full_name"] == "Maria"

    # The journey page shows Done, and the completed view renders read-only
    # instead of crashing (regression: DynamicForm's render_only is a
    # parent-owned-form mode, not a read-only display)
    {:ok, _view, html} = live(conn, journey_path)
    assert html =~ "Done"

    {:ok, view, html} = live(conn, instance_path)
    assert html =~ "Submitted"
    assert has_element?(view, "fieldset[disabled]")
    refute has_element?(view, "button", "Submit")

    # Reopen brings the form back to editable, answers kept
    view |> element("button", "Reopen") |> render_click()
    assert has_element?(view, "button", "Submit")
    refute has_element?(view, "fieldset[disabled]")
    assert Instances.Forms.get(instance_id).status == "in_progress"
  end

  defp journey_ready_flow do
    {:ok, form} = Forms.create(%{name: "Enrollment #{System.unique_integer([:positive])}"})
    [draft] = form.versions
    {:ok, draft} = Forms.update_draft(draft, %{definition: @definition})
    {:ok, _v1} = Forms.update_status(draft, :published)

    start_id = Ecto.UUID.generate()
    form_node_id = Ecto.UUID.generate()
    end_id = Ecto.UUID.generate()

    {:ok, flow} =
      Flows.create(%{
        name: "Licensing application",
        label: "forms",
        nodes: [
          step(start_id, "Start", "start"),
          step(form_node_id, "Enrollment", "form") |> Map.put(:form_id, form.id),
          step(end_id, "End", "end")
        ],
        relationships: [
          %{source_id: start_id, target_id: form_node_id, label: "TRANSITIONS_TO"},
          %{source_id: form_node_id, target_id: end_id, label: "TRANSITIONS_TO"}
        ]
      })

    flow
  end

  defp step(id, label, kind) do
    %{
      id: id,
      labels: [],
      properties: %{
        "type" => "step",
        "position" => %{"x" => 0, "y" => 0},
        "data" => %{"label" => label, "kind" => kind}
      }
    }
  end
end
