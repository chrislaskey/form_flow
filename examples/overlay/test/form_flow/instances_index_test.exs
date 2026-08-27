defmodule Demo.FormFlowInstancesIndexTest do
  @moduledoc """
  Exercises the user-facing flow listing's `Slab.table` against a real
  database — query mode, so the sorting and pagination the URL asks for have
  to compile into real SQL rather than being applied to a list in memory.

  The template indexes get the same treatment in `flows_crud_test.exs` and
  `forms_crud_test.exs`; this is the third of the three, and the one whose
  rows carry a preloaded association Slab resolves after counting.

  Two things to know about asserting on these. Slab keeps its `id` on the
  LiveComponent and derives ids for the parts it renders, so the table's
  presence is probed through one of those — here the page-size control the
  `<:pagination>` slot brings — rather than through the id passed to it, the
  same trick `install_check_live_test.exs` documents. And
  presence of a *row* is asserted through the instance id in its link: a
  flow's name also appears in the "start a new flow" picker beside the table,
  so matching on names alone would pass with no row rendered at all.
  """

  @table "#flow-instances-table-per-page"

  use DemoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias FormFlow.Data.Instances
  alias FormFlow.Data.Templates.Flows

  test "lists the current user's flow instances, newest first", %{conn: conn} do
    older = start_flow("Older", "demo-user")
    newer = start_flow("Newer", "demo-user")

    {:ok, view, html} = live(conn, "/users/flows")

    assert has_element?(view, @table)
    assert has_element?(view, row_link(older), "Older")
    assert has_element?(view, row_link(newer), "Newer")
    assert row_order(html, [newer, older]) == :in_order
  end

  test "the flow's name comes from the preloaded template", %{conn: conn} do
    instance = start_flow("Benefits Application", "demo-user")

    {:ok, view, _html} = live(conn, "/users/flows")

    # A joined value, rendered per row — so the preload survived Slab's count
    assert has_element?(view, row_link(instance), "Benefits Application")
  end

  test "another user's instances are not listed", %{conn: conn} do
    mine = start_flow("Mine", "demo-user")
    theirs = start_flow("Theirs", "someone-else")

    {:ok, _view, html} = live(conn, "/users/flows")

    assert html =~ mine.id
    refute html =~ theirs.id
  end

  test "an empty listing says so instead of drawing a table", %{conn: conn} do
    {:ok, view, html} = live(conn, "/users/flows")

    refute has_element?(view, @table)
    assert html =~ "Nothing started yet"
  end

  test "the URL's sort compiles into the query", %{conn: conn} do
    older = start_flow("Older", "demo-user")
    newer = start_flow("Newer", "demo-user")

    {:ok, _view, html} = live(conn, "/users/flows?sort=inserted_at&sort_direction=asc")

    assert row_order(html, [older, newer]) == :in_order
  end

  test "pagination splits the rows instead of rendering them all", %{conn: conn} do
    instances = for i <- 1..11, do: start_flow("Flow #{i}", "demo-user")

    {:ok, _view, page_one} = live(conn, "/users/flows")
    {:ok, _view, page_two} = live(conn, "/users/flows?page=2")

    assert rows_on_page(page_one, instances) == 10
    assert rows_on_page(page_two, instances) == 1
  end

  test "the start-a-flow picker is a plain list beside the table", %{conn: conn} do
    {:ok, flow} = Flows.create(%{name: "Startable"})

    {:ok, view, _html} = live(conn, "/users/flows")

    view |> element("button[phx-value-flow-id='#{flow.id}']") |> render_click()

    assert {path, _flash} = assert_redirect(view)
    assert path =~ ~r|^/users/flows/[0-9a-f-]{36}$|
  end

  defp row_link(instance), do: "a[href='/users/flows/#{instance.id}']"

  defp start_flow(name, user_id) do
    {:ok, flow} = Flows.create(%{name: name})
    {:ok, instance} = Instances.Flows.create(%{flow_id: flow.id, user_id: user_id})

    instance
  end

  # Whether the rows appear in the order listed. Ids reach the page through
  # each row's link, so their positions are the row order.
  defp row_order(html, instances) do
    positions =
      for instance <- instances do
        case :binary.match(html, instance.id) do
          {position, _length} -> position
          :nomatch -> flunk("no row rendered for #{instance.id}")
        end
      end

    if positions == Enum.sort(positions), do: :in_order, else: :out_of_order
  end

  defp rows_on_page(html, instances) do
    Enum.count(instances, &String.contains?(html, &1.id))
  end
end
