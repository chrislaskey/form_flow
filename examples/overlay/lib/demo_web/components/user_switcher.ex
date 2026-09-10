defmodule DemoWeb.UserSwitcher do
  @moduledoc """
  The control that picks which of `Demo.Users` the demo is viewed as.

  Rendered in the header by `Layouts.app` and anywhere in page content that
  benefits from it. A dark initials avatar with a gradient chevron badge, a
  "Viewing as" caption over the user's name, and a menu whose rows post to
  `DemoWeb.UserSwitchController`, so choosing a user reloads the page as them.
  The current row's avatar carries a check badge instead of the chevron.

  The design was chosen on `/branding` (direction 16 with check badges).
  """

  use DemoWeb, :html

  alias Demo.Users

  attr :id, :string, required: true
  attr :current_user, :map, required: true

  attr :align, :atom,
    values: [:start, :end],
    default: :end,
    doc: "which edge the menu hangs from"

  attr :open, :boolean, default: false, doc: "render the menu already open"

  def user_switcher(assigns) do
    assigns = assign(assigns, :users, Users.all())

    ~H"""
    <details
      id={@id}
      open={@open}
      class={["dropdown", @align == :end && "dropdown-end"]}
      phx-click-away={JS.remove_attribute("open")}
    >
      <summary class="cursor-pointer list-none select-none [&::-webkit-details-marker]:hidden">
        <span class="inline-flex items-center gap-2.5 rounded-lg py-1 pl-1 pr-2 transition-colors hover:bg-gray-100">
          <.user_avatar user={@current_user} badge={:chevron} />
          <span class="flex flex-col text-left leading-tight">
            <span class="text-[10px] font-semibold uppercase tracking-wider text-gray-400">
              Viewing as
            </span>
            <span class="text-sm whitespace-nowrap">
              <span class="font-semibold text-gray-900">{@current_user.name}</span>
              <span class="text-gray-400"> · Switch</span>
            </span>
          </span>
        </span>
      </summary>

      <%!-- Links, not a <form>: FormFlow's pages carry their own forms and their
      tests select "form" outright. phoenix_html's JS turns a method="post"
      link into a form submission on click. --%>
      <div class="dropdown-content z-30 mt-2 w-72 rounded-xl border border-gray-200 bg-white p-1.5 shadow-lg">
        <p class="px-2.5 pb-1 pt-1.5 text-[10px] font-semibold uppercase tracking-wider text-gray-400">
          Viewing as
        </p>
        <ul role="listbox">
          <li :for={user <- @users}>
            <.link
              href={~p"/switch-user/#{user.id}"}
              method="post"
              role="option"
              aria-selected={to_string(user.id == @current_user.id)}
              class={[
                "flex w-full items-center gap-3 rounded-lg px-2.5 py-2 text-left transition-colors hover:bg-gray-100",
                user.id == @current_user.id && "bg-gray-50"
              ]}
            >
              <.user_avatar user={user} badge={user.id == @current_user.id && :check} />
              <span class="min-w-0 flex-1">
                <span class="block text-sm font-medium text-gray-900">{user.name}</span>
                <span class="block truncate text-xs text-gray-500">{user.blurb}</span>
              </span>
            </.link>
          </li>
        </ul>
        <p class="mt-1 border-t border-gray-100 px-2.5 pb-1 pt-2 text-[11px] text-gray-400">
          Switching reloads the page as that user.
        </p>
      </div>
    </details>
    """
  end

  @doc """
  A user's dark initials avatar, optionally with a small gradient badge
  overlapping its bottom-right corner: `:chevron` marks the switcher's
  trigger, `:check` marks the current user in its menu.
  """
  attr :user, :map, required: true
  attr :class, :string, default: "size-8 text-[11px]"
  attr :badge, :any, default: nil, values: [nil, false, :chevron, :check]

  def user_avatar(assigns) do
    ~H"""
    <span class="relative inline-flex shrink-0">
      <span class={[
        "inline-flex items-center justify-center rounded-full bg-gray-900 font-bold text-white",
        @class
      ]}>
        {@user.initials}
      </span>
      <span
        :if={@badge}
        class="absolute -bottom-1 -right-1 inline-flex size-4 items-center justify-center rounded-full bg-gradient-to-br from-indigo-600 to-fuchsia-600 ring-2 ring-white"
      >
        <%!-- Inline rather than masked heroicons so the glyphs can be optically
        centred: a "V" is top-heavy, so it sits 1.5 units below the box's
        centre; the check sits on it. Strokes are heavier than heroicons' 1.5
        to survive a 12px render. --%>
        <svg
          viewBox="0 0 16 16"
          class="size-3 text-white"
          fill="none"
          stroke="currentColor"
          stroke-width="2.25"
          stroke-linecap="round"
          stroke-linejoin="round"
          aria-hidden="true"
        >
          <path :if={@badge == :chevron} d="M4 7.5l4 4 4-4" />
          <path :if={@badge == :check} d="M3.5 8.5l3 3 6-6.5" />
        </svg>
      </span>
    </span>
    """
  end
end
