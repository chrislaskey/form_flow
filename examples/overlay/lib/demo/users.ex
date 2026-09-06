defmodule Demo.Users do
  @moduledoc """
  The demo's hardcoded users: the perspectives the demo can be viewed from.

  There is no sign-in. The current user's id lives in the session under
  `"demo_user_id"` (set by `DemoWeb.UserSwitchController`, read by
  `DemoWeb.UserHook`); visitors without one see the demo as the default user.
  """

  # In the order a visitor meets them: reading, applying, then the two staff
  # roles — the reviewer works applications, the admin builds the flows.
  @users [
    %{
      id: "docs_reader",
      name: "Docs Reader",
      initials: "DR",
      blurb: "Reads the README-style docs at /"
    },
    %{
      id: "dog_owner",
      name: "Dog Owner",
      initials: "DO",
      blurb: "Applies for and renews a dog license"
    },
    %{
      id: "cat_owner",
      name: "Cat Owner",
      initials: "CO",
      blurb: "Applies for and renews a cat license"
    },
    %{
      id: "reviewer",
      name: "Pet License Reviewer",
      initials: "PR",
      blurb: "Reviews and decides license applications"
    },
    %{
      id: "admin",
      name: "Pet License Admin",
      initials: "PA",
      blurb: "Builds the licensing flows and forms"
    }
  ]

  @session_key "demo_user_id"

  @doc "All users, in display order."
  def all, do: @users

  @doc "The user a visitor sees the demo as before switching."
  def default, do: hd(@users)

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
