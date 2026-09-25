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

    test "offers every side to every user, whoever is viewing", %{conn: _conn} do
      for user <- ["admin", "dog_owner", "cat_owner", "reviewer", "docs_reader"] do
        {:ok, _view, html} = live(build_conn_as(user), ~p"/")

        menu = LazyHTML.from_fragment(html) |> LazyHTML.query("#experience-menu a")

        assert LazyHTML.attribute(menu, "href") == Enum.map(Experiences.menu(), & &1.path),
               "the menu was filtered for #{user}"
      end
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
               {"Pet License Reviews", "/demo/pet-licenses/reviews"},
               {"Other Forms", "/demo/other-forms"}
             ]
    end

    test "each path opens its own page, for the user it is for, titled as the menu names it" do
      for {user, path, region, title} <- [
            {"admin", "/demo/admin", "#admin-pages", "Admin"},
            {"dog_owner", "/demo/pet-licenses/applications", "#users-pages",
             "Pet License Applications"},
            {"reviewer", "/demo/pet-licenses/reviews", "#reviewers-pages", "Pet License Reviews"},
            {"dog_owner", "/demo/other-forms", "#other-forms-pages", "Other Forms"}
          ] do
        {:ok, view, _html} = live(build_conn_as(user), path)

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
    test "switches a pet owner to the admin rather than refusing them", %{conn: conn} do
      assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/demo/admin")
      assert to == "/view-as/admin?return_to=%2Fdemo%2Fadmin"

      {:ok, view, _html} = live(follow_switch(conn, to), ~p"/demo/admin")
      assert has_element?(view, "#admin-pages")
    end

    test "opens for the default user, who is the admin", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/demo/admin")

      assert has_element?(view, "#admin-pages")
    end
  end

  describe "the other forms experience" do
    @tag user: "cat_owner"
    test "opens for a pet owner", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/demo/other-forms")

      assert has_element?(view, "#other-forms-pages")
    end

    @tag user: "reviewer"
    test "switches the reviewer to the dog owner", %{conn: conn} do
      assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/demo/other-forms")
      assert to == "/view-as/dog_owner?return_to=%2Fdemo%2Fother-forms"
    end

    @tag user: "cat_owner"
    test "leaves the cat owner as they are - an owner is who this page is for",
         %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/demo/other-forms")

      {:ok, cat_owner} = Demo.Users.fetch("cat_owner")

      assert has_element?(view, "#other-forms-pages")
      assert html =~ cat_owner.name
    end
  end

  describe "the user experience" do
    @tag user: "dog_owner"
    test "opens for a pet owner", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/demo/pet-licenses/applications")

      assert has_element?(view, "#users-pages")
    end

    @tag user: "admin"
    test "switches the admin to the dog owner, perspectives notwithstanding", %{conn: conn} do
      # The admin carries the "applicant" perspective, so a perspective test
      # would leave them here as themselves. Fit is the role.
      {:ok, admin} = Demo.Users.fetch("admin")
      assert "applicant" in admin.perspectives

      assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/demo/pet-licenses/applications")
      assert to == "/view-as/dog_owner?return_to=%2Fdemo%2Fpet-licenses%2Fapplications"
    end

    @tag user: "docs_reader"
    test "switches a reader to the dog owner", %{conn: conn} do
      assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/demo/pet-licenses/applications")
      assert to == "/view-as/dog_owner?return_to=%2Fdemo%2Fpet-licenses%2Fapplications"
    end

    @tag user: "cat_owner"
    test "leaves the cat owner as they are, so a switch made by hand sticks", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/demo/pet-licenses/applications")

      {:ok, cat_owner} = Demo.Users.fetch("cat_owner")

      assert has_element?(view, "#users-pages")
      assert html =~ cat_owner.name
    end
  end

  describe "the reviewer experience" do
    @tag user: "reviewer"
    test "opens for the reviewer", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/demo/pet-licenses/reviews")

      assert has_element?(view, "#reviewers-pages")
    end

    @tag user: "admin"
    test "switches the admin to the reviewer, perspectives notwithstanding", %{conn: conn} do
      # The admin carries the "reviewer" perspective too
      {:ok, admin} = Demo.Users.fetch("admin")
      assert "reviewer" in admin.perspectives

      assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/demo/pet-licenses/reviews")
      assert to == "/view-as/reviewer?return_to=%2Fdemo%2Fpet-licenses%2Freviews"

      {:ok, view, _html} = live(follow_switch(conn, to), ~p"/demo/pet-licenses/reviews")
      assert has_element?(view, "#reviewers-pages")
    end

    @tag user: "dog_owner"
    test "switches a pet owner to the reviewer", %{conn: conn} do
      assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/demo/pet-licenses/reviews")
      assert to == "/view-as/reviewer?return_to=%2Fdemo%2Fpet-licenses%2Freviews"
    end
  end

  describe "opening a side of the demo you are not" do
    @tag user: "dog_owner"
    test "keeps the deep link, so the switch lands where the click was going",
         %{conn: conn} do
      assert {:error, {:redirect, %{to: to}}} =
               live(conn, ~p"/demo/pet-licenses/reviews/some-journey-id")

      assert to ==
               "/view-as/reviewer?return_to=%2Fdemo%2Fpet-licenses%2Freviews%2Fsome-journey-id"

      assert redirected_to(get(conn, to)) == "/demo/pet-licenses/reviews/some-journey-id"
    end

    @tag user: "dog_owner"
    test "the switch writes the session, so the page opens on the way back", %{conn: conn} do
      switched = get(conn, "/view-as/reviewer?return_to=%2Fdemo%2Fpet-licenses%2Freviews")

      assert Plug.Conn.get_session(switched, Demo.Users.session_key()) == "reviewer"
      assert redirected_to(switched) == "/demo/pet-licenses/reviews"
    end

    test "refuses to send the visitor off this site", %{conn: conn} do
      {:ok, reviewer} = Demo.Users.fetch("reviewer")

      for elsewhere <- ["https://evil.test/x", "//evil.test/x", "evil.test"] do
        to = "/view-as/reviewer?return_to=" <> URI.encode_www_form(elsewhere)

        assert redirected_to(get(conn, to)) == reviewer.landing,
               "#{elsewhere} was followed"
      end
    end

    test "an unknown user changes nothing and says so", %{conn: conn} do
      switched = get(conn, "/view-as/nobody?return_to=%2Fdemo")

      assert redirected_to(switched) == "/demo"
      assert Phoenix.Flash.get(switched.assigns.flash, :error) =~ "does not exist"
    end
  end

  describe "the perspective picker" do
    test "is on the home page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#perspective")
      assert has_element?(view, "#perspective-user-switcher")
    end

    @tag user: "dog_owner"
    test "is the header's alone on a demo page, not repeated inside it", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/demo/pet-licenses/applications")

      assert html =~ "Viewing as"

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

    test "lists every demo page to every user, whoever is viewing", %{conn: _conn} do
      expected =
        ["/", "/docs"] ++
          Enum.map(Experiences.menu(), & &1.path) ++
          ["https://github.com/chrislaskey/form_flow"]

      for user <- ["admin", "dog_owner", "cat_owner", "reviewer", "docs_reader"] do
        {:ok, _view, html} = live(build_conn_as(user), ~p"/")

        links =
          html
          |> LazyHTML.from_fragment()
          |> LazyHTML.query("#mobile-nav a")

        assert LazyHTML.attribute(links, "href") == expected,
               "the mobile nav was filtered for #{user}"
      end
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

  # The visitor after following the switch the entry hook sent them to: a
  # conn carrying the session that switch wrote, ready to open the page the
  # click was going to.
  defp follow_switch(conn, to) do
    switched = get(conn, to)

    build_conn_as(Plug.Conn.get_session(switched, Demo.Users.session_key()))
  end
end
