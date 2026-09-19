defmodule DemoWeb.Experiences do
  @moduledoc """
  The three sides of the demo, and the page that introduces them.

  `all/0` is the three sides; `menu/0` puts `overview/0` in front of them, and
  is what the header's Demo app menu and the mobile nav list. The overview is
  not a fourth side of the demo — it is the page those three are described on,
  which is also where the menu's own label goes.

  Each experience names the `roles` it is for. The page hands them to
  `DemoWeb.PersonaComponents.persona_gate/1`, and the header's menus list
  what `menu_for/1` gives them: the experiences the current user is
  admitted to, so nobody is offered a link to a refusal - except the admin,
  who is offered every side (see `menu_for/1`). The overview has no roles:
  it is where the sides are described, and everyone reads it.

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
      roles: [:admin]
    },
    %{
      id: :user,
      nav: :users,
      title: "Pet License Applications",
      kind: "User pages",
      path: "/demo/pet-licenses/applications",
      blurb: "Fill out and track an application",
      roles: [:owner]
    },
    %{
      id: :reviewer,
      nav: :reviewers,
      title: "Pet License Reviews",
      kind: "Reviewer pages",
      path: "/demo/pet-licenses/reviews",
      blurb: "Review and decide applications",
      roles: [:reviewer]
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

  # The roles the menu offers every side to, admitted or not. The admin's,
  # and only because the demo opens as the admin (`Demo.Users.default/0`):
  # a visitor who starts there and is shown two of four pages has no way to
  # learn the other two exist. The link leads to a refusal that names whose
  # page it is and points at the switcher, which teaches the demo's one
  # lesson better than a missing link does.
  #
  # This is about links, not access. `DemoWeb.PersonaComponents` admits the
  # admin to the admin pages and no others, as it does everyone.
  @offered_every_side [:admin]

  @doc """
  What the Demo app menu offers `user`: the overview, then the experiences
  whose pages admit them - every side for the roles in `@offered_every_side`,
  and the full `menu/0` when there is no user.
  """
  def menu_for(nil), do: menu()
  def menu_for(%{role: role}) when role in @offered_every_side, do: menu()
  def menu_for(user), do: Enum.filter(menu(), &admits?(&1, user))

  @doc "The roles the experience with `id` is for, as its page's gate wants them."
  def roles(id) do
    case Enum.find(@experiences, &(&1.id == id)) do
      %{roles: roles} -> roles
      nil -> raise ArgumentError, "no experience #{inspect(id)}"
    end
  end

  defp admits?(%{roles: :everyone}, _user), do: true
  defp admits?(%{roles: roles}, user), do: DemoWeb.PersonaComponents.allows?(user, roles)

  @doc "Every `current_nav` the Demo app menu covers."
  def navs, do: Enum.map(menu(), & &1.nav)
end
