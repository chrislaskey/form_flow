defmodule DemoWeb.DemoLiveTest do
  use DemoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias DemoWeb.Experiences

  test "offers every experience, linked, in menu order", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/demo")

    listed =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#demo-experiences a")
      |> LazyHTML.attribute("href")

    assert listed == Enum.map(Experiences.all(), & &1.path)

    for experience <- Experiences.all() do
      assert html =~ experience.title
      assert html =~ experience.blurb
    end
  end

  test "names each side of the demo by kind, with its service name beside it", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/demo")

    headings =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#demo-experiences a div.font-semibold")
      |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))

    assert headings == [
             "Admin pages",
             "User pages - Pet License Applications",
             "Reviewer pages - Pet License Reviews"
           ]
  end

  test "carries the perspective picker", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/demo")

    assert has_element?(view, "#perspective")
    assert has_element?(view, "#perspective-user-switcher")
  end

  test "the header marks Demo app as the section being read", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/demo")

    current =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("header nav a.font-semibold")
      |> LazyHTML.text()
      |> String.trim()

    assert current == "Demo app"
  end

  describe "resetting the demo data" do
    @tag user: "admin"
    test "the admin is offered it here too", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/demo")

      assert has_element?(view, "#reset-demo button", "Reset demo data")
    end

    @tag user: "dog_owner"
    test "another perspective sees it too, and is refused on the click", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/demo")

      assert has_element?(view, "#reset-demo button", "Reset demo data")
      assert render_click(view, "reset_demo") =~ "Only the admin can reset"
    end

    @tag user: "admin"
    test "clicking it puts the shipped data back", %{conn: conn} do
      Demo.Repo.query!("PRAGMA defer_foreign_keys = ON")
      Enum.each(Demo.Snapshot.statements(), &Demo.Repo.query!(&1, [], log: false))

      Demo.Repo.query!("""
      INSERT INTO form_flow_template_flows
        (id, name, label, tenant_id, slug, status, properties, owner_flow_id, inserted_at, updated_at)
      SELECT 'built-by-a-visitor', 'Built by a visitor', label, tenant_id, 'built-by-a-visitor',
             status, properties, owner_flow_id, inserted_at, updated_at
      FROM form_flow_template_flows LIMIT 1
      """)

      {:ok, view, _html} = live(conn, ~p"/demo")

      assert view |> element("#reset-demo button") |> render_click() =~ "Demo data reset"

      %{rows: [[left_behind]]} =
        Demo.Repo.query!(
          "SELECT count(*) FROM form_flow_template_flows WHERE id = 'built-by-a-visitor'"
        )

      assert left_behind == 0
    end
  end
end
