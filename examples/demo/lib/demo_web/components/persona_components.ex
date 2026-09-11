defmodule DemoWeb.PersonaComponents do
  @moduledoc """
  Which of `Demo.Users` a page admits, and what it shows the ones it turns
  away.

  There is no sign-in in the demo, so this is not security — it is the
  demonstration of it. A page names the roles it is for, and a visitor
  holding another one is told whose page it is and sent to the header's
  switcher. Deliberately sent, rather than offered a switcher of its own:
  there is one place to change perspective, and a refusal is a bad place to
  teach a second one.

  A gate wraps a page's content, not its title — the title stays outside it,
  so someone turned away still sees which page they were turned away from.
  """

  use DemoWeb, :html

  import DemoWeb.PageComponents

  alias Demo.Users
  alias DemoWeb.UserSwitcher

  @doc "Whether `user` holds one of `roles`."
  def allows?(user, roles), do: user.role in roles

  @doc """
  A page's content, for the users whose role is in `roles`. Everyone else
  gets `not_authorized/1` in its place — the block is never rendered, so a
  page can put anything inside it.

  Wrap the content, and leave the page's `h1` above it.
  """
  attr :current_user, :map, required: true
  attr :roles, :list, required: true, doc: "the roles this page is for"
  attr :page, :string, required: true, doc: "what is being refused, as the refusal names it"
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
  The refusal: who you are, who this page is for, and where to change that.
  """
  attr :current_user, :map, required: true
  attr :roles, :list, required: true
  attr :page, :string, required: true

  def not_authorized(assigns) do
    assigns = assign(assigns, :allowed, Users.with_roles(assigns.roles))

    ~H"""
    <div>
      <.h2>Not authorized!</.h2>

      <div class="space-y-4">
        <p class="max-w-5xl text-base-content/70">
          You are viewing the demo as <span class="font-semibold text-base-content">{@current_user.name}</span>, who cannot see {@page}.
          <span class="font-semibold text-base-content">{@allowed
          |> Enum.map(& &1.name)
          |> to_sentence()}</span>
          can.
        </p>

        <p class="flex max-w-5xl items-center gap-2 text-base-content/70 border rounded-lg p-4 border-gray-300">
          Switch with the <span class="font-semibold text-base-content">Viewing as</span>
          control in the top right of every page, and the page opens.
          <svg
            viewBox="0 0 16 16"
            class="size-4 shrink-0"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
            aria-hidden="true"
          >
            <path d="M5.5 10.5l5-5M6.5 5.5h4v4" />
          </svg>
        </p>
      </div>
    </div>
    """
  end

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
