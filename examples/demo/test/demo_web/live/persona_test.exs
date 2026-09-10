defmodule DemoWeb.PersonaTest do
  use DemoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Demo.Users
  alias DemoWeb.Experiences

  describe "the Demo Experience menu" do
    test "offers every experience, linked", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      menu = LazyHTML.from_fragment(html) |> LazyHTML.query("#experience-menu a")

      assert LazyHTML.attribute(menu, "href") == Enum.map(Experiences.all(), & &1.path)

      for experience <- Experiences.all() do
        assert html =~ experience.title
      end
    end

    test "replaced the Admin and Users links", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      labels =
        html
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("header nav > a")
        |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))

      assert labels == ["Home", "Docs"]
    end
  end

  describe "the admin experience" do
    @tag user: "admin"
    test "opens for the admin", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "#admin-pages")
    end

    @tag user: "dog_owner"
    test "refuses a pet owner, and says who it is for", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/admin")

      refute has_element?(view, "#admin-pages")
      assert html =~ "Not authorized"
      assert html =~ "Dog Owner"
      assert html =~ "Pet License Admin"
    end

    test "refuses the default user", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin")

      assert html =~ "Not authorized"
    end
  end

  describe "the user experience" do
    @tag user: "dog_owner"
    test "opens for a pet owner", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users")

      assert has_element?(view, "#users-pages")
    end

    @tag user: "reviewer"
    test "opens for the reviewer, who has no page of their own yet", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users")

      assert has_element?(view, "#users-pages")
    end

    @tag user: "admin"
    test "refuses the admin", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/users")

      refute has_element?(view, "#users-pages")
      assert html =~ "Not authorized"
    end
  end

  describe "the perspective picker" do
    test "is on the home page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#perspective")
      assert has_element?(view, "#perspective-user-switcher")
    end

    test "is what a refused page offers instead", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "#not-authorized-perspective")

      for user <- Users.all() do
        assert has_element?(view, ~s(a[href="/switch-user/#{user.id}"]))
      end
    end
  end
end
