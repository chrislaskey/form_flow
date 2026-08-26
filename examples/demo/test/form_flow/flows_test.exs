defmodule Demo.FormFlowFlowsTest do
  @moduledoc """
  Exercises `FormFlow.Data.Templates.Flows` and the flow schemas against a real database —
  the library's own tests stop at changesets, so this is where the V01 flow DDL
  (foreign keys, cascades, the unique relationship index) is proven to hold.
  """

  use Demo.DataCase, async: false

  alias FormFlow.Data.Repo, as: FormFlowRepo
  alias FormFlow.Data.Templates.Flow
  alias FormFlow.Data.Templates.Flows

  test "create, get, update, and delete a flow" do
    assert {:ok, %Flow{id: id}} = Flows.create()

    assert %Flow{id: ^id, nodes: [], relationships: []} = Flows.get(id)

    assert {:ok, %Flow{id: ^id}} = Flows.update(Flows.get(id), %{})

    assert {:ok, _} = Flows.delete(Flows.get(id))
    assert Flows.get(id) == nil
  end

  test "list returns flows with counts, without loading their contents" do
    {:ok, first} = Flows.create()
    {:ok, second} = Flows.create()

    start = insert_node(first)
    form = insert_node(first)
    insert_relationship(first, start, form)

    assert [%Flow{id: a}, %Flow{id: b}] = Flows.list()
    assert {a, b} == {first.id, second.id}

    assert [
             %Flow{nodes_count: 2, relationships_count: 1},
             %Flow{nodes_count: 0, relationships_count: 0}
           ] = Flows.list()

    assert [%Flow{nodes: %Ecto.Association.NotLoaded{}} | _] = Flows.list()

    # Owned subflow children live inside their root — never listed beside it
    {:ok, _child} = Flows.create(%{owner_flow_id: first.id})
    assert length(Flows.list()) == 2
  end

  test "get loads nodes and relationships, round-tripping labels and properties" do
    {:ok, flow} = Flows.create()

    start = insert_node(flow, ["Step", "Start"], %{"label" => "Start"})
    form = insert_node(flow, ["Step"], %{"label" => "Form", "fields" => 4})
    insert_relationship(flow, start, form, %{"if" => "always"})

    assert %Flow{nodes: nodes, relationships: [relationship]} = Flows.get(flow.id)

    assert length(nodes) == 2
    assert Enum.find(nodes, &(&1.id == start.id)).labels == ["Step", "Start"]

    assert Enum.find(nodes, &(&1.id == form.id)).properties == %{
             "label" => "Form",
             "fields" => 4,
             "flow_id" => flow.id
           }

    assert relationship.label == "TRANSITIONS_TO"
    assert relationship.properties == %{"if" => "always", "flow_id" => flow.id}
    assert {relationship.source_id, relationship.target_id} == {start.id, form.id}
  end

  test "flow_id is written to both the column and properties" do
    {:ok, flow} = Flows.create()
    node = insert_node(flow)
    other = insert_node(flow)
    relationship = insert_relationship(flow, node, other)

    assert node.flow_id == flow.id
    assert node.properties["flow_id"] == flow.id

    assert relationship.flow_id == flow.id
    assert relationship.properties["flow_id"] == flow.id
  end

  test "a source and target can only be linked once per label" do
    {:ok, flow} = Flows.create()
    start = insert_node(flow)
    form = insert_node(flow)

    insert_relationship(flow, start, form)

    assert {:error, changeset} =
             FormFlowRepo.insert(relationship_changeset(flow, start, form))

    assert %{source_id: ["has already been taken"]} = errors_on(changeset)

    # The same pair under a different label is fine
    assert {:ok, _} =
             FormFlowRepo.insert(
               relationship_changeset(flow, start, form, label: "FALLS_BACK_TO")
             )
  end

  test "relationships require nodes that exist" do
    {:ok, flow} = Flows.create()
    start = insert_node(flow)

    changeset =
      Flow.Relationship.changeset(%Flow.Relationship{}, %{
        flow_id: flow.id,
        source_id: start.id,
        target_id: Ecto.UUID.generate(),
        label: "TRANSITIONS_TO"
      })

    # SQLite reports foreign key violations without naming the constraint, so
    # Ecto cannot route them to the changeset's foreign_key_constraint and
    # raises instead. On Postgres this same insert returns {:error, changeset}
    # with "does not exist" on :target_id.
    assert_raise Ecto.ConstraintError, ~r/foreign_key_constraint/, fn ->
      FormFlowRepo.insert(changeset)
    end
  end

  test "deleting a node detaches it: its relationships go too" do
    {:ok, flow} = Flows.create()
    start = insert_node(flow)
    form = insert_node(flow)
    insert_relationship(flow, start, form)

    assert {:ok, _} = FormFlowRepo.delete(form)

    assert %Flow{relationships: []} = Flows.get(flow.id)
  end

  test "deleting a flow cascades to every node and relationship in it" do
    {:ok, flow} = Flows.create()
    start = insert_node(flow)
    form = insert_node(flow)
    insert_relationship(flow, start, form)

    assert {:ok, _} = Flows.delete(Flows.get(flow.id))

    assert {:ok, %{rows: [[0]]}} = Repo.query("SELECT count(*) FROM form_flow_nodes")

    assert {:ok, %{rows: [[0]]}} =
             Repo.query("SELECT count(*) FROM form_flow_relationships")
  end

  describe "declared flavor and save-time children" do
    test "create persists name and label; label is immutable" do
      {:ok, flow} = Flows.create(%{name: "Enrollment", label: "subflows"})

      assert flow.name == "Enrollment"
      assert flow.label == "subflows"

      assert {:error, changeset} = Flows.update(flow, %{label: "forms"})
      assert %{label: ["cannot be changed after creation"]} = errors_on(changeset)

      assert {:ok, renamed} = Flows.update(flow, %{name: "Renamed"})
      assert renamed.name == "Renamed"
    end

    test "a forms flow rejects subflow steps" do
      {:ok, flow} = Flows.create(%{label: "forms"})

      assert {:error, changeset} =
               Flows.update(flow, %{
                 nodes: [%{properties: %{"type" => "subflow", "data" => %{}}}],
                 relationships: []
               })

      assert %{nodes: ["a forms flow cannot contain subflow steps"]} = errors_on(changeset)
    end

    test "a subflows flow rejects form steps but accepts Start and End" do
      {:ok, flow} = Flows.create(%{label: "subflows"})

      assert {:error, changeset} =
               Flows.update(flow, %{
                 nodes: [%{properties: %{"type" => "step", "data" => %{"kind" => "form"}}}],
                 relationships: []
               })

      assert %{nodes: ["a subflows flow cannot contain form steps"]} = errors_on(changeset)

      assert {:ok, _} =
               Flows.update(Flows.get(flow.id), %{
                 nodes: Flows.starter_nodes(),
                 relationships: []
               })
    end

    test "saving creates children for subflow nodes, from their declared label" do
      {:ok, root} =
        Flows.create(%{label: "subflows", nodes: Flows.starter_nodes(), relationships: []})

      {:ok, _} =
        Flows.update(Flows.get(root.id), %{
          nodes: [
            %{
              properties: %{
                "type" => "subflow",
                "data" => %{"label" => "Collect address", "subflow_label" => "forms"}
              }
            },
            %{
              properties: %{
                "type" => "subflow",
                "data" => %{"label" => "Interview", "subflow_label" => "subflows"}
              }
            }
          ],
          relationships: []
        })

      root = Flows.get(root.id)
      children = root.nodes |> Enum.map(& &1.subflow_id) |> Enum.map(&Flows.get/1)

      address = Enum.find(children, &(&1.name == "Collect address"))
      interview = Enum.find(children, &(&1.name == "Interview"))

      assert address.label == "forms"
      assert interview.label == "subflows"

      # Owned by the root, seeded with the universal Start/End starter
      for child <- children do
        assert child.owner_flow_id == root.id

        assert child.nodes |> Enum.map(&get_in(&1.properties, ["data", "label"])) |> Enum.sort() ==
                 ["End", "Start"]

        assert child.relationships == []
      end

      # Saving again does not create duplicates: the references round-trip
      {:ok, _} =
        Flows.update(root, %{
          nodes: Enum.map(root.nodes, &%{id: &1.id, properties: &1.properties}),
          relationships: []
        })

      assert Flows.get(root.id).nodes
             |> Enum.map(& &1.subflow_id)
             |> Enum.sort() == Enum.sort([address.id, interview.id])
    end
  end

  describe "subflows and ownership" do
    test "an owned subflow: created, referenced, drilled into" do
      {:ok, root} = Flows.create()
      {:ok, child} = Flows.create(%{owner_flow_id: root.id})

      node = insert_subflow_node(root, child)

      assert Flows.owned?(child)
      refute Flows.owned?(root)

      # The reference dual-writes into properties, like flow_id
      assert node.subflow_id == child.id
      assert node.properties["subflow_id"] == child.id

      assert %Flow{id: id} = Flows.get(node.subflow_id)
      assert id == child.id
    end

    test "a subflow reference survives the editor round-trip via properties" do
      {:ok, root} = Flows.create(%{label: "subflows"})
      {:ok, child} = Flows.create(%{owner_flow_id: root.id})

      # The editor sends properties untouched, no :subflow_id attribute
      {:ok, _} =
        Flows.update(root, %{
          nodes: [%{id: Ecto.UUID.generate(), properties: %{"subflow_id" => child.id}}],
          relationships: []
        })

      assert [node] = Flows.get(root.id).nodes
      assert node.subflow_id == child.id
      assert Flows.get(child.id) != nil
    end

    test "make_reusable detaches, stamps, and re-homes descendants" do
      {:ok, root} = Flows.create()
      {:ok, middle} = Flows.create(%{owner_flow_id: root.id})
      {:ok, leaf} = Flows.create(%{owner_flow_id: root.id})

      insert_subflow_node(root, middle)
      insert_subflow_node(middle, leaf)

      assert {:ok, middle} = Flows.make_reusable(Flows.get(middle.id))

      assert middle.owner_flow_id == nil
      assert %DateTime{} = middle.made_reusable_at

      # The leaf under it stays private, re-homed to the new ownership root
      assert Flows.get(leaf.id).owner_flow_id == middle.id
    end

    test "list_reusable lists only flows made reusable, newest first" do
      {:ok, _root} = Flows.create()
      {:ok, first} = Flows.create()
      {:ok, second} = Flows.create()

      {:ok, _} = Flows.make_reusable(first)
      {:ok, _} = Flows.make_reusable(second)

      assert Enum.map(Flows.list_reusable(), & &1.id) == [second.id, first.id]
    end

    test "duplicate deep-copies owned children and keeps reusable references" do
      {:ok, root} = Flows.create()
      {:ok, owned} = Flows.create(%{owner_flow_id: root.id})
      {:ok, shared} = Flows.create()
      {:ok, shared} = Flows.make_reusable(shared)

      form = insert_node(owned, ["Step"], %{"label" => "Inside"})
      insert_subflow_node(root, owned)
      insert_subflow_node(root, shared)

      assert {:ok, copy} = Flows.duplicate(Flows.get(root.id))

      assert copy.id != root.id
      assert copy.made_reusable_at == nil

      copied_refs = copy.nodes |> Enum.map(& &1.subflow_id) |> Enum.reject(&is_nil/1)

      # The reusable reference is shared; the owned one points at a fresh copy
      assert shared.id in copied_refs
      assert [owned_copy_id] = copied_refs -- [shared.id]
      assert owned_copy_id != owned.id

      owned_copy = Flows.get(owned_copy_id)
      assert owned_copy.owner_flow_id == copy.id
      assert [inside] = owned_copy.nodes
      assert inside.id != form.id
      assert inside.properties["label"] == "Inside"
    end

    test "deleting a flow referenced by another flow is refused" do
      {:ok, root} = Flows.create()
      {:ok, shared} = Flows.create()
      {:ok, shared} = Flows.make_reusable(shared)

      insert_subflow_node(root, shared)

      assert {:error, changeset} = Flows.delete(shared)
      assert %{id: ["is still used as a subflow by another flow"]} = errors_on(changeset)

      # Remove the reference and deletion goes through
      {:ok, _} = Flows.update(Flows.get(root.id), %{nodes: [], relationships: []})
      assert {:ok, _} = Flows.delete(shared)
    end

    test "deleting a root deletes its owned tree, sparing reusable flows" do
      {:ok, root} = Flows.create()
      {:ok, owned} = Flows.create(%{owner_flow_id: root.id})
      {:ok, shared} = Flows.create()
      {:ok, shared} = Flows.make_reusable(shared)

      insert_subflow_node(root, owned)
      insert_subflow_node(root, shared)

      assert {:ok, _} = Flows.delete(Flows.get(root.id))

      assert Flows.get(root.id) == nil
      assert Flows.get(owned.id) == nil
      assert Flows.get(shared.id) != nil
    end

    test "delete_node removes the step and collects owned children, sparing reusable" do
      {:ok, root} = Flows.create(%{label: "subflows"})
      {:ok, owned} = Flows.create(%{owner_flow_id: root.id})
      {:ok, grandchild} = Flows.create(%{owner_flow_id: root.id})
      {:ok, shared} = Flows.create()
      {:ok, shared} = Flows.make_reusable(shared)

      owned_node = insert_subflow_node(root, owned)
      shared_node = insert_subflow_node(root, shared)
      insert_subflow_node(owned, grandchild)

      {:ok, _} = Flows.delete_node(owned_node)

      # The step is gone, and the owned subtree went with it
      assert Flows.get_node(owned_node.id) == nil
      assert Flows.get(owned.id) == nil
      assert Flows.get(grandchild.id) == nil

      # Removing a reusable usage keeps the reusable flow
      {:ok, _} = Flows.delete_node(shared_node)
      assert Flows.get(shared.id) != nil
    end

    test "saving contents garbage-collects unreachable owned subflows" do
      {:ok, root} = Flows.create(%{label: "subflows"})
      {:ok, kept} = Flows.create(%{owner_flow_id: root.id})
      {:ok, dropped} = Flows.create(%{owner_flow_id: root.id})
      {:ok, grandchild} = Flows.create(%{owner_flow_id: root.id})

      keeper = insert_subflow_node(root, kept)
      insert_subflow_node(root, dropped)
      insert_subflow_node(dropped, grandchild)

      # Save the root keeping only the node that references `kept`
      {:ok, _} =
        Flows.update(Flows.get(root.id), %{
          nodes: [%{id: keeper.id, subflow_id: kept.id, properties: keeper.properties}],
          relationships: []
        })

      assert Flows.get(kept.id) != nil
      assert Flows.get(dropped.id) == nil
      assert Flows.get(grandchild.id) == nil
    end
  end

  defp insert_node(flow, labels \\ ["Step"], properties \\ %{}) do
    {:ok, node} =
      %Flow.Node{}
      |> Flow.Node.changeset(%{flow_id: flow.id, labels: labels, properties: properties})
      |> FormFlowRepo.insert()

    node
  end

  defp insert_relationship(flow, source, target, properties \\ %{}) do
    {:ok, relationship} =
      FormFlowRepo.insert(relationship_changeset(flow, source, target, properties: properties))

    relationship
  end

  defp insert_subflow_node(flow, subflow) do
    {:ok, node} =
      %Flow.Node{}
      |> Flow.Node.changeset(%{
        flow_id: flow.id,
        subflow_id: subflow.id,
        properties: %{"type" => "subflow"}
      })
      |> FormFlowRepo.insert()

    node
  end

  defp relationship_changeset(flow, source, target, opts \\ []) do
    Flow.Relationship.changeset(%Flow.Relationship{}, %{
      flow_id: flow.id,
      source_id: source.id,
      target_id: target.id,
      label: Keyword.get(opts, :label, "TRANSITIONS_TO"),
      properties: Keyword.get(opts, :properties, %{})
    })
  end
end
