defmodule Demo.Users do
  @moduledoc """
  The demo's hardcoded users: the perspectives the demo can be viewed from.

  There is no sign-in. The current user's id lives in the session under
  `"demo_user_id"` (set by `DemoWeb.UserSwitchController`, read by
  `DemoWeb.UserHook`); visitors without one see the demo as `default/0`, the
  admin. Every user reaches the pages their own role is for and no others,
  the admin included (`DemoWeb.PersonaComponents`).
  """

  alias FormFlow.Config.Flows.Allowed

  # The flows a reviewer reviews, by slug - the two pet licenses seeded into
  # every demo database (`flows/1`).
  @pet_licenses ["dog-license", "cat-license"]

  # In reading order: reading, applying, then the two staff roles — the
  # reviewer works applications, the admin builds the flows. The demo opens
  # as the admin (`default/0`), which is the last of them rather than the
  # first: the list is a description of the cast, not a running order.
  #
  # `role` is what the pages gate on (`DemoWeb.PersonaComponents`): the two
  # pet owners share `:owner`, since nothing in the demo tells them apart.
  #
  # `perspectives` is what the FormFlow pages pass as their `perspectives`
  # attr: the ids the demo's flow types declare
  # (`DemoWeb.FormFlowLive.Types.perspectives/0`), so a user translates to
  # FormFlow one-to-one. A pet owner is an applicant and the reviewer a
  # reviewer; the admin names both, since an admin who reached an instance
  # page would be reading every side of it, and FormFlow shows a viewer
  # naming none only the flows that are for everyone. The reader names none.
  # The demo's gate keeps the admin to the admin pages, so nothing reads
  # theirs today - they say what the user is, not what a page does.
  #
  # `journeys` is whose flow instances the user's pages list, turned into
  # the FormFlow pages' `instances` attr by `instances/1`. `:own` is the
  # pet owners', and FormFlow's own default: a listing of what you started.
  # `:everyone` is the reviewer's and the admin's, and it is what makes the
  # reviews page a queue of other people's applications rather than the
  # empty table it is without it - a reviewer starts no journeys of their
  # own. Listing only: FormFlow opens any journey by id for anyone who
  # reaches its URL, and `DemoWeb.PersonaComponents.persona_gate/1` is what
  # keeps a visitor off the page to begin with.
  #
  # `journeys` decides the `flows` attr too (`flows/1`): a user who applies
  # gets every flow the tenant holds, so an admin can author one and then go
  # and start it, and a user who works other people's applications gets the
  # two pet licenses with `start: false`, which takes the Start section off
  # the reviews page.
  #
  # `landing` is where switching to the user sends the visitor
  # (`DemoWeb.UserSwitchController`): the page that perspective is for. The
  # demo is unguided, and the page someone switched from is rarely a page the
  # new perspective is admitted to, so landing beats staying put - the
  # alternative is a refusal on nearly every switch.
  @users [
    %{
      id: "docs_reader",
      role: :reader,
      perspectives: [],
      journeys: :own,
      landing: "/docs",
      name: "Docs Reader",
      initials: "DR",
      blurb: "Reads the README-style docs at /docs"
    },
    %{
      id: "dog_owner",
      role: :owner,
      perspectives: ["applicant"],
      journeys: :own,
      landing: "/demo/pet-licenses/applications",
      name: "User - Dog Owner",
      initials: "DO",
      blurb: "Applies for and renews a dog license"
    },
    %{
      id: "cat_owner",
      role: :owner,
      perspectives: ["applicant"],
      journeys: :own,
      landing: "/demo/pet-licenses/applications",
      name: "User - Cat Owner",
      initials: "CO",
      blurb: "Applies for and renews a cat license"
    },
    %{
      id: "reviewer",
      role: :reviewer,
      perspectives: ["reviewer"],
      journeys: :everyone,
      landing: "/demo/pet-licenses/reviews",
      name: "Reviewer - Pet Licenses",
      initials: "RE",
      blurb: "Reviews and decides license applications"
    },
    %{
      id: "admin",
      role: :admin,
      perspectives: ["applicant", "reviewer"],
      journeys: :everyone,
      landing: "/demo/admin",
      name: "Admin",
      initials: "AD",
      blurb: "Builds the flows and forms"
    }
  ]

  @session_key "demo_user_id"

  # The perspective the demo opens on. The admin, because the flows and forms
  # are built there and that is where the demo's story starts. A visitor who
  # deep-links to another side's page before switching meets a refusal, which
  # names who the page is for and points at the switcher - the demonstration
  # this demo is here to give.
  @default Enum.find(@users, &(&1.role == :admin)) ||
             raise("no admin user for Demo.Users.default/0 to return")

  @doc "All users, in display order."
  def all, do: @users

  @doc """
  The user a visitor sees the demo as before switching: the admin, whose
  pages are where the flows and forms are built.
  """
  def default, do: @default

  @doc "Every user holding one of `roles`, in display order."
  def with_roles(roles), do: Enum.filter(@users, &(&1.role in roles))

  @doc """
  The journeys this user's pages list, in the shape the FormFlow pages'
  `instances` attr wants: `nil` for a user who lists their own, which is
  what the attr does when it is not given, and a query over every journey
  for a user who works other people's.

  A listing, not a gate - see the note above `@users`.
  """
  def instances(%{journeys: :own}), do: nil
  def instances(%{journeys: :everyone}), do: FormFlow.Data.Instances.Flows.list_query()

  @doc """
  The flows this user's pages are about, in the shape the FormFlow pages'
  `flows` attr wants: `nil` for a user who applies, and a
  `FormFlow.Config.Flows.Allowed` per pet license, none of them startable,
  for a user who works other people's applications.

  `nil` is every root flow, which is the demo's own story: the admin builds
  a flow, switches to a pet owner, and finds it there to start. Naming the
  licenses on the applications page would break that walk-through, and this
  demo is here to give it.

  The reviews page names them, because it says something about them - a
  reviewer starts no applications of their own, so each license is
  `start: false` and the page has no Start section at all. Naming is also
  what keeps a flow the admin authors at run time from quietly becoming a
  reviewer's work: the reviews page says what a reviewer reviews, and adding
  a license is an edit here.
  """
  def flows(%{journeys: :own}), do: nil

  def flows(%{journeys: :everyone}),
    do: Enum.map(@pet_licenses, &Allowed.new(flow_slug: &1, start: false))

  @doc "Looks a user up by id."
  def fetch(id), do: Enum.find_value(@users, :error, &if(&1.id == id, do: {:ok, &1}))

  @doc "The session key the current user's id is stored under."
  def session_key, do: @session_key

  @doc "The current user for a session map, falling back to `default/0`."
  def from_session(session) do
    case fetch(Map.get(session, @session_key)) do
      {:ok, user} -> user
      :error -> default()
    end
  end
end
