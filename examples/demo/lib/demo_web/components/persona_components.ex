defmodule DemoWeb.PersonaComponents do
  @moduledoc """
  Which of `Demo.Users` a page is for, and the framed control for choosing
  between them.

  There is no sign-in in the demo, so this is not security - it is the
  demonstration of it. Every page is for one side of the demo and no other,
  the admin included. The admin used to be admitted everywhere, on the
  reasoning that the demo opens as the admin and a first visit should not
  be a refusal. It cost more than it bought: an admin on the reviews page
  read every applicant's journey, correct in a real service and unexplained
  in a self-guided demo, where the page gives no sign that what is being
  read is the reviewer's view rather than the admin's own.

  **Nothing is refused any more.** Opening a side of the demo the current
  user is not for switches the visitor to one who is
  (`DemoWeb.ExperienceEntry`), so `allows?/2` now answers a question asked
  on the way in rather than one asked of a page already rendered. The
  refusal this module used to draw - "Not authorized!", naming whose page
  it was and pointing at the switcher - is gone with the thing it
  explained. It was the right screen while a wrong-perspective page was a
  dead end; it is a screen nobody can reach now that the same click simply
  works.
  """

  use DemoWeb, :html

  alias Demo.Users
  alias DemoWeb.UserSwitcher

  @doc "Whether `user` holds one of `roles`."
  def allows?(user, roles), do: user.role in roles

  @doc """
  The framed "Pick a user perspective" control, for a page that introduces
  the switch rather than assuming it — the demo index does. Pages that
  merely need it have the header's.
  """
  attr :id, :string, default: "perspective"
  attr :current_user, :map, required: true
  attr :blurb, :string, default: nil, doc: "replaces the default line under the heading"

  def pick_perspective(assigns) do
    assigns = assign_new(assigns, :count, fn -> length(Users.all()) end)

    ~H"""
    <section
      id={@id}
      class="flex max-w-5xl items-center justify-between gap-4 rounded-xl border border-gray-300 px-6 py-5"
    >
      <div class="space-y-1">
        <h2 class="font-semibold text-gray-900">Choose a user perspective</h2>
        <p class="text-sm text-base-content/70">
          {@blurb ||
            "The demo is viewed as one of #{@count} hardcoded users, with no sign-in.
             Each one sees the pages their own role is for and no others, so
             switching is how you read another side. It opens as the admin, who
             builds the flows. Switch here or in the header; the page reloads as
             that user."}
        </p>
      </div>
      <UserSwitcher.user_switcher id={"#{@id}-user-switcher"} current_user={@current_user} />
    </section>
    """
  end
end
