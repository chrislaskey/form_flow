defmodule DemoWeb.HomeLiveTest do
  use DemoWeb.ConnCase

  import Phoenix.LiveViewTest

  test "renders the demo index", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "FormFlow demo"
    assert has_element?(view, "#form-flow-version")
    assert has_element?(view, "#perspective")
  end

  test "reports the compiled form_flow version", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    version = to_string(Application.spec(:form_flow, :vsn))

    assert version != ""
    assert render(element(view, "#form-flow-version")) =~ version
  end

  test "renders the README's pitch", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "Why FormFlow?"
    assert html =~ "forms as data"
    assert has_element?(view, "#how-do-i-use-it")
    assert has_element?(view, "#how-is-form-flow-built")
  end

  describe "resetting the demo data" do
    @tag user: "admin"
    test "the admin is offered it", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#reset-demo button", "Reset demo data")
    end

    @tag user: "dog_owner"
    test "another perspective sees it too, and is refused on the click", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

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

      {:ok, view, _html} = live(conn, ~p"/")

      html = view |> element("#reset-demo button") |> render_click()

      assert html =~ "Demo data reset"

      %{rows: [[left_behind]]} =
        Demo.Repo.query!(
          "SELECT count(*) FROM form_flow_template_flows WHERE id = 'built-by-a-visitor'"
        )

      assert left_behind == 0
    end

    @tag user: "dog_owner"
    test "another perspective cannot push the event either", %{conn: conn} do
      Enum.each(Demo.Snapshot.statements(), &Demo.Repo.query!(&1, [], log: false))
      before = Demo.Repo.query!("SELECT count(*) FROM form_flow_template_flows").rows

      {:ok, view, _html} = live(conn, ~p"/")

      assert render_click(view, "reset_demo") =~ "Only the admin can reset"
      assert Demo.Repo.query!("SELECT count(*) FROM form_flow_template_flows").rows == before
    end
  end

  test "is the only route at the root: nothing falls through to it", %{conn: conn} do
    assert get(conn, "/flows").status == 404
  end
end
