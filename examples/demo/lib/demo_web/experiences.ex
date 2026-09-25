defmodule DemoWeb.Experiences do
  @moduledoc """
  The pages of the demo - three sides, four pages - and the page that
  introduces them.

  `all/0` is the four pages; `menu/0` puts `overview/0` in front of them, and
  is what the header's Demo app menu and the mobile nav list. The overview is
  not a page of the demo's service — it is the page the others are described
  on, which is also where the menu's own label goes. The user side has two
  pages: the pet license applications, and Other Forms, the catch-all for
  every flow outside the pet licensing group.

  Each experience names the `roles` it is for and the `lands_on` user it
  puts a visitor who does not hold one. The header's menus list **every**
  experience to everyone: in a self-guided demo a hidden link is a page
  nobody learns exists, and the landing below means no link leads to a
  refusal. The overview has no roles: it is where the sides are described,
  and everyone reads it.

  ## Clicking a side switches the visitor to it

  `DemoWeb.ExperienceEntry` asks `fits?/2` on the way in and, when the
  answer is no, switches the demo's current user to `lands_on` before the
  page renders. So the reviews page is always read by a reviewer and the
  admin pages by the admin, whoever clicked.

  Fit is the **role**, not the FormFlow perspectives the user carries. The
  admin holds both `"applicant"` and `"reviewer"` perspectives, so a
  perspective test would leave an admin reading the reviews page as
  themselves - every applicant's journey, correct in a real service and
  unexplained here, which is the thing
  `DemoWeb.PersonaComponents` was written to stop. One page, one side.

  The two owner pages land on the dog owner and admit the cat owner, both
  being owners, so a visitor who switched to the cat owner keeps that
  choice while moving between them.

  `title` is the page's name in the pet licensing service, which the header
  menus show. `kind` is which side of the demo it is — "User pages",
  "Reviewer pages" — the name the overview explains the demo by, so the
  overview shows both: the kind first, then the title beside it
  (`overview_title/1`).

  `nav` is what a page assigns as `current_nav`, so a nav entry can tell
  whether it is the page being read without a table mapping one to the other.
  """

  @overview %{
    id: :overview,
    nav: :demo,
    title: "Overview",
    path: "/demo",
    blurb: "What the demo is, and the three sides of it",
    roles: :everyone
  }

  @experiences [
    %{
      id: :admin,
      nav: :admin,
      title: "Admin pages",
      kind: "Admin pages",
      path: "/demo/admin",
      blurb: "Build and view the flows and forms",
      roles: [:admin],
      lands_on: "admin"
    },
    %{
      id: :user,
      nav: :users,
      title: "Pet License Applications",
      kind: "User pages",
      path: "/demo/pet-licenses/applications",
      blurb: "Fill out and track an application",
      roles: [:owner],
      lands_on: "dog_owner"
    },
    %{
      id: :reviewer,
      nav: :reviewers,
      title: "Pet License Reviews",
      kind: "Reviewer pages",
      path: "/demo/pet-licenses/reviews",
      blurb: "Review and decide applications",
      roles: [:reviewer],
      lands_on: "reviewer"
    },
    %{
      id: :other,
      nav: :other_forms,
      title: "Other Forms",
      kind: "User pages",
      path: "/demo/other-forms",
      blurb: "Fill out and track any flow outside pet licensing",
      roles: [:owner],
      lands_on: "dog_owner"
    }
  ]

  @doc "The experiences, in menu order."
  def all, do: @experiences

  @doc """
  How the overview names an experience: its kind, then its title in the pet
  licensing service when the two differ — "User pages - Pet License
  Applications", but just "Admin pages".
  """
  def overview_title(%{kind: kind, title: kind}), do: kind
  def overview_title(%{kind: kind, title: title}), do: "#{kind} - #{title}"

  @doc "The page the experiences are introduced on, and the menu's own label."
  def overview, do: @overview

  @doc "Everything the Demo app menu offers: the overview, then the experiences."
  def menu, do: [@overview | @experiences]

  @doc """
  What the Demo app menu offers: every experience, to everyone, whoever is
  viewing. The argument is kept so callers read the same either way, and
  because who is viewing is what the menu marks as current.

  It used to be filtered to the pages the viewer was admitted to, with the
  admin excepted so the demo's opening user could still see the sides
  exist. Both halves are gone: clicking a side now switches the visitor to
  it (`DemoWeb.ExperienceEntry`), so there is no refusal for a link to lead
  to, and a menu that changed shape as you moved around it was a poor way
  to show a visitor what the demo contains.
  """
  def menu_for(_user), do: menu()

  @doc "The experience with `id`."
  def fetch!(id) do
    Enum.find(@experiences, &(&1.id == id)) ||
      raise ArgumentError, "no experience #{inspect(id)}"
  end

  @doc "The roles the experience with `id` is for."
  def roles(id), do: fetch!(id).roles

  @doc """
  Whether `user` is one this experience is for - the test
  `DemoWeb.ExperienceEntry` asks on the way into a page, and the reason it
  is the role rather than the perspectives (see the moduledoc).
  """
  def fits?(%{roles: :everyone}, _user), do: true
  def fits?(%{roles: roles}, user), do: DemoWeb.PersonaComponents.allows?(user, roles)

  @doc "Every `current_nav` the Demo app menu covers."
  def navs, do: Enum.map(menu(), & &1.nav)
end
