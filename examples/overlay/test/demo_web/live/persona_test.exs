defmodule DemoWeb.PersonaTest do
  use DemoWeb.ConnCase

  import Phoenix.LiveViewTest

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

      {:ok, owner} = Demo.Users.fetch("dog_owner")
      {:ok, admin} = Demo.Users.fetch("admin")

      refute has_element?(view, "#admin-pages")
      assert html =~ "Not authorized"
      assert html =~ owner.name
      assert html =~ admin.name
    end

    test "opens for the default user, who is the admin", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")

      assert has_element?(view, "#admin-pages")
    end
  end

  describe "the user experience" do
    @tag user: "dog_owner"
    test "opens for a pet owner", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users")

      assert has_element?(view, "#users-pages")
    end

    @tag user: "admin"
    test "opens for the admin, as the user sees it", %{conn: conn} do
      {:ok, view, admin_html} = live(conn, ~p"/users")

      assert has_element?(view, "#users-pages")

      {:ok, _view, owner_html} = live(build_conn_as("dog_owner"), ~p"/users")

      admin_page = page(admin_html, "#users-pages")

      assert admin_page =~ ~r/\S/
      assert admin_page == page(owner_html, "#users-pages")
    end

    @tag user: "docs_reader"
    test "refuses a reader, and names the admin among those who can", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/users")

      {:ok, admin} = Demo.Users.fetch("admin")

      refute has_element?(view, "#users-pages")
      assert html =~ "Not authorized"
      assert html =~ admin.name
    end
  end

  describe "the reviewer experience" do
    @tag user: "reviewer"
    test "opens for the reviewer", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/reviewers")

      assert has_element?(view, "#reviewers-pages")
    end

    @tag user: "admin"
    test "opens for the admin, as the reviewer sees it", %{conn: conn} do
      {:ok, view, admin_html} = live(conn, ~p"/reviewers")

      assert has_element?(view, "#reviewers-pages")

      {:ok, _view, reviewer_html} = live(build_conn_as("reviewer"), ~p"/reviewers")

      admin_page = page(admin_html, "#reviewers-pages")

      assert admin_page =~ ~r/\S/
      assert admin_page == page(reviewer_html, "#reviewers-pages")
    end

    @tag user: "dog_owner"
    test "refuses a pet owner", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/reviewers")

      refute has_element?(view, "#reviewers-pages")
      assert html =~ "Not authorized"
    end
  end

  describe "a refused page" do
    @tag user: "dog_owner"
    test "still says which page it was", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin")

      headings =
        html
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("h1, h2")
        |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))

      assert [title, refusal] = headings
      assert title == "Admin pages"
      assert refusal =~ "Not authorized"
    end
  end

  describe "the perspective picker" do
    test "is on the home page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#perspective")
      assert has_element?(view, "#perspective-user-switcher")
    end

    @tag user: "dog_owner"
    test "is not repeated on a refusal, which points at the header instead", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/admin")

      assert html =~ "Not authorized"
      assert html =~ "Viewing as"

      # The header's switcher is the only one on the page
      switchers =
        html
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("details.dropdown")
        |> LazyHTML.attribute("id")

      assert switchers == ["experience-menu", "header-user-switcher"]
      refute has_element?(view, "#perspective")
    end
  end

  # One region of a render, as text — what an admin sees on another role's
  # page, to compare against what that role sees.
  defp page(html, selector) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(selector)
    |> LazyHTML.text()
  end
end
