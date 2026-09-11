defmodule Demo.Users do
  @moduledoc """
  The demo's hardcoded users: the perspectives the demo can be viewed from.

  There is no sign-in. The current user's id lives in the session under
  `"demo_user_id"` (set by `DemoWeb.UserSwitchController`, read by
  `DemoWeb.UserHook`); visitors without one see the demo as `default/0`, the
  admin, who is admitted everywhere — narrower perspectives are opt-in.
  """

  # In reading order: reading, applying, then the two staff roles — the
  # reviewer works applications, the admin builds the flows. The demo opens
  # as the admin (`default/0`), which is the last of them rather than the
  # first: the list is a description of the cast, not a running order.
  #
  # `role` is what the pages gate on (`DemoWeb.PersonaComponents`): the two
  # pet owners share `:owner`, since nothing in the demo tells them apart.
  @users [
    %{
      id: "docs_reader",
      role: :reader,
      name: "Docs Reader",
      initials: "DR",
      blurb: "Reads the README-style docs at /"
    },
    %{
      id: "dog_owner",
      role: :owner,
      name: "User - Dog Owner",
      initials: "DO",
      blurb: "Applies for and renews a dog license"
    },
    %{
      id: "cat_owner",
      role: :owner,
      name: "User - Cat Owner",
      initials: "CO",
      blurb: "Applies for and renews a cat license"
    },
    %{
      id: "reviewer",
      role: :reviewer,
      name: "Reviewer - Pet Licenses",
      initials: "RE",
      blurb: "Reviews and decides license applications"
    },
    %{
      id: "admin",
      role: :admin,
      name: "Admin",
      initials: "AD",
      blurb: "Builds the flows and forms"
    }
  ]

  @session_key "demo_user_id"

  # The perspective the demo opens on. The admin, because
  # `DemoWeb.PersonaComponents` admits an admin to every page, so a visitor
  # who has not chosen a perspective yet never lands on a refusal.
  @default Enum.find(@users, &(&1.role == :admin)) ||
             raise("no admin user for Demo.Users.default/0 to return")

  @doc "All users, in display order."
  def all, do: @users

  @doc """
  The user a visitor sees the demo as before switching: the admin, who can
  see every page.
  """
  def default, do: @default

  @doc "Every user holding one of `roles`, in display order."
  def with_roles(roles), do: Enum.filter(@users, &(&1.role in roles))

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
