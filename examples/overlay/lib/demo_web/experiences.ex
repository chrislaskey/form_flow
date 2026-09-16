defmodule DemoWeb.Experiences do
  @moduledoc """
  The three sides of the demo, and the page that introduces them.

  `all/0` is the three sides; `menu/0` puts `overview/0` in front of them, and
  is what the header's Demo app menu and the mobile nav list. The overview is
  not a fourth side of the demo — it is the page those three are described on,
  which is also where the menu's own label goes.

  This is the menu's list, not the authorization: which roles a page admits
  is declared by the page, in the `roles` it hands
  `DemoWeb.PersonaComponents.persona_gate/1`. The two are separate because
  the reviewer has no page of its own yet and shares the user experience's.

  `nav` is what a page assigns as `current_nav`, so a nav entry can tell
  whether it is the page being read without a table mapping one to the other.
  """

  @overview %{
    id: :overview,
    nav: :demo,
    title: "Overview",
    path: "/demo",
    blurb: "What the demo is, and the three sides of it"
  }

  @experiences [
    %{
      id: :admin,
      nav: :admin,
      title: "Admin pages",
      path: "/admin",
      blurb: "Build and view the flows and forms"
    },
    %{
      id: :user,
      nav: :users,
      title: "User pages",
      path: "/users",
      blurb: "Fill out and track an application"
    },
    %{
      id: :reviewer,
      nav: :reviewers,
      title: "Reviewer pages",
      path: "/reviewers",
      blurb: "Review and decide applications"
    }
  ]

  @doc "The experiences, in menu order."
  def all, do: @experiences

  @doc "The page the experiences are introduced on, and the menu's own label."
  def overview, do: @overview

  @doc "Everything the Demo app menu offers: the overview, then the experiences."
  def menu, do: [@overview | @experiences]

  @doc "Every `current_nav` the Demo app menu covers."
  def navs, do: Enum.map(menu(), & &1.nav)
end
