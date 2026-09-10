defmodule DemoWeb.DataModelingLiveTest do
  use DemoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias DemoWeb.DataModelingLive.Diagram

  test "draws one node per table FormFlow's schemas define", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/docs/data-modeling")

    drawn = view |> diagram() |> Map.fetch!("nodes") |> Enum.map(& &1["id"])

    assert Enum.sort(drawn) == Enum.sort(form_flow_tables())
  end

  test "every column carries a Postgres type", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/docs/data-modeling")

    for node <- view |> diagram() |> Map.fetch!("nodes"),
        column <- node["data"]["columns"] do
      assert column["type"] not in [nil, ""],
             "#{node["id"]}.#{column["name"]} has no Postgres type"
    end
  end

  test "every edge attaches to a column that has a handle for it", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/docs/data-modeling")

    %{"nodes" => nodes, "edges" => edges} = diagram(view)

    columns =
      Map.new(nodes, &{&1["id"], Map.new(&1["data"]["columns"], fn c -> {c["name"], c} end)})

    assert length(edges) == length(Diagram.foreign_keys())

    for edge <- edges do
      assert columns[edge["source"]][edge["sourceHandle"]]["handle"] == "source",
             "#{edge["id"]} leaves a column with no source handle"

      assert columns[edge["target"]][edge["targetHandle"]]["handle"] == "target",
             "#{edge["id"]} arrives at a column with no target handle"
    end
  end

  test "lists every foreign key with its ON DELETE rule", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/docs/data-modeling")

    html = render(element(view, "#foreign-keys"))

    for key <- Diagram.foreign_keys() do
      assert html =~ key.column
      assert html =~ key.references
      assert html =~ key.on_delete
    end
  end

  test "names the CDN packages the canvas is built on", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/docs/data-modeling")

    html = render(element(view, "#cdn-sources"))

    assert html =~ "react"
    assert html =~ "reactflow"
    assert html =~ "cdn.jsdelivr.net"
  end

  # The nodes and edges the hook is handed, out of the container's
  # data-diagram attribute
  defp diagram(view) do
    view
    |> element("#schema-diagram")
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query_by_id("schema-diagram")
    |> LazyHTML.attribute("data-diagram")
    |> hd()
    |> Jason.decode!()
  end

  # Derived the long way round on purpose: the diagram's table list is written
  # by hand, since ReactFlow has no layout of its own and each table needs a
  # position. Reading the same list back would prove nothing, so the test asks
  # the form_flow application which of its modules are Ecto schemas.
  defp form_flow_tables do
    {:ok, modules} = :application.get_key(:form_flow, :modules)

    for module <- modules,
        Code.ensure_loaded?(module),
        function_exported?(module, :__schema__, 1),
        do: module.__schema__(:source)
  end
end
