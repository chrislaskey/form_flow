defmodule DemoWeb.DocsLive.DataModelingLiveTest do
  use DemoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias DemoWeb.DocsComponents
  alias DemoWeb.DocsLive.DataModelingLive.Diagram
  alias DemoWeb.DocsLive.DataModelingLive.GraphSchema
  alias DemoWeb.DocsLive.DataModelingLive.SqlExamples

  test "draws one node per table FormFlow's schemas define", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/docs/data-modeling")

    drawn = view |> diagram() |> Map.fetch!("nodes") |> Enum.map(& &1["id"])

    assert Enum.sort(drawn) == Enum.sort(form_flow_tables())
  end

  test "stars the five tables the rest support", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/docs/data-modeling")

    starred =
      for node <- view |> diagram() |> Map.fetch!("nodes"),
          node["data"]["primary"],
          do: node["id"]

    assert Enum.sort(starred) == [
             "form_flow_instance_flows",
             "form_flow_instance_forms",
             "form_flow_template_flow_nodes",
             "form_flow_template_flows",
             "form_flow_template_forms"
           ]
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

  test "draws the graph schema with the same node type as the SQL schema", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/docs/data-modeling")

    %{"nodes" => nodes, "edges" => edges} = diagram(view, "graph-diagram")

    # Only the graph half of the templates crosses over — a node, a
    # relationship between two nodes, and the flow they belong to
    assert Enum.map(nodes, & &1["data"]["table"]) |> Enum.sort() == [
             "form_flow_template_flow_nodes",
             "form_flow_template_flow_relationships",
             "form_flow_template_flows"
           ]

    assert Enum.all?(nodes, &(&1["type"] == "table"))

    # Neo4j has no primary or foreign keys, so no row carries a key badge
    for node <- nodes, column <- node["data"]["columns"] do
      assert column["key"] == nil
    end

    columns =
      Map.new(nodes, &{&1["id"], Map.new(&1["data"]["columns"], fn c -> {c["name"], c} end)})

    for edge <- edges do
      assert columns[edge["source"]][edge["sourceHandle"]]["handle"] == "source"
      assert columns[edge["target"]][edge["targetHandle"]]["handle"] == "target"
    end

    # The reserved types are the dashed ones: a property says it, so no
    # relationship row holds it
    dashed = for edge <- edges, edge["style"]["strokeDasharray"], do: edge["label"]

    assert Enum.sort(dashed) == ["EMBEDS", "IN", "OWNED_BY"]
  end

  test "the docs nav offers every page under /docs", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/docs/data-modeling")

    listed =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#docs-nav a:not([href^='#'])")
      |> LazyHTML.attribute("href")

    # The nav heads the list with /docs itself
    assert listed == ["/docs" | Enum.map(DocsComponents.pages(), & &1.path)]
  end

  test "the nav's section list and the headings are the same list", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/docs/data-modeling")

    page = LazyHTML.from_fragment(html)
    links = LazyHTML.query(page, "#docs-nav a[href^='#']")

    ids = links |> LazyHTML.attribute("href") |> Enum.map(&String.trim_leading(&1, "#"))
    titles = Enum.map(links, &(&1 |> LazyHTML.text() |> String.trim()))

    assert "introduction" in ids

    # Every nav entry points at a heading that says the same thing and links
    # to itself
    for {id, title} <- Enum.zip(ids, titles) do
      heading = LazyHTML.query_by_id(page, id)

      assert LazyHTML.tag(heading) == ["h2"]
      assert LazyHTML.text(heading) =~ title
      assert heading |> LazyHTML.query("a") |> LazyHTML.attribute("href") == ["#" <> id]
    end

    # ...and no heading is missing from the nav, in order
    assert page |> LazyHTML.query("h2") |> LazyHTML.attribute("id") == ids
  end

  test "prints every query example, in full", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/docs/data-modeling")

    for example <- SqlExamples.all() do
      block = render(element(view, "#sql-#{example.id}"))

      assert block =~ example.title
      assert block =~ "<pre"
    end

    # The three options, then FormFlow's own, whose tables are the ones the
    # diagram draws
    assert html =~ "JOIN edges"
    assert html =~ "WITH RECURSIVE"
    assert html =~ "MATCH ("

    form_flow = render(element(view, "#sql-form-flow"))

    assert form_flow =~ "form_flow_template_flow_nodes"
    assert form_flow =~ "form_flow_template_flow_relationships"

    refute html =~ "NOTE:"
  end

  test "lists each reserved relationship type with the column behind it", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/docs/data-modeling")

    html = render(element(view, "#structural-types"))

    for type <- GraphSchema.structural_types() do
      assert html =~ type.type
      assert html =~ type.derived_from
    end
  end

  # The nodes and edges the hook is handed, out of the container's
  # data-diagram attribute
  defp diagram(view, id \\ "schema-diagram") do
    view
    |> element("##{id}")
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query_by_id(id)
    |> LazyHTML.attribute("data-diagram")
    |> hd()
    |> Jason.decode!()
  end

  # Derived the long way round on purpose: the diagram's table list is written
  # by hand, since ReactFlow has no layout of its own and each table needs a
  # position. Reading the same list back would prove nothing, so the test asks
  # the form_flow application which of its modules are Ecto schemas.
  # Schemas with a source — an embedded one (`Form.Prefill`, stored inside a
  # column) names no table, and the diagram draws tables
  defp form_flow_tables do
    {:ok, modules} = :application.get_key(:form_flow, :modules)

    for module <- modules,
        Code.ensure_loaded?(module),
        function_exported?(module, :__schema__, 1),
        table = module.__schema__(:source),
        do: table
  end
end
