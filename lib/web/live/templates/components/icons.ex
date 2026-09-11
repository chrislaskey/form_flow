defmodule FormFlow.Web.Templates.Components.Icons do
  @moduledoc """
  `FormFlow.Web.Templates.Components.Icons` holds the icons the admin pages
  draw more than once. They are inline SVG — the paths are Heroicons' 20px
  solid set — so a host needs no icon set of its own for FormFlow's pages to
  look right. `FormFlow.Web.CoreComponents.icon/1` is the other way: it
  emits a `hero-*` class name and leaves the drawing to whatever the host
  bundles.

  Each takes a `class` for its size and colour, and is `aria-hidden`: the
  button around it carries the label.

      <Icons.trash class="size-5" />
  """

  use Phoenix.Component

  attr(:class, :any, default: "size-5")

  @doc "A waste basket, for a delete whose button is the icon alone."
  def trash(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class={@class} aria-hidden="true">
      <path
        fill-rule="evenodd"
        d="M8.75 1A2.75 2.75 0 0 0 6 3.75v.443c-.795.077-1.584.176-2.365.298a.75.75 0 1 0 .23 1.482l.149-.022.841 10.518A2.75 2.75 0 0 0 7.596 19h4.807a2.75 2.75 0 0 0 2.742-2.53l.841-10.52.149.023a.75.75 0 0 0 .23-1.482A41.03 41.03 0 0 0 14 4.193V3.75A2.75 2.75 0 0 0 11.25 1h-2.5ZM10 4c.84 0 1.673.025 2.5.075V3.75c0-.69-.56-1.25-1.25-1.25h-2.5c-.69 0-1.25.56-1.25 1.25v.325C8.327 4.025 9.16 4 10 4ZM8.58 7.72a.75.75 0 0 0-1.5.06l.3 7.5a.75.75 0 1 0 1.5-.06l-.3-7.5Zm4.34.06a.75.75 0 1 0-1.5-.06l-.3 7.5a.75.75 0 1 0 1.5.06l.3-7.5Z"
        clip-rule="evenodd"
      />
    </svg>
    """
  end
end
