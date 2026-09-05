defmodule DemoWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use DemoWeb, :html

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
    doc: "which primary nav item is active: :home, :install_check, :admin, or :users"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="flex min-h-screen flex-col bg-white">
      <header class="w-full bg-white shadow-sm">
        <div class="h-1 w-full bg-gradient-to-r from-indigo-600 via-violet-600 to-fuchsia-600" />
        <div class="flex items-center justify-between p-5">
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
            FormFlow <span class="-ml-1 opacity-70 font-light">Demo</span>
          </.link>

          <nav class="hidden items-center gap-1 text-sm font-medium sm:flex">
            <.nav_link navigate="/" current={@current_nav == :home}>Home</.nav_link>
            <.nav_link navigate="/install-check" current={@current_nav == :install_check}>
              Install Check
            </.nav_link>
            <.nav_link navigate="/admin" current={@current_nav == :admin}>Admin</.nav_link>
            <.nav_link navigate="/users" current={@current_nav == :users}>Users</.nav_link>
          </nav>
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
