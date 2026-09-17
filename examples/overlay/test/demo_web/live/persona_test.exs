defmodule DemoWeb.PersonaTest do
  use DemoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias DemoWeb.Experiences

  describe "the Demo Experience menu" do
    test "its label is a link to the page that describes the experiences", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      label =
        html
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("header nav div.group > a")

      assert LazyHTML.attribute(label, "href") == ["/demo"]
      assert label |> LazyHTML.text() |> String.trim() =~ "Demo app"
    end

    test "opens on hover and on focus, rather than on click", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      classes =
        html
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("header nav div.group > div")
        |> LazyHTML.attribute("class")
        |> hd()

      assert classes =~ "group-hover:visible"
      assert classes =~ "group-focus-within:visible"
      refute html =~ ~s(<details id="experience-menu")
    end

    test "offers every experience, linked", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      menu = LazyHTML.from_fragment(html) |> LazyHTML.query("#experience-menu a")

      assert LazyHTML.attribute(menu, "href") == Enum.map(Experiences.menu(), & &1.path)

      for experience <- Experiences.menu() do
        assert html =~ experience.title
      end
    end

    @tag user: "dog_owner"
    test "offers a pet owner only the overview and the pet license applications", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      menu = LazyHTML.from_fragment(html) |> LazyHTML.query("#experience-menu a")

      assert LazyHTML.attribute(menu, "href") == ["/demo", "/demo/pet-licenses/applications"]
    end

    @tag user: "reviewer"
    test "offers the reviewer only the overview and the pet license reviews", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      menu = LazyHTML.from_fragment(html) |> LazyHTML.query("#experience-menu a")

      assert LazyHTML.attribute(menu, "href") == ["/demo", "/demo/pet-licenses/reviews"]
    end

    @tag user: "docs_reader"
    test "offers a reader the overview alone", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      menu = LazyHTML.from_fragment(html) |> LazyHTML.query("#experience-menu a")

      assert LazyHTML.attribute(menu, "href") == ["/demo"]
    end

    @tag user: "dog_owner"
    test "the overview page still lists every side, whoever reads it", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/demo")

      listed = LazyHTML.from_fragment(html) |> LazyHTML.query("#demo-experiences a")

      assert LazyHTML.attribute(listed, "href") == Enum.map(Experiences.all(), & &1.path)
    end

    test "the overview leads it, before the three sides of the demo", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      titles =
        html
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#experience-menu a span:first-child")
        |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))

      assert titles == ["Overview" | Enum.map(Experiences.all(), & &1.title)]
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

  describe "the demo's pages" do
    test "sit under /demo, named for the pet licensing service" do
      assert Enum.map(Experiences.menu(), &{&1.title, &1.path}) == [
               {"Overview", "/demo"},
               {"Admin pages", "/demo/admin"},
               {"Pet License Applications", "/demo/pet-licenses/applications"},
               {"Pet License Reviews", "/demo/pet-licenses/reviews"}
             ]
    end

    test "each path opens its own page, titled as the menu names it", %{conn: conn} do
      for {path, region, title} <- [
            {"/demo/admin", "#admin-pages", "Admin"},
            {"/demo/pet-licenses/applications", "#users-pages", "Pet License Applications"},
            {"/demo/pet-licenses/reviews", "#reviewers-pages", "Pet License Reviews"}
          ] do
        {:ok, view, _html} = live(conn, path)

        assert has_element?(view, region)
        assert page_title(view) =~ title
      end
    end

    test "the overview is still its own page beside them", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/demo")

      assert has_element?(view, "#demo-experiences")
      refute has_element?(view, "#admin-pages")
    end

    test "the pages' own links carry the mount prefix", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/demo/admin")

      hrefs =
        html
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#admin-pages a[href^='/']")
        |> LazyHTML.attribute("href")

      assert hrefs != []
      assert Enum.all?(hrefs, &String.starts_with?(&1, "/demo/admin"))
    end

    test "the old top-level paths are gone", %{conn: conn} do
      for path <- ["/admin", "/users", "/reviewers"] do
        assert get(conn, path).status == 404
      end
    end
  end

  describe "the admin experience" do
    @tag user: "admin"
    test "opens for the admin", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/demo/admin")

      assert has_element?(view, "#admin-pages")
    end

    @tag user: "dog_owner"
    test "refuses a pet owner, and says who it is for", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/demo/admin")

      {:ok, owner} = Demo.Users.fetch("dog_owner")
      {:ok, admin} = Demo.Users.fetch("admin")

      refute has_element?(view, "#admin-pages")
      assert html =~ "Not authorized"
      assert html =~ owner.name
      assert html =~ admin.name
    end

    test "opens for the default user, who is the admin", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/demo/admin")

      assert has_element?(view, "#admin-pages")
    end
  end

  describe "the user experience" do
    @tag user: "dog_owner"
    test "opens for a pet owner", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/demo/pet-licenses/applications")

      assert has_element?(view, "#users-pages")
    end

    @tag user: "admin"
    test "opens for the admin, as the user sees it", %{conn: conn} do
      {:ok, view, admin_html} = live(conn, ~p"/demo/pet-licenses/applications")

      assert has_element?(view, "#users-pages")

      {:ok, _view, owner_html} =
        live(build_conn_as("dog_owner"), ~p"/demo/pet-licenses/applications")

      admin_page = page(admin_html, "#users-pages")

      assert admin_page =~ ~r/\S/
      assert admin_page == page(owner_html, "#users-pages")
    end

    @tag user: "docs_reader"
    test "refuses a reader, and names the admin among those who can", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/demo/pet-licenses/applications")

      {:ok, admin} = Demo.Users.fetch("admin")

      refute has_element?(view, "#users-pages")
      assert html =~ "Not authorized"
      assert html =~ admin.name
    end
  end

  describe "the reviewer experience" do
    @tag user: "reviewer"
    test "opens for the reviewer", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/demo/pet-licenses/reviews")

      assert has_element?(view, "#reviewers-pages")
    end

    @tag user: "admin"
    test "opens for the admin, as the reviewer sees it", %{conn: conn} do
      {:ok, view, admin_html} = live(conn, ~p"/demo/pet-licenses/reviews")

      assert has_element?(view, "#reviewers-pages")

      {:ok, _view, reviewer_html} =
        live(build_conn_as("reviewer"), ~p"/demo/pet-licenses/reviews")

      admin_page = page(admin_html, "#reviewers-pages")

      assert admin_page =~ ~r/\S/
      assert admin_page == page(reviewer_html, "#reviewers-pages")
    end

    @tag user: "dog_owner"
    test "refuses a pet owner", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/demo/pet-licenses/reviews")

      refute has_element?(view, "#reviewers-pages")
      assert html =~ "Not authorized"
    end
  end

  describe "a refused page" do
    @tag user: "dog_owner"
    test "still says which page it was", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/demo/admin")

      headings =
        html
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("h1, h2")
        |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))

      assert [refusal] = headings
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
      {:ok, view, html} = live(conn, ~p"/demo/admin")

      assert html =~ "Not authorized"
      assert html =~ "Viewing as"

      # The header's switcher is the only one on the page
      switchers =
        html
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("[id$='user-switcher']")
        |> LazyHTML.attribute("id")

      assert switchers == ["header-user-switcher"]
      refute has_element?(view, "#perspective")
    end
  end

  describe "the mobile nav" do
    test "lists every page flat, with no menu inside it", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      links =
        html
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#mobile-nav a")

      assert LazyHTML.attribute(links, "href") ==
               ["/", "/docs"] ++
                 Enum.map(Experiences.menu(), & &1.path) ++
                 ["https://github.com/chrislaskey/form_flow"]

      assert links |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim())) ==
               ["Home", "Docs"] ++ Enum.map(Experiences.menu(), & &1.title) ++ ["GitHub"]

      # Nothing to open inside it: the desktop's hover menu is flattened here
      nested = LazyHTML.query(LazyHTML.from_fragment(html), "#mobile-nav details")

      assert Enum.empty?(nested)
    end

    @tag user: "dog_owner"
    test "lists only the demo pages the current user can open", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      links =
        html
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#mobile-nav a")

      assert LazyHTML.attribute(links, "href") ==
               [
                 "/",
                 "/docs",
                 "/demo",
                 "/demo/pet-licenses/applications",
                 "https://github.com/chrislaskey/form_flow"
               ]
    end

    test "carries the source link, which the header only shows on a wide screen", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      document = LazyHTML.from_fragment(html)

      source = LazyHTML.query(document, "#mobile-nav a[href^='https://github.com']")
      assert source |> LazyHTML.text() |> String.trim() == "GitHub"

      # The same destination, as a mark, for the width the mobile nav is not on
      mark = LazyHTML.query(document, "header > div > div > a[href^='https://github.com']")
      assert mark |> LazyHTML.attribute("class") |> hd() =~ "hidden sm:block"
    end

    test "marks the page being read", %{conn: conn} do
      for {path, title} <- [{"/", "Home"}, {"/docs", "Docs"}, {"/demo", "Overview"}] do
        {:ok, _view, html} = live(conn, path)

        current =
          html
          |> LazyHTML.from_fragment()
          |> LazyHTML.query("#mobile-nav a[aria-current='page']")

        assert current |> LazyHTML.text() |> String.trim() == title
      end
    end

    test "is the nav on a narrow screen, and the header's is on a wide one", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      document = LazyHTML.from_fragment(html)

      assert document
             |> LazyHTML.query("header nav[aria-label='Menu']")
             |> LazyHTML.attribute("class") ==
               ["sm:hidden"]

      assert document
             |> LazyHTML.query("header nav:not([aria-label])")
             |> LazyHTML.attribute("class")
             |> hd() =~ "hidden"
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
