defmodule Demo.FormFlowTemplateFlowSnapshotsTest do
  @moduledoc """
  Exercises template flow snapshots against a real database
  (`FormFlow.Data.Templates.Flow.Snapshot`,
  `FormFlow.Data.Templates.Flows.Snapshots`): what `take/1` holds and
  leaves out, that a snapshot reads back as the tree `resolve_tree/1`
  gives, when two trees are one snapshot and when they are two, and that a
  journey records one as it starts.
  """

  use Demo.DataCase, async: false

  alias FormFlow.Data.Instances
  alias FormFlow.Data.Repo, as: FormFlowRepo
  alias FormFlow.Data.Templates.Flow
  alias FormFlow.Data.Templates.Flow.Snapshot
  alias FormFlow.Data.Templates.Flows
  alias FormFlow.Data.Templates.Flows.Health
  alias FormFlow.Data.Templates.Flows.Snapshots
  alias FormFlow.Data.Templates.Forms

  describe "Snapshot.take/1" do
    test "holds every column of every row as JSON primitives, and the tree's shape" do
      %{root: root, documents: documents, documents_node: documents_node, forms: [first, _second]} =
        nested_flow()

      data = root.id |> Flows.resolve_tree() |> Snapshot.take()

      assert %{
               "flow" => flow,
               "nodes" => nodes,
               "relationships" => relationships,
               "subflows" => subflows
             } =
               data

      assert flow["id"] == root.id
      assert flow["name"] == "Onboarding"
      assert flow["label"] == "subflows"
      assert is_binary(flow["inserted_at"]) and is_binary(flow["updated_at"])
      refute Map.has_key?(flow, "status")
      refute Map.has_key?(flow, "nodes_count")

      assert Enum.map(nodes, & &1["id"]) == Enum.map(Flows.get(root.id).nodes, & &1.id)
      assert length(relationships) == 2

      documents_node_id = documents_node.id
      assert %{^documents_node_id => subtree} = subflows
      assert subtree["flow"]["id"] == documents.id
      assert subtree["flow"]["owner_flow_id"] == root.id
      assert Enum.find(subtree["nodes"], &(&1["id"] == first.id))["form_id"] == first.form_id
      assert subtree["subflows"] == %{}

      # Every key a string, every value a JSON primitive: the map encodes
      # and decodes to itself
      assert data |> Jason.encode!() |> Jason.decode!() == data
    end

    test "leaves the library's own bookkeeping out of every properties map" do
      %{root: root} = nested_flow()
      Health.refresh(root.id)
      assert Map.has_key?(Flows.get(root.id).properties, "_health_metadata")

      data = root.id |> Flows.resolve_tree() |> Snapshot.take()

      refute Enum.any?(Map.keys(data["flow"]["properties"]), &String.starts_with?(&1, "_"))
    end

    test "nil for nil" do
      assert Snapshot.take(nil) == nil
    end
  end

  describe "Snapshots.tree/1" do
    test "reads back as the tree resolve_tree/1 gives, back-references included" do
      %{root: root, documents: documents, documents_node: documents_node, forms: [first, second]} =
        nested_flow()

      live = Flows.resolve_tree(root.id)
      {:ok, snapshot} = Snapshots.get_or_create(root, live)
      tree = Snapshots.tree(snapshot)

      assert %Flow{id: root_id, status: "open", nodes: nodes, relationships: relationships} =
               tree.flow

      assert root_id == root.id
      assert %DateTime{} = tree.flow.inserted_at
      assert tree.flow.inserted_at == live.flow.inserted_at
      assert nodes == tree.nodes
      assert relationships == tree.relationships
      assert Enum.map(tree.nodes, & &1.id) == Enum.map(live.nodes, & &1.id)

      subflow_node = Enum.find(tree.nodes, &(&1.id == documents_node.id))
      assert %Flow{id: documents_id} = subflow_node.subflow
      assert documents_id == documents.id
      assert subflow_node.subflow == tree.subflows[documents_node.id].flow

      subtree = tree.subflows[documents_node.id]

      assert Enum.map(subtree.nodes, & &1.id) ==
               Enum.map(live.subflows[documents_node.id].nodes, & &1.id)

      form_node = Enum.find(subtree.nodes, &(&1.id == first.id))
      assert form_node.form.id == first.form_id
      assert form_node.subflow == nil
      assert Enum.find(subtree.nodes, &(&1.id == second.id)).form.id == second.form_id

      # take → tree → take is the identity: the row holds the map that was hashed
      assert Snapshot.take(tree) == snapshot.data
      assert Snapshots.get(snapshot.id).data == snapshot.data
      assert Snapshot.checksum(Snapshots.get(snapshot.id).data) == snapshot.checksum
    end

    test "the flow's status is read live" do
      %{root: root} = nested_flow()
      {:ok, snapshot} = Snapshots.get_or_create(root, Flows.resolve_tree(root.id))

      {:ok, _flow} = Flows.update_status(root, :winding_down)

      assert Snapshots.tree(snapshot).flow.status == "winding_down"
    end

    test "a form template that is gone leaves the node with no form" do
      %{root: root, documents_node: documents_node, forms: [first, _second]} = nested_flow()
      {:ok, snapshot} = Snapshots.get_or_create(root, Flows.resolve_tree(root.id))

      FormFlowRepo.delete_all(from(n in Flow.Node, where: n.id == ^first.id))
      {:ok, _form} = Forms.delete(Forms.get(first.form_id))

      subtree = Snapshots.tree(snapshot).subflows[documents_node.id]
      node = Enum.find(subtree.nodes, &(&1.id == first.id))
      assert node.form_id == first.form_id
      assert node.form == nil
    end

    test "nil for nil" do
      assert Snapshots.tree(nil) == nil
    end
  end

  describe "Snapshots.get_or_create/2" do
    test "the same tree twice is one snapshot; a save is a new one, numbered on" do
      %{root: root, documents: documents} = nested_flow()

      {:ok, first} = Snapshots.get_or_create(root, Flows.resolve_tree(root.id))
      {:ok, again} = Snapshots.get_or_create(root, Flows.resolve_tree(root.id))
      assert again.id == first.id
      assert first.number == 1
      assert first.template_flow_id == root.id

      {:ok, _renamed} = Flows.update(root, %{name: "Onboarding 2027"})
      {:ok, second} = Snapshots.get_or_create(root, Flows.resolve_tree(root.id))
      assert second.id != first.id
      assert second.number == 2
      assert second.checksum != first.checksum

      # A save of a subflow is a save of the tree
      {:ok, _renamed} = Flows.update(Flows.get(documents.id), %{name: "Documents 2027"})
      {:ok, third} = Snapshots.get_or_create(root, Flows.resolve_tree(root.id))
      assert third.number == 3

      assert Enum.map(Snapshots.list(root), & &1.number) == [1, 2, 3]
    end

    test "a status change is a new snapshot; a health refresh is not" do
      %{root: root} = nested_flow()
      {:ok, first} = Snapshots.get_or_create(root, Flows.resolve_tree(root.id))

      Health.refresh(root.id)
      {:ok, same} = Snapshots.get_or_create(root, Flows.resolve_tree(root.id))
      assert same.id == first.id

      {:ok, _flow} = Flows.update_status(root, :winding_down)
      {:ok, next} = Snapshots.get_or_create(root, Flows.resolve_tree(root.id))
      assert next.id != first.id
      assert next.number == 2
    end

    test "a node moved on the canvas is a new snapshot" do
      %{root: root, documents_node: documents_node} = nested_flow()
      {:ok, first} = Snapshots.get_or_create(root, Flows.resolve_tree(root.id))

      moved = Map.put(documents_node.properties, "position", %{"x" => 10, "y" => 20})

      {:ok, _node} =
        FormFlowRepo.update(Flow.Node.changeset(documents_node, %{properties: moved}))

      {:ok, next} = Snapshots.get_or_create(root, Flows.resolve_tree(root.id))
      assert next.id != first.id
    end

    test "the checksum is over the encoded data, and can be checked from the row" do
      %{root: root} = nested_flow()
      data = root.id |> Flows.resolve_tree() |> Snapshot.take()
      {:ok, snapshot} = Snapshots.get_or_create(root, Flows.resolve_tree(root.id))

      assert snapshot.checksum == Snapshot.checksum(data)
      assert snapshot.checksum == Snapshot.checksum(Snapshots.get(snapshot.id).data)
      assert String.length(snapshot.checksum) == 64
    end
  end

  describe "a journey starting" do
    test "records the flow's snapshot, and reads its tree from it" do
      %{root: root} = nested_flow()

      {:ok, journey} = Instances.Flows.create(%{template_flow_id: root.id, user_id: "dog_owner"})

      assert is_binary(journey.template_flow_snapshot_id)
      snapshot = Snapshots.get(journey.template_flow_snapshot_id)
      assert snapshot.number == 1
      assert snapshot.template_flow_id == root.id
      assert Snapshots.tree(journey).flow.id == root.id
    end

    test "two starts of an unchanged flow share one snapshot; a save between them makes two" do
      %{root: root} = nested_flow()

      {:ok, one} = Instances.Flows.create(%{template_flow_id: root.id, user_id: "dog_owner"})
      {:ok, two} = Instances.Flows.create(%{template_flow_id: root.id, user_id: "cat_owner"})
      assert one.template_flow_snapshot_id == two.template_flow_snapshot_id

      {:ok, _renamed} = Flows.update(root, %{name: "Onboarding 2027"})
      {:ok, three} = Instances.Flows.create(%{template_flow_id: root.id, user_id: "dog_owner"})
      assert three.template_flow_snapshot_id != one.template_flow_snapshot_id
      assert Snapshots.get(three.template_flow_snapshot_id).number == 2
    end

    test "a flow that does not exist is refused on the changeset, as before" do
      assert {:error, changeset} =
               Instances.Flows.create(%{template_flow_id: Ecto.UUID.generate(), user_id: "x"})

      assert %{template_flow_id: ["does not exist"]} = errors_on(changeset)
    end

    test "the snapshot outlives the journey and goes with the flow" do
      %{root: root} = nested_flow()
      {:ok, journey} = Instances.Flows.create(%{template_flow_id: root.id, user_id: "dog_owner"})
      snapshot_id = journey.template_flow_snapshot_id

      {:ok, _deleted} = Instances.Flows.delete_instance(journey)
      assert Snapshots.get(snapshot_id)

      {:ok, _deleted} = Flows.delete(Flows.get(root.id))
      assert Snapshots.get(snapshot_id) == nil
    end
  end

  describe "Instances.Flows.move_to_snapshot/3" do
    test "moves the root's in-progress journeys, writes an event on each, and sweeps them" do
      %{root: root, documents_node: documents_node, forms: [first, second]} = nested_flow()
      {:ok, one} = Instances.Flows.create(%{template_flow_id: root.id, user_id: "dog_owner"})
      {:ok, two} = Instances.Flows.create(%{template_flow_id: root.id, user_id: "cat_owner"})
      first_snapshot = Snapshots.get(one.template_flow_snapshot_id)
      assert one.next_path == [documents_node.id, first.id]

      # The first form removed from the template, and the journeys moved to
      # the tree without it
      FormFlowRepo.delete_all(from(n in Flow.Node, where: n.id == ^first.id))
      edge(Flows.get(documents_node.subflow_id), start_of(documents_node.subflow_id), second)
      {:ok, next} = Snapshots.get_or_create(root, Flows.resolve_tree(root.id))
      assert next.number == 2

      assert {:ok, 2} = Instances.Flows.move_to_snapshot(root, next, user_id: "admin")

      for journey <- [one, two] do
        moved = Instances.Flows.get(journey.id)
        assert moved.template_flow_snapshot_id == next.id
        # Swept against the new tree: the first form is gone, the second is next
        assert moved.next_path == [documents_node.id, second.id]
        assert %DateTime{} = moved.next_computed_at
        assert Snapshots.tree(moved).flow.id == root.id

        [_created, event] = Instances.Flows.list_events(moved) |> Enum.map(& &1.event)
        assert event.event == "moved"
        assert event.user_id == "admin"
        assert event.snapshot["form_flow"] == %{"from_snapshot" => 1, "to_snapshot" => 2}
      end

      # Moving again to the same snapshot moves nobody and writes nothing
      assert {:ok, 0} = Instances.Flows.move_to_snapshot(root, next)
      assert length(Instances.Flows.list_events(Instances.Flows.get(one.id))) == 2
      assert Snapshots.get(first_snapshot.id)
    end

    test "a completed journey is never moved" do
      %{root: root, documents_node: documents_node, forms: [first, second]} = nested_flow()
      {:ok, journey} = Instances.Flows.create(%{template_flow_id: root.id, user_id: "dog_owner"})
      {:ok, _done} = Instances.Flows.complete(journey)
      snapshot_id = journey.template_flow_snapshot_id

      {:ok, _renamed} = Flows.update(root, %{name: "Onboarding 2027"})
      {:ok, next} = Snapshots.get_or_create(root, Flows.resolve_tree(root.id))
      assert {:ok, 0} = Instances.Flows.move_to_snapshot(root, next)

      assert Instances.Flows.get(journey.id).template_flow_snapshot_id == snapshot_id
      _ = {documents_node, first, second}
    end

    test "a move leaves a journey stranded at a step the new snapshot does not have" do
      %{root: root, documents_node: documents_node, forms: [first, second]} = nested_flow()
      {:ok, journey} = Instances.Flows.create(%{template_flow_id: root.id, user_id: "dog_owner"})
      path = [documents_node.id, first.id]
      {:ok, _opened} = Instances.Forms.update_status(journey, path, :in_progress)
      {:ok, _done} = Instances.Forms.update_status(journey, path, :completed, data: %{})
      assert Instances.Flows.list_stranded(journey) == []

      FormFlowRepo.delete_all(from(n in Flow.Node, where: n.id == ^first.id))
      edge(Flows.get(documents_node.subflow_id), start_of(documents_node.subflow_id), second)
      {:ok, next} = Snapshots.get_or_create(root, Flows.resolve_tree(root.id))
      {:ok, 1} = Instances.Flows.move_to_snapshot(root, next)

      assert [%{path: ^path}] = Instances.Flows.list_stranded(Instances.Flows.get(journey.id))
    end
  end

  describe "the sweep reads each journey's own snapshot" do
    test "two journeys on two snapshots are each recomputed against their own tree" do
      %{root: root, documents_node: documents_node, forms: [first, second]} = nested_flow()
      {:ok, old} = Instances.Flows.create(%{template_flow_id: root.id, user_id: "dog_owner"})

      FormFlowRepo.delete_all(from(n in Flow.Node, where: n.id == ^first.id))
      edge(Flows.get(documents_node.subflow_id), start_of(documents_node.subflow_id), second)
      {:ok, new} = Instances.Flows.create(%{template_flow_id: root.id, user_id: "cat_owner"})
      refute old.template_flow_snapshot_id == new.template_flow_snapshot_id

      assert {:ok, 2} = Instances.Flows.update_next_positions(root)

      assert Instances.Flows.get(old.id).next_path == [documents_node.id, first.id]
      assert Instances.Flows.get(new.id).next_path == [documents_node.id, second.id]
    end
  end

  describe "Instances.Flows.delete_pre_release/2" do
    test "prunes the snapshots no remaining journey reads" do
      %{root: root} = nested_flow()
      {:ok, root} = Flows.update_status(root, :pre_release)
      {:ok, trial} = Instances.Flows.create(%{template_flow_id: root.id, user_id: "tester"})

      {:ok, _renamed} = Flows.update(root, %{name: "Onboarding 2027"})
      {:ok, root} = Flows.update_status(Flows.get(root.id), :open)
      {:ok, real} = Instances.Flows.create(%{template_flow_id: root.id, user_id: "dog_owner"})
      refute trial.template_flow_snapshot_id == real.template_flow_snapshot_id

      assert {:ok, 1} = Instances.Flows.delete_pre_release(root)

      assert Snapshots.get(trial.template_flow_snapshot_id) == nil
      assert Snapshots.get(real.template_flow_snapshot_id)
    end
  end

  # ── fixtures ────────────────────────────────────────────────────────────

  defp start_of(flow_id) do
    Enum.find(Flows.get(flow_id).nodes, &("Start" in &1.labels))
  end

  # Start → Documents (Start → First → Second → End) - one subflow step
  # wrapping a two-form child flow
  defp nested_flow do
    {:ok, root} = Flows.create(%{name: "Onboarding", label: "subflows", status: "open"})

    {:ok, documents} =
      Flows.create(%{name: "Documents", label: "forms", owner_flow_id: root.id})

    first_node = build_node(documents, ["Start"], "Start")
    first = build_form_node(documents, "First")
    second = build_form_node(documents, "Second")
    last_node = build_node(documents, ["End"], "End")

    edge(documents, first_node, first)
    edge(documents, first, second)
    edge(documents, second, last_node)

    root_start = build_node(root, ["Start"], "Start")
    documents_node = build_node(root, ["Subflow"], "Documents", %{subflow_id: documents.id})
    root_end = build_node(root, ["End"], "End")

    edge(root, root_start, documents_node)
    edge(root, documents_node, root_end)

    %{root: root, documents: documents, documents_node: documents_node, forms: [first, second]}
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

  # A published form with one text question, "name"
  defp build_form_node(flow, label) do
    {:ok, form} = Forms.create(%{name: "#{label} #{System.unique_integer([:positive])}"})
    [draft] = form.versions

    definition = %{"elements" => [%{"type" => "text", "name" => "name", "title" => "Name"}]}
    {:ok, draft} = Forms.update_draft(draft, %{definition: definition})
    {:ok, _published} = Forms.update_status(draft, :published)

    build_node(flow, ["Form"], label, %{form_id: form.id})
  end

  defp edge(flow, source, target) do
    {:ok, relationship} =
      FormFlowRepo.insert(
        Flow.Relationship.changeset(%Flow.Relationship{}, %{
          flow_id: flow.id,
          source_id: source.id,
          target_id: target.id,
          label: "CONNECTS_TO"
        })
      )

    relationship
  end
end
