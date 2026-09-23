defmodule Demo.FormFlowHealthTest do
  @moduledoc """
  `FormFlow.Data.Templates.Flows.Health`'s writes against a real database:
  the status cached on the root flow under `_health_metadata`, refreshed
  after a save and read back off the struct with no query, and the ignored
  records beside it. The checks themselves are proven on hand-built trees in
  the library's own suite.
  """

  use Demo.DataCase, async: false

  alias FormFlow.Config.Property
  alias FormFlow.Data.Templates.Flows
  alias FormFlow.Data.Templates.Flows.Health
  alias FormFlow.Data.Templates.Forms

  # Start and End, unwired: an error (Start does not reach End) and a warning
  # (End is not connected)
  defp starter_flow(name \\ "Enrollment") do
    {:ok, flow} =
      Flows.create(%{name: name, label: "forms", nodes: Flows.starter_nodes(), relationships: []})

    Flows.get(flow.id)
  end

  defp wire(flow) do
    start = Enum.find(flow.nodes, &("Start" in &1.labels))
    stop = Enum.find(flow.nodes, &("End" in &1.labels))

    {:ok, _flow} =
      Flows.update(flow, %{
        nodes: Enum.map(flow.nodes, &%{id: &1.id, properties: &1.properties}),
        relationships: [%{source_id: start.id, target_id: stop.id, label: "CONNECTS_TO"}]
      })

    Flows.get(flow.id)
  end

  test "a flow never checked has no status; refresh caches the report on the root" do
    flow = starter_flow()
    assert Health.status(flow) == nil

    assert %Health{level: :error, checks_run: run} = Health.refresh(flow.id)

    flow = Flows.get(flow.id)
    status = Health.status(flow)

    assert status.level == :error
    assert status.counts == %{error: 1, warning: 1, info: 0, ignored: 0}
    assert status.checks_run == run
    assert status.summary.label == "forms"
    assert status.summary.steps == 0
    assert %DateTime{} = status.checked_at

    # One key, strings throughout — the flow's own open map, as the type and
    # perspectives already are
    assert %{
             "status" => %{
               "level" => "error",
               "counts" => %{"error" => 1, "warning" => 1, "info" => 0, "ignored" => 0},
               "summary" => %{"label" => "forms"},
               "checks_run" => ^run,
               "checked_at" => <<_::binary>>
             }
           } = flow.properties["_health_metadata"]

    # Another save, another refresh: the status follows the flow
    flow |> wire() |> Health.refresh()

    assert %{level: :warning, counts: %{error: 0, warning: 1}} = Health.status(Flows.get(flow.id))
  end

  test "a save from a stale copy of the properties keeps the ignored records" do
    flow = starter_flow()
    stale = Flows.get(flow.id)

    health = Health.refresh(flow.id)
    [unconnected] = Health.at(health, :warning)
    {:ok, _root} = Health.ignore(health, unconnected, "demo-admin")

    # An identity save from a page loaded before the ignore: its map has no
    # bookkeeping, and must not take the stored bookkeeping with it
    {:ok, saved} =
      Flows.update(stale, %{properties: Map.put(stale.properties, "flow_type", "default")})

    assert saved.properties["flow_type"] == "default"

    assert [%{"code" => "unconnected"}] =
             saved.properties["_health_metadata"]["ignored_entries"]

    # And a caller cannot set bookkeeping of its own through a save
    {:ok, saved} =
      Flows.update(saved, %{properties: %{"_health_metadata" => %{}, "_mine" => true}})

    assert [%{"code" => "unconnected"}] =
             saved.properties["_health_metadata"]["ignored_entries"]

    refute Map.has_key?(saved.properties, "_mine")
  end

  test "a check does not move the flow's updated_at" do
    flow = starter_flow()
    Health.refresh(flow.id)
    before = Flows.get(flow.id)

    Process.sleep(1_100)
    health = Health.refresh(flow.id)
    [unconnected] = Health.at(health, :warning)
    {:ok, _root} = Health.ignore(health, unconnected, nil)

    after_checks = Flows.get(flow.id)
    assert after_checks.updated_at == before.updated_at
    assert after_checks.properties["_health_metadata"] != before.properties["_health_metadata"]
  end

  test "a flow deleted under a report refuses the toggle and the refresh, without raising" do
    flow = starter_flow()
    health = Health.refresh(flow.id)
    [unconnected] = Health.at(health, :warning)

    {:ok, _flow} = Flows.delete(Flows.get(flow.id))

    assert Health.ignore(health, unconnected, "demo-admin") == {:error, :not_found}
    assert Health.stop_ignoring(health, unconnected, "demo-admin") == {:error, :not_found}
    assert Health.refresh(flow.id) == nil
  end

  test "refresh writes only its own key, leaving the admin's beside it" do
    flow = starter_flow()

    {:ok, flow} =
      Flows.update(flow, %{properties: Map.put(flow.properties, "flow_type", "default")})

    Health.refresh(flow.id)

    properties = Flows.get(flow.id).properties
    assert properties["flow_type"] == "default"
    assert properties["slug"] == flow.slug
    assert Map.has_key?(properties, "_health_metadata")
  end

  test "refresh on an owned subflow refreshes its root; a subflow never carries health" do
    {:ok, root} =
      Flows.create(%{
        name: "Licensing",
        label: "subflows",
        nodes: [
          %{
            properties: %{
              "type" => "subflow",
              "data" => %{"label" => "Review", "subflow_label" => "forms"}
            }
          }
        ]
      })

    [node] = Flows.get(root.id).nodes
    subflow = Flows.get(node.subflow_id)
    assert subflow.owner_flow_id == root.id

    assert %Health{flow_id: flow_id} = Health.refresh(subflow)
    assert flow_id == root.id

    assert Health.status(Flows.get(root.id)) != nil
    assert Health.status(Flows.get(subflow.id)) == nil
    refute Map.has_key?(Flows.get(subflow.id).properties, "_health_metadata")

    # A check by the subflow's id is the root's check too, so what is ignored
    # from it — the record and the event — lands on the root
    health = Health.check(subflow.id)
    assert health.flow_id == root.id
    [entry | _rest] = health.entries

    {:ok, written} = Health.ignore(health, entry, "demo-admin")
    assert written.id == root.id
    refute Map.has_key?(Flows.get(subflow.id).properties, "_health_metadata")
    assert [%{event: "health_ignored"} | _older] = Flows.list_events(Flows.get(root.id))
    assert Flows.list_events(Flows.get(subflow.id)) == []
  end

  test "ignoring and stopping are logged on the flow, with who decided and what" do
    flow = starter_flow()
    health = Health.refresh(flow.id)
    [unconnected] = Health.at(health, :warning)

    {:ok, _root} = Health.ignore(health, unconnected, "demo-admin")
    {:ok, _root} = Health.stop_ignoring(Health.check(flow.id), unconnected, "other-admin")

    assert [
             %{event: "created"},
             %{event: "health_ignored", user_id: "demo-admin", snapshot: ignored},
             %{event: "health_unignored", user_id: "other-admin", snapshot: unignored}
           ] = flow |> Flows.list_events() |> Enum.reverse()

    assert %{"code" => "unconnected", "path" => [_end_id], "subject" => "End"} = ignored
    assert unignored["code"] == "unconnected"
  end

  test "ignoring writes the status too, and refresh drops a record whose entry is gone" do
    flow = starter_flow()
    health = Health.refresh(flow.id)
    [unconnected] = Health.at(health, :warning)

    {:ok, root} = Health.ignore(health, unconnected, "demo-admin")

    assert %{level: :error, counts: %{error: 1, warning: 0, info: 0, ignored: 1}} =
             Health.status(root)

    assert [%{"code" => "unconnected", "user_id" => "demo-admin", "path" => [_end_id]}] =
             root.properties["_health_metadata"]["ignored_entries"]

    # The next check reads the mark
    assert [%{code: :unconnected, ignored: %{user_id: "demo-admin"}}] =
             Health.ignored(Health.check(flow.id))

    # Wiring End in removes the entry; the refresh after that save removes
    # the record, and the status counts nothing as ignored
    flow |> wire() |> Health.refresh()

    root = Flows.get(flow.id)
    refute Map.has_key?(root.properties["_health_metadata"], "ignored_entries")
    assert %{level: :warning, counts: %{ignored: 0}} = Health.status(root)

    # Stop ignoring writes the status as well
    health = Health.refresh(flow.id)
    [no_steps] = health.entries
    {:ok, root} = Health.ignore(health, no_steps, nil)
    assert %{level: :ok, counts: %{ignored: 1}} = Health.status(root)

    {:ok, root} = Health.stop_ignoring(Health.check(flow.id), no_steps, "demo-admin")
    assert %{level: :warning, counts: %{warning: 1, ignored: 0}} = Health.status(root)
    refute Map.has_key?(root.properties["_health_metadata"], "ignored_entries")
  end

  test "refresh_for_form refreshes every root with a step on the form" do
    {:ok, catalog} = Forms.create(%{name: "Owner contact"})
    dog = flow_with_catalog_form_node("Dog License", catalog)
    cat = flow_with_catalog_form_node("Cat License", catalog)
    other = starter_flow("Unrelated")

    Health.refresh_for_form(catalog.id)

    # The form is a draft, so both flows using it report it unpublished
    assert %{counts: %{error: error}} = Health.status(Flows.get(dog.id))
    assert error >= 1
    assert %{counts: %{error: ^error}} = Health.status(Flows.get(cat.id))
    assert Health.status(Flows.get(other.id)) == nil

    [draft] = Forms.list_versions(catalog.id)
    {:ok, _v1} = Forms.update_status(draft, :published)
    Health.refresh_for_form(catalog.id)

    assert %{counts: %{error: after_publish}} = Health.status(Flows.get(dog.id))
    assert after_publish == error - 1
  end

  describe "a pointer into another flow, looked up for real" do
    test "a position the named flow has, and a Start reaches, raises nothing" do
      last_year = flow_of_one_form("Dog License 2026")
      this_year = prefilling_flow(position(last_year))

      assert Enum.all?(
               Health.check(this_year.flow.id, host_types()).entries,
               &(&1.code != :related_form_in_any_flow_missing)
             )
    end

    test "a flow that is gone is reported, and the message says so" do
      last_year = flow_of_one_form("Dog License 2026")
      this_year = prefilling_flow(position(last_year))

      {:ok, _deleted} = Flows.delete(Flows.get(last_year.flow.id))

      assert [entry] = pointer_entries(this_year)
      assert entry.level == :error
      assert entry.message =~ "at a flow that no longer exists"
    end

    test "a position the named flow no longer has is reported" do
      last_year = flow_of_one_form("Dog License 2026")

      this_year =
        prefilling_flow(Property.flow_position(last_year.flow.id, [Ecto.UUID.generate()]))

      assert [entry] = pointer_entries(this_year)
      assert entry.message =~ "no longer has"
    end

    defp pointer_entries(%{flow: flow}) do
      flow.id
      |> Health.check(host_types())
      |> Map.fetch!(:entries)
      |> Enum.filter(&(&1.code == :related_form_in_any_flow_missing))
    end

    defp position(%{flow: flow, form_node: node}),
      do: Property.flow_position(flow.id, [node.id])

    # Start → one form step → End, so the step is connected and its type's
    # properties are checked
    defp flow_of_one_form(name) do
      {:ok, flow} = Flows.create(%{name: name, label: "forms", nodes: Flows.starter_nodes()})
      flow = Flows.get(flow.id)

      {:ok, _} =
        Flows.update(flow, %{
          nodes:
            node_attrs(flow.nodes) ++
              [
                %{
                  properties: %{
                    "type" => "step",
                    "data" => %{"label" => "Owner", "kind" => "form"}
                  }
                }
              ]
        })

      flow = Flows.get(flow.id)
      owner = Enum.find(flow.nodes, & &1.form_id)
      start = Enum.find(flow.nodes, &("Start" in &1.labels))
      stop = Enum.find(flow.nodes, &("End" in &1.labels))

      {:ok, _} =
        Flows.update(flow, %{
          nodes: node_attrs(flow.nodes),
          relationships: [
            %{source_id: start.id, target_id: owner.id, label: "CONNECTS_TO"},
            %{source_id: owner.id, target_id: stop.id, label: "CONNECTS_TO"}
          ]
        })

      %{flow: Flows.get(flow.id), form_node: owner}
    end

    # The same flow, with its one form set to prefill from `value`
    defp prefilling_flow(value) do
      built = flow_of_one_form("Dog License 2027")

      {:ok, _} =
        Forms.update(Forms.get(built.form_node.form_id), %{
          properties: %{
            "form_type" => "default",
            "form_type_property_values" => %{"prefill_with_answers_from" => value}
          }
        })

      built
    end

    # Nodes as a save re-sends them: the form a step already points at rides
    # in the properties, which is where a save reads it from
    defp node_attrs(nodes) do
      for node <- nodes do
        properties =
          if node.form_id,
            do: Map.put(node.properties, "form_id", node.form_id),
            else: node.properties

        %{id: node.id, labels: node.labels, properties: properties}
      end
    end
  end

  test "a copy carries the source's ignores re-pointed, and is checked as it is made" do
    flow = starter_flow()
    health = Health.refresh(flow.id)
    [unconnected] = Health.at(health, :warning)
    {:ok, _root} = Health.ignore(health, unconnected, "demo-admin")

    # The source's own status describes a check the copy has not had, so it
    # does not come along; the copy is checked with the types the caller had
    # to pass. The ignore comes along, naming the copied node.
    {:ok, copy} = Flows.copy(Flows.get(flow.id), host_types())
    assert copy.properties["slug"] == copy.slug

    assert [record] = copy.properties["_health_metadata"]["ignored_entries"]
    assert record["code"] == "unconnected"
    assert record["user_id"] == "demo-admin"
    [copied_node_id] = record["path"]
    assert copied_node_id != hd(unconnected.path)
    assert Enum.any?(copy.nodes, &(&1.id == copied_node_id))

    # Checked, the copy counts the ignore as the source did
    assert %{level: :error, counts: %{error: 1, warning: 0, ignored: 1}} = Health.status(copy)

    # The source keeps its own
    assert %{counts: %{ignored: 1}} = Health.status(Flows.get(flow.id))
  end

  test "a copy refuses to run without both of the host's type lists" do
    flow = starter_flow()

    assert_raise ArgumentError, ~r/needs both flow_types: and form_types:/, fn ->
      Flows.copy(Flows.get(flow.id))
    end

    assert_raise ArgumentError, fn ->
      Flows.copy(Flows.get(flow.id), form_types: FormFlow.Config.Forms.Type.defaults())
    end
  end

  # A root flow with one step on the catalog form, wired from Start to End
  defp flow_with_catalog_form_node(flow_name, catalog) do
    {:ok, flow} = Flows.create(%{name: flow_name, nodes: Flows.starter_nodes()})
    flow = Flows.get(flow.id)
    start = Enum.find(flow.nodes, &("Start" in &1.labels))
    stop = Enum.find(flow.nodes, &("End" in &1.labels))
    step_id = Ecto.UUID.generate()

    {:ok, _flow} =
      Flows.update(flow, %{
        nodes:
          Enum.map(flow.nodes, &%{id: &1.id, properties: &1.properties}) ++
            [
              %{
                id: step_id,
                properties: %{
                  "type" => "step",
                  "form_id" => catalog.id,
                  "data" => %{"label" => catalog.name, "kind" => "form"}
                }
              }
            ],
        relationships: [
          %{source_id: start.id, target_id: step_id, label: "CONNECTS_TO"},
          %{source_id: step_id, target_id: stop.id, label: "CONNECTS_TO"}
        ]
      })

    Flows.get(flow.id)
  end
end
