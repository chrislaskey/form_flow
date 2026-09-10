defmodule DemoWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use DemoWeb, :html

  alias DemoWeb.Experiences
  alias DemoWeb.UserSwitcher

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :current_nav, :atom,
    default: nil,
    doc:
      "which primary nav item is active: :home, :install_check, :docs, " <>
        ":admin, or :users — the last two both light the Demo Experience menu"

  attr :current_user, :map,
    default: nil,
    doc: "the `Demo.Users` user the demo is viewed as; renders the user switcher when set"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="flex min-h-screen flex-col bg-white">
      <header class="w-full bg-white shadow-sm">
        <div class="h-1 w-full bg-gradient-to-r from-indigo-600 via-violet-600 to-fuchsia-600 opacity-50" />
        <div class="flex items-center justify-between p-6 px-8">
          <.link
            navigate="/"
            class="flex items-center gap-2 font-semibold text-gray-900 hover:text-gray-600 text-lg"
          >
            <.logo_mark class="size-8" box1="#111827" box2="url(#logo-gradient)" front={:box1}>
              <:defs>
                <linearGradient id="logo-gradient" x1="0" y1="0" x2="1" y2="1">
                  <stop offset="0%" stop-color="#4f46e5" />
                  <stop offset="50%" stop-color="#7c3aed" />
                  <stop offset="100%" stop-color="#c026d3" />
                </linearGradient>
              </:defs>
            </.logo_mark>
            FormFlow <span class="font-thin opacity-50">Demo</span>
          </.link>

          <div class="flex items-center gap-4">
            <nav class="hidden items-center gap-1 text-sm font-medium sm:flex">
              <.nav_link navigate="/" current={@current_nav == :home}>Home</.nav_link>
              <.nav_link navigate="/docs" current={@current_nav == :docs}>Docs</.nav_link>
              <.experience_menu current={@current_nav in [:admin, :users]} />
            </nav>
            <div :if={@current_user} class="flex items-center sm:border-l sm:border-gray-200 sm:pl-4">
              <UserSwitcher.user_switcher id="header-user-switcher" current_user={@current_user} />
            </div>
          </div>
        </div>
      </header>

      <main class="min-w-0 flex-1 px-4 py-8 sm:px-6 lg:px-8">
        {render_slot(@inner_block)}
      </main>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Renders the FormFlow mark: two overlapping, see-through squares (echoing the
  ⧉ glyph used for subflow nodes in the editor), top-left over bottom-right.

  Pass `box1`/`box2` as a color (`"currentColor"`, `"#000"`, `"url(#some-id)"`)
  to color each square independently — a `:defs` slot carries any `<defs>`
  (e.g. a `<linearGradient>`) a `url(#...)` value refers to. `front` picks
  which square draws last (so its stroke sits on top at the overlap).
  """
  attr :class, :string, default: "size-5"
  attr :box1, :string, default: "currentColor", doc: "stroke for the top-left square"
  attr :box2, :string, default: "currentColor", doc: "stroke for the bottom-right square"

  attr :front, :atom,
    values: [:box1, :box2],
    default: :box2,
    doc: "which square renders on top at the overlap"

  slot :defs

  def logo_mark(assigns) do
    ~H"""
    <svg viewBox="0 0 24 24" fill="none" stroke-width="1.75" class={@class} aria-hidden="true">
      {render_slot(@defs)}
      <rect :if={@front != :box1} x="3" y="3" width="13" height="13" rx="1" stroke={@box1} />
      <rect :if={@front != :box2} x="8" y="8" width="13" height="13" rx="1" stroke={@box2} />
      <rect :if={@front == :box1} x="3" y="3" width="13" height="13" rx="1" stroke={@box1} />
      <rect :if={@front == :box2} x="8" y="8" width="13" height="13" rx="1" stroke={@box2} />
    </svg>
    """
  end

  @doc """
  The header's Demo Experience menu: the three sides of the demo, from
  `DemoWeb.Experiences`.

  A `<details>` rather than a hover menu, for the same reason the user
  switcher is one — it opens on click, closes on click-away, and needs no
  JavaScript of its own.
  """
  attr :current, :boolean, default: false, doc: "whether one of its pages is being read"

  def experience_menu(assigns) do
    assigns = assign(assigns, :experiences, Experiences.all())

    ~H"""
    <details
      id="experience-menu"
      class="dropdown dropdown-end"
      phx-click-away={JS.remove_attribute("open")}
    >
      <summary class={[
        "flex cursor-pointer list-none items-center gap-1 rounded-lg px-3 py-2 text-gray-600 transition-colors select-none hover:bg-gray-100 hover:text-gray-900 [&::-webkit-details-marker]:hidden",
        @current && "bg-gray-100 font-semibold text-indigo-600"
      ]}>
        Demo Experience
        <svg
          viewBox="0 0 16 16"
          class="size-3.5"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
          stroke-linejoin="round"
          aria-hidden="true"
        >
          <path d="M4 6.5l4 4 4-4" />
        </svg>
      </summary>

      <ul class="dropdown-content z-30 mt-2 w-64 rounded-xl border border-gray-200 bg-white p-1.5 shadow-lg">
        <li :for={experience <- @experiences}>
          <.link
            navigate={experience.path}
            class="block rounded-lg px-2.5 py-2 transition-colors hover:bg-gray-100"
          >
            <span class="block text-sm font-medium text-gray-900">{experience.title}</span>
            <span class="block truncate text-xs text-gray-500">{experience.blurb}</span>
          </.link>
        </li>
      </ul>
    </details>
    """
  end

  @doc """
  Renders one link in the header nav, styled as active when `current` is true.
  """
  attr :navigate, :string, required: true
  attr :current, :boolean, default: false
  slot :inner_block, required: true

  def nav_link(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class={[
        "rounded-lg px-3 py-2 text-gray-600 transition-colors hover:bg-gray-100 hover:text-gray-900",
        @current && "bg-gray-100 font-semibold text-indigo-600"
      ]}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title="We can't find the internet"
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title="Something went wrong!"
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
