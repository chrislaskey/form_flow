defmodule Demo.FormFlowResolveTreeTest do
  @moduledoc """
  Exercises `FormFlow.Data.Templates.Flows.resolve_tree/1` against a real
  database: the tree a journey is derived against, loaded in three queries
  for the whole tree rather than five per flow in it
  (`archive/plans/next-position.md` §5.1).

  What is proven here is the shape the rest of the library reads - the
  map, each flow's nodes and relationships, each subflow node's `subflow`,
  each form node's `form` - and the query count, which is the whole point
  of the loader.
  """

  use Demo.DataCase, async: false

  alias FormFlow.Data.Instances
  alias FormFlow.Data.Repo, as: FormFlowRepo
  alias FormFlow.Data.Templates.Flow
  alias FormFlow.Data.Templates.Flows
  alias FormFlow.Data.Templates.Forms

  describe "resolve_tree/1" do
    test "returns the root's tree: flow, nodes, relationships, and a subtree per subflow step" do
      %{root: root, documents: documents, documents_node: documents_node} = nested_flow()

      tree = Flows.resolve_tree(root.id)

      assert %{flow: %Flow{id: root_id}, nodes: nodes, relationships: relationships} = tree
      assert root_id == root.id
      assert length(nodes) == 2
      assert length(relationships) == 1

      # The subtree sits under the step's node id, and is the child's own tree
      assert [documents_node_id] = Map.keys(tree.subflows)
      assert documents_node_id == documents_node.id

      subtree = tree.subflows[documents_node.id]
      assert subtree.flow.id == documents.id
      assert length(subtree.nodes) == 4
      assert length(subtree.relationships) == 3
      assert subtree.subflows == %{}
    end

    test "each flow carries its nodes and relationships, as get/1 loads them" do
      %{root: root, documents: documents, documents_node: documents_node} = nested_flow()

      tree = Flows.resolve_tree(root.id)

      # `tree.flow` is a loaded flow, not a bare row
      assert tree.flow.nodes == tree.nodes
      assert tree.flow.relationships == tree.relationships

      subtree = tree.subflows[documents_node.id]
      assert subtree.flow.nodes == subtree.nodes
      assert subtree.flow.relationships == subtree.relationships
      assert Enum.map(subtree.nodes, & &1.flow_id) |> Enum.uniq() == [documents.id]
    end

    test "a subflow step points at the flow it embeds; a form step at its form" do
      %{root: root, documents: documents, documents_node: documents_node} = nested_flow()

      tree = Flows.resolve_tree(root.id)

      step = Enum.find(tree.nodes, &(&1.id == documents_node.id))
      assert %Flow{id: id} = step.subflow
      assert id == documents.id

      for node <- tree.subflows[documents_node.id].nodes, node.form_id do
        assert %FormFlow.Data.Templates.Form{id: form_id} = node.form
        assert form_id == node.form_id
      end
    end

    test "nodes and relationships keep the order they were stored in" do
      {:ok, flow} = Flows.create(%{name: "Ordered"})

      first = build_node(flow, ["Start"], "Start")
      second = build_form_node(flow, "Second")
      third = build_form_node(flow, "Third")
      edge_a = edge(flow, first, second)
      edge_b = edge(flow, second, third)

      tree = Flows.resolve_tree(flow.id)

      assert Enum.map(tree.nodes, & &1.id) == [first.id, second.id, third.id]
      assert Enum.map(tree.relationships, & &1.id) == [edge_a.id, edge_b.id]
    end

    test "a subflow's id gives the tree from that flow down" do
      %{documents: documents} = nested_flow()

      tree = Flows.resolve_tree(documents.id)

      assert tree.flow.id == documents.id
      assert length(tree.nodes) == 4
      assert tree.subflows == %{}
    end

    test "an unknown id, and one that is not a UUID, resolve to nil" do
      assert Flows.resolve_tree(Ecto.UUID.generate()) == nil
      assert Flows.resolve_tree("not-a-uuid") == nil
    end

    test "a cyclic reference resolves to no subtree; a repeated sibling reference resolves at each step" do
      {:ok, root} = Flows.create(%{name: "Root", label: "subflows"})
      {:ok, child} = Flows.create(%{name: "Child", label: "subflows", owner_flow_id: root.id})

      # Child points back at the root: the cycle
      back = build_node(child, ["Subflow"], "Back", %{subflow_id: root.id})

      # The root embeds the child twice: the diamond
      once = build_node(root, ["Subflow"], "Once", %{subflow_id: child.id})
      twice = build_node(root, ["Subflow"], "Twice", %{subflow_id: child.id})

      tree = Flows.resolve_tree(root.id)

      assert Map.keys(tree.subflows) |> Enum.sort() == Enum.sort([once.id, twice.id])
      assert tree.subflows[once.id].flow.id == child.id
      assert tree.subflows[twice.id].flow.id == child.id
      assert tree.subflows[once.id].subflows == %{}
      assert Enum.any?(tree.subflows[once.id].nodes, &(&1.id == back.id))
    end

    test "a whole tree loads in three queries, whatever its depth" do
      %{root: root} = nested_flow()

      {tree, count} = counting_queries(fn -> Flows.resolve_tree(root.id) end)

      assert %{flow: %Flow{}} = tree
      assert count == 3
    end
  end

  describe "list_stranded/2" do
    test "takes the tree and instances a caller has loaded, and reads nothing when given both" do
      %{root: root, forms: [first | _rest]} = nested_flow()
      {:ok, journey} = Instances.Flows.create(%{template_flow_id: root.id, user_id: "dog_owner"})

      # An instance at a position the tree does not have: stranded
      {:ok, stranded} =
        FormFlowRepo.insert(
          Instances.Form.visit_changeset(
            %Instances.Form{},
            %{template_form_version_id: Forms.get_latest_version(first.form_id).id},
            journey.id,
            [Ecto.UUID.generate()]
          )
        )

      tree = Flows.resolve_tree(root.id)
      instances = Instances.Flows.form_instances(journey)

      {listed, count} =
        counting_queries(fn ->
          Instances.Flows.list_stranded(journey, tree: tree, form_instances: instances)
        end)

      assert Enum.map(listed, & &1.id) == [stranded.id]
      assert count == 0

      # The same answer with nothing passed
      assert Enum.map(Instances.Flows.list_stranded(journey), & &1.id) == [stranded.id]
    end
  end

  # ── fixtures ────────────────────────────────────────────────────────────

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

    edge(root, root_start, documents_node)

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

  # Runs `fun`, counting the queries the repo made meanwhile
  defp counting_queries(fun) do
    handler = "count-queries-#{System.unique_integer([:positive])}"
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler,
        [:demo, :repo, :query],
        fn _event, _measurements, _metadata, _config -> send(test_pid, :query) end,
        nil
      )

    result = fun.()
    :telemetry.detach(handler)

    {result, drain(0)}
  end

  defp drain(count) do
    receive do
      :query -> drain(count + 1)
    after
      0 -> count
    end
  end
end
