defmodule FormFlow.Data.Templates.Flows.ConnectedTreeTest do
  @moduledoc """
  `FormFlow.Data.Templates.Flows.connected_tree/1` over hand-built trees —
  pure structs, no database, the way `FormFlow.Data.Instances.FlowProgressTest`
  builds its fixtures. The rule under test is the one the overview draws
  with: a node counts when a Start node reaches it forward along the flow's
  relationships, at every level.
  """

  use ExUnit.Case, async: true

  alias FormFlow.Data.Templates.Flow
  alias FormFlow.Data.Templates.Flows

  defp build_node(labels, opts \\ []) do
    %Flow.Node{
      id: Ecto.UUID.generate(),
      labels: labels,
      form_id: Keyword.get(opts, :form_id),
      subflow_id: Keyword.get(opts, :subflow_id),
      properties: %{"data" => %{"label" => Keyword.get(opts, :label)}}
    }
  end

  defp form_node(label), do: build_node(["Form"], form_id: Ecto.UUID.generate(), label: label)

  defp subflow_node(label, subflow_id) do
    build_node(["Subflow"], subflow_id: subflow_id, label: label)
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

  defp ids(records), do: Enum.map(records, & &1.id)

  test "keeps a fully connected flow as it is" do
    start = build_node(["Start"])
    name = form_node("Name")
    stop = build_node(["End"])
    edges = [edge(start, name), edge(name, stop)]
    tree = tree([start, name, stop], edges)

    assert Flows.connected_tree(tree) == tree
  end

  test "drops nodes no Start reaches, and their relationships" do
    start = build_node(["Start"])
    name = form_node("Name")
    stop = build_node(["End"])
    # Wired only towards End: a user can never get here
    dangling = form_node("Dangling")
    # Wired to nothing at all
    loose = form_node("Loose")

    edges = [edge(start, name), edge(name, stop), edge(dangling, stop)]
    narrowed = Flows.connected_tree(tree([start, name, dangling, loose, stop], edges))

    assert ids(narrowed.nodes) == ids([start, name, stop])
    assert ids(narrowed.relationships) == ids(Enum.take(edges, 2))
  end

  test "keeps a node with an unconnected predecessor when Start also reaches it" do
    start = build_node(["Start"])
    name = form_node("Name")
    stop = build_node(["End"])
    dangling = form_node("Dangling")

    edges = [edge(start, name), edge(name, stop), edge(dangling, name)]
    narrowed = Flows.connected_tree(tree([start, name, dangling, stop], edges))

    assert ids(narrowed.nodes) == ids([start, name, stop])
    # The edge from the dropped node goes with it
    assert ids(narrowed.relationships) == ids(Enum.take(edges, 2))
  end

  test "narrows subflows recursively, and drops the subtree of an unreachable subflow node" do
    inner_start = build_node(["Start"])
    inner_form = form_node("Inner")
    inner_loose = form_node("Inner loose")
    inner_stop = build_node(["End"])

    inner =
      tree(
        [inner_start, inner_form, inner_loose, inner_stop],
        [edge(inner_start, inner_form), edge(inner_form, inner_stop)],
        %{},
        %Flow{id: Ecto.UUID.generate(), name: "Application", label: "forms"}
      )

    start = build_node(["Start"])
    reached = subflow_node("Application", inner.flow.id)
    unreached = subflow_node("Orphan", Ecto.UUID.generate())
    stop = build_node(["End"])

    outer =
      tree(
        [start, reached, unreached, stop],
        [edge(start, reached), edge(reached, stop)],
        %{reached.id => inner, unreached.id => inner}
      )

    narrowed = Flows.connected_tree(outer)

    assert ids(narrowed.nodes) == ids([start, reached, stop])
    assert Map.keys(narrowed.subflows) == [reached.id]
    assert ids(narrowed.subflows[reached.id].nodes) == ids([inner_start, inner_form, inner_stop])
  end

  test "an unresolved subflow (a reference cycle) stays nil under its node" do
    start = build_node(["Start"])
    cyclic = subflow_node("Cyclic", Ecto.UUID.generate())

    narrowed =
      Flows.connected_tree(tree([start, cyclic], [edge(start, cyclic)], %{cyclic.id => nil}))

    assert narrowed.subflows == %{cyclic.id => nil}
  end

  test "survives a cycle among the nodes" do
    start = build_node(["Start"])
    a = form_node("A")
    b = form_node("B")

    edges = [edge(start, a), edge(a, b), edge(b, a)]
    narrowed = Flows.connected_tree(tree([start, a, b], edges))

    assert ids(narrowed.nodes) == ids([start, a, b])
    assert length(narrowed.relationships) == 3
  end

  test "a flow with no Start node has nothing connected" do
    a = form_node("A")
    b = form_node("B")

    narrowed = Flows.connected_tree(tree([a, b], [edge(a, b)]))

    assert narrowed.nodes == []
    assert narrowed.relationships == []
  end

  test "nil in, nil out" do
    assert Flows.connected_tree(nil) == nil
  end
end
