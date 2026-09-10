defmodule DemoWeb.Experiences do
  @moduledoc """
  The three sides of the demo the header's Demo Experience menu offers.

  This is the menu's list, not the authorization: which roles a page admits
  is declared by the page, in the `roles` it hands
  `DemoWeb.PersonaComponents.persona_gate/1`. The two are separate because
  the reviewer has no page of its own yet and shares the user experience's.
  """

  @experiences [
    %{
      id: :admin,
      title: "Admin pages",
      path: "/admin",
      blurb: "Build and view the flows and forms"
    },
    %{
      id: :user,
      title: "User pages",
      path: "/users",
      blurb: "Fill out and track an application"
    },
    %{
      id: :reviewer,
      title: "Reviewer pages",
      path: "/reviewers",
      blurb: "Review and decide applications"
    }
  ]

  @doc "The experiences, in menu order."
  def all, do: @experiences
end
