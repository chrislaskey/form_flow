defmodule DemoWeb.PersonaComponents do
  @moduledoc """
  Which of `Demo.Users` a page admits, and what it shows the ones it turns
  away.

  There is no sign-in in the demo, so this is not security — it is the
  demonstration of it. A page names the roles it is for, and a visitor
  holding another one is met by the same control they would have used to
  get in: the perspective picker, with the users who can see the page
  called out.
  """

  use DemoWeb, :html

  alias Demo.Users
  alias DemoWeb.UserSwitcher

  @doc "Whether `user` holds one of `roles`."
  def allows?(user, roles), do: user.role in roles

  @doc """
  A page's content, for the users whose role is in `roles`. Everyone else
  gets `not_authorized/1` in its place — the block is never rendered, so a
  page can put anything inside it.
  """
  attr :current_user, :map, required: true
  attr :roles, :list, required: true, doc: "the roles this page is for"
  attr :page, :string, required: true, doc: "what the page is, named in the refusal"
  slot :inner_block, required: true

  def persona_gate(assigns) do
    ~H"""
    <%= if allows?(@current_user, @roles) do %>
      {render_slot(@inner_block)}
    <% else %>
      <.not_authorized current_user={@current_user} roles={@roles} page={@page} />
    <% end %>
    """
  end

  @doc """
  The refusal: who you are, who this page is for, and the picker to become
  one of them.
  """
  attr :current_user, :map, required: true
  attr :roles, :list, required: true
  attr :page, :string, required: true

  def not_authorized(assigns) do
    assigns = assign(assigns, :allowed, Users.with_roles(assigns.roles))

    ~H"""
    <div class="space-y-6">
      <header class="space-y-2">
        <h1 class="text-2xl font-semibold">Not authorized</h1>
        <p class="max-w-3xl text-base-content/70">
          You are viewing the demo as <span class="font-semibold text-base-content">{@current_user.name}</span>, and {@page} is not {@current_user.name}'s to see. It belongs to <span class="font-semibold text-base-content">
            {@allowed |> Enum.map(& &1.name) |> to_sentence()}
          </span>.
        </p>
      </header>

      <.pick_perspective
        id="not-authorized-perspective"
        current_user={@current_user}
        blurb="Switch to one of them and the page opens."
      />
    </div>
    """
  end

  @doc """
  The framed "Pick a user perspective" control, for any page that wants to
  offer the switch in its own content rather than only in the header.
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
        <h2 class="font-semibold text-gray-900">Pick a user perspective</h2>
        <p class="text-sm text-base-content/70">
          {@blurb ||
            "The demo is viewed as one of #{@count} hardcoded users, with no sign-in.
             Switch here or in the header; the page reloads as that user."}
        </p>
      </div>
      <UserSwitcher.user_switcher id={"#{@id}-user-switcher"} current_user={@current_user} />
    </section>
    """
  end

  # "A", "A and B", "A, B, and C"
  defp to_sentence([name]), do: name
  defp to_sentence([first, second]), do: "#{first} and #{second}"

  defp to_sentence(names) do
    {leading, [last]} = Enum.split(names, -1)
    Enum.join(leading, ", ") <> ", and " <> last
  end
end
