defmodule FormFlow.Data.Instances.FlowProgressTest do
  use ExUnit.Case, async: true

  alias FormFlow.Data.Instances
  alias FormFlow.Data.Instances.FlowProgress
  alias FormFlow.Data.Templates.Flow

  # ── tree-building helpers: pure structs, no database ─────────────────────

  defp build_node(labels, opts \\ []) do
    %Flow.Node{
      id: Ecto.UUID.generate(),
      labels: labels,
      form_id: Keyword.get(opts, :form_id),
      subflow_id: Keyword.get(opts, :subflow_id),
      properties: %{"data" => %{"label" => Keyword.get(opts, :label)}}
    }
  end

  defp form_node(label) do
    build_node(["Form"], form_id: Ecto.UUID.generate(), label: label)
  end

  defp edge(source, target) do
    %Flow.Relationship{
      id: Ecto.UUID.generate(),
      source_id: source.id,
      target_id: target.id,
      label: "CONNECTS_TO"
    }
  end

  defp tree(nodes, edges, subflows \\ %{}, flow \\ %Flow{}) do
    %{flow: flow, nodes: nodes, relationships: edges, subflows: subflows}
  end

  defp forms_flow(name) do
    %Flow{id: Ecto.UUID.generate(), name: name, label: "forms"}
  end

  defp form_instance(path, status, opts \\ []) do
    %Instances.Form{
      path: path,
      status: status,
      superseded_at: Keyword.get(opts, :superseded_at)
    }
  end

  defp linear_flow do
    start = build_node(["Start"])
    form1 = build_node(["Form"], form_id: Ecto.UUID.generate())
    form2 = build_node(["Form"], form_id: Ecto.UUID.generate())
    stop = build_node(["End"])

    edges = [edge(start, form1), edge(form1, form2), edge(form2, stop)]
    {tree([start, form1, form2, stop], edges), start, form1, form2, stop}
  end

  # Start → Name → Address → End, in a named "forms" flow
  defp named_flow do
    flow = forms_flow("Application")
    start = build_node(["Start"])
    name = form_node("Name")
    address = form_node("Address")
    stop = build_node(["End"])

    edges = [edge(start, name), edge(name, address), edge(address, stop)]

    {tree([start, name, address, stop], edges, %{}, flow), flow, name, address}
  end

  describe "derive/2 on a linear flow" do
    test "an untouched journey: first form available, the rest pending" do
      {tree, start, form1, form2, stop} = linear_flow()

      statuses = FlowProgress.derive(tree, [])

      assert statuses[[start.id]] == :completed
      assert statuses[[form1.id]] == :available
      assert statuses[[form2.id]] == :pending
      assert statuses[[stop.id]] == :pending
      refute FlowProgress.complete?(tree, [])
    end

    test "an instance in progress marks its position and gates the next" do
      {tree, _start, form1, form2, _stop} = linear_flow()

      statuses = FlowProgress.derive(tree, [form_instance([form1.id], "in_progress")])

      assert statuses[[form1.id]] == :in_progress
      assert statuses[[form2.id]] == :pending
    end

    test "completion unlocks the successor and, at End, the journey" do
      {tree, _start, form1, form2, stop} = linear_flow()

      statuses = FlowProgress.derive(tree, [form_instance([form1.id], "completed")])
      assert statuses[[form1.id]] == :completed
      assert statuses[[form2.id]] == :available

      instances = [
        form_instance([form1.id], "completed"),
        form_instance([form2.id], "completed")
      ]

      assert FlowProgress.derive(tree, instances)[[stop.id]] == :completed
      assert FlowProgress.complete?(tree, instances)
    end
  end

  describe "derive/2 join semantics (AND-join)" do
    test "End waits for every parallel branch" do
      start = build_node(["Start"])
      form1 = build_node(["Form"], form_id: Ecto.UUID.generate())
      form2 = build_node(["Form"], form_id: Ecto.UUID.generate())
      stop = build_node(["End"])

      edges = [edge(start, form1), edge(start, form2), edge(form1, stop), edge(form2, stop)]
      tree = tree([start, form1, form2, stop], edges)

      one_done = [form_instance([form1.id], "completed")]
      assert FlowProgress.derive(tree, one_done)[[stop.id]] == :pending
      refute FlowProgress.complete?(tree, one_done)

      both_done = [form_instance([form2.id], "completed") | one_done]
      assert FlowProgress.derive(tree, both_done)[[stop.id]] == :completed
      assert FlowProgress.complete?(tree, both_done)
    end
  end

  describe "derive/2 with subflows" do
    defp nested_flow do
      inner_start = build_node(["Start"])
      inner_form = build_node(["Form"], form_id: Ecto.UUID.generate())
      inner_stop = build_node(["End"])

      inner =
        tree([inner_start, inner_form, inner_stop], [
          edge(inner_start, inner_form),
          edge(inner_form, inner_stop)
        ])

      start = build_node(["Start"])
      subflow = build_node(["Subflow"], subflow_id: Ecto.UUID.generate())
      stop = build_node(["End"])

      outer =
        tree([start, subflow, stop], [edge(start, subflow), edge(subflow, stop)], %{
          subflow.id => inner
        })

      {outer, subflow, inner_form, stop}
    end

    test "interior positions are addressed by the embedding chain" do
      {outer, subflow, inner_form, _stop} = nested_flow()

      statuses = FlowProgress.derive(outer, [])
      assert statuses[[subflow.id]] == :available
      assert statuses[[subflow.id, inner_form.id]] == :available
    end

    test "interior activity marks the subflow in progress; interior End completes it" do
      {outer, subflow, inner_form, stop} = nested_flow()

      in_progress = [form_instance([subflow.id, inner_form.id], "in_progress")]
      assert FlowProgress.derive(outer, in_progress)[[subflow.id]] == :in_progress

      completed = [form_instance([subflow.id, inner_form.id], "completed")]
      statuses = FlowProgress.derive(outer, completed)
      assert statuses[[subflow.id]] == :completed
      assert statuses[[stop.id]] == :completed
      assert FlowProgress.complete?(outer, completed)
    end
  end

  describe "next_path_position/2" do
    test "walks the flow in order: first available, then the one after" do
      {tree, _start, form1, form2, _stop} = linear_flow()

      assert FlowProgress.next_path_position(tree, []) == [form1.id]

      done_one = [form_instance([form1.id], "completed")]
      assert FlowProgress.next_path_position(tree, done_one) == [form2.id]

      all_done = [form_instance([form2.id], "completed") | done_one]
      assert FlowProgress.next_path_position(tree, all_done) == nil
    end

    test "an in-progress form is the next stop — resume before advancing" do
      {tree, _start, form1, _form2, _stop} = linear_flow()

      instances = [form_instance([form1.id], "in_progress")]
      assert FlowProgress.next_path_position(tree, instances) == [form1.id]
    end

    test "descends into an available subflow" do
      {outer, subflow, inner_form, _stop} = nested_flow()

      assert FlowProgress.next_path_position(outer, []) == [subflow.id, inner_form.id]

      done = [form_instance([subflow.id, inner_form.id], "completed")]
      assert FlowProgress.next_path_position(outer, done) == nil
    end
  end

  describe "derive/2 stranding and supersession" do
    test "an instance whose path matches no position surfaces as stranded" do
      {tree, _start, form1, _form2, _stop} = linear_flow()
      dead_path = [Ecto.UUID.generate()]

      statuses =
        FlowProgress.derive(tree, [
          form_instance([form1.id], "completed"),
          form_instance(dead_path, "in_progress")
        ])

      assert statuses[dead_path] == :stranded
      assert statuses[[form1.id]] == :completed
    end

    test "superseded instances are skipped everywhere" do
      {tree, _start, form1, _form2, _stop} = linear_flow()
      dead_path = [Ecto.UUID.generate()]
      stamp = DateTime.utc_now()

      statuses =
        FlowProgress.derive(tree, [
          # a superseded completed instance must not complete its position
          form_instance([form1.id], "completed", superseded_at: stamp),
          # a superseded stranded instance must not resurface as stranded
          form_instance(dead_path, "in_progress", superseded_at: stamp)
        ])

      assert statuses[[form1.id]] == :available
      refute Map.has_key?(statuses, dead_path)
    end
  end

  describe "forms/2" do
    test "the flow's forms in the order they are worked, with their state" do
      {tree, flow, name, address} = named_flow()
      instances = [form_instance([name.id], "completed")]

      assert [first, second] = FlowProgress.forms(tree, instances)

      assert first.path == [name.id]
      assert first.label == "Name"
      assert first.status == :completed
      assert first.instance.path == [name.id]
      assert first.ancestors == []
      assert first.flow == flow

      assert second.path == [address.id]
      assert second.label == "Address"
      assert second.status == :available
      assert is_nil(second.instance)
    end

    test "an untouched journey has no instances attached" do
      {tree, _flow, name, address} = named_flow()

      assert [first, second] = FlowProgress.forms(tree, [])

      assert {first.path, first.status, first.instance} == {[name.id], :available, nil}
      assert {second.path, second.status} == {[address.id], :pending}
    end

    test "superseded instances are ignored, like everywhere else" do
      {tree, _flow, name, _address} = named_flow()
      superseded = form_instance([name.id], "completed", superseded_at: DateTime.utc_now())

      assert [first, _second] = FlowProgress.forms(tree, [superseded])
      assert is_nil(first.instance)
      assert first.status == :available
    end

    test "a stranded instance is not one of the flow's forms" do
      {tree, _flow, _name, _address} = named_flow()
      dead_path = [Ecto.UUID.generate()]
      stranded = form_instance(dead_path, "in_progress")

      forms = FlowProgress.forms(tree, [stranded])

      assert length(forms) == 2
      refute Enum.any?(forms, &(&1.path == dead_path))
      # ...though derive/2 still surfaces it, which is what strand sweeps read
      assert FlowProgress.derive(tree, [stranded])[dead_path] == :stranded
    end

    test "a nil tree (a deleted flow) has no forms" do
      assert FlowProgress.forms(nil, []) == []
    end

    test "forms inside subflows carry the nodes drilled through and their own flow" do
      {subtree, subflow, name, _address} = named_flow()

      root = %Flow{id: Ecto.UUID.generate(), name: "Onboarding", label: "subflows"}
      start = build_node(["Start"])
      documents = build_node(["Subflow"], subflow_id: subflow.id, label: "Documents")
      stop = build_node(["End"])

      tree =
        tree(
          [start, documents, stop],
          [edge(start, documents), edge(documents, stop)],
          %{documents.id => subtree},
          root
        )

      assert [first, second] = FlowProgress.forms(tree, [])

      assert first.path == [documents.id, name.id]
      assert first.ancestors == [documents]
      assert first.flow == subflow
      assert FlowProgress.qualified_label(first) == "Documents / Name"
      assert FlowProgress.qualified_label(second) == "Documents / Address"
    end
  end

  describe "forms_in_flow/2 and find_form/2" do
    test "narrow a journey's forms to the one flow a form_flow_type governs" do
      {subtree_a, flow_a, name_a, _address_a} = named_flow()
      {subtree_b, flow_b, name_b, _address_b} = named_flow()

      root = %Flow{id: Ecto.UUID.generate(), label: "subflows"}
      start = build_node(["Start"])
      a = build_node(["Subflow"], subflow_id: flow_a.id, label: "A")
      b = build_node(["Subflow"], subflow_id: flow_b.id, label: "B")

      tree =
        tree(
          [start, a, b],
          [edge(start, a), edge(a, b)],
          %{a.id => subtree_a, b.id => subtree_b},
          root
        )

      forms = FlowProgress.forms(tree, [])
      assert length(forms) == 4

      in_flow = FlowProgress.forms_in_flow(forms, [a.id, name_a.id])
      assert Enum.map(in_flow, & &1.label) == ["Name", "Address"]
      assert Enum.all?(in_flow, &(hd(&1.path) == a.id))

      assert FlowProgress.find_form(forms, [b.id, name_b.id]).flow == flow_b
      assert is_nil(FlowProgress.find_form(forms, ["nope"]))
    end
  end

  describe "qualified_label/1" do
    test "unqualified for a form in the root flow" do
      {tree, _flow, _name, _address} = named_flow()

      assert [first | _rest] = FlowProgress.forms(tree, [])
      assert FlowProgress.qualified_label(first) == "Name"
    end

    test "falls back to the node's label when the canvas has no name" do
      start = build_node(["Start"])
      unnamed = build_node(["Form"], form_id: Ecto.UUID.generate())

      tree = tree([start, unnamed], [edge(start, unnamed)])

      assert [%{label: "Form"}] = FlowProgress.forms(tree, [])
    end
  end

  describe "actionable?/1" do
    test "is where the flow allows work: an available or started form" do
      assert FlowProgress.actionable?(%Instances.FormProgress{status: :available})
      assert FlowProgress.actionable?(%Instances.FormProgress{status: :in_progress})
      refute FlowProgress.actionable?(%Instances.FormProgress{status: :pending})
      refute FlowProgress.actionable?(%Instances.FormProgress{status: :completed})
      refute FlowProgress.actionable?(%Instances.FormProgress{status: :stranded})
    end
  end
end
