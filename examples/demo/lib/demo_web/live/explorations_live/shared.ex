defmodule DemoWeb.ExplorationsLive.Shared do
  @moduledoc """
  The pieces every exploration page under `/explorations` uses: the link back
  to the index, and the SVG gradients the logo mark's `url(#...)` strokes
  refer to.
  """

  use DemoWeb, :html

  @doc """
  The link back to the exploration index, above a page's heading.
  """
  def back_link(assigns) do
    ~H"""
    <p class="text-sm">
      <.link navigate="/explorations" class="text-indigo-600 hover:underline">
        ← Explorations
      </.link>
    </p>
    """
  end

  @doc """
  The gradients a `Layouts.logo_mark` stroke can point at, as an empty SVG
  the page renders once. A `url(#grad-brand)` fill only resolves if the
  gradient is in the document, so any page drawing the mark gradient-filled
  has to include this.
  """
  def gradients(assigns) do
    ~H"""
    <svg width="0" height="0" style="position: absolute" aria-hidden="true">
      <defs>
        <linearGradient id="grad-brand" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0%" stop-color="#4f46e5" />
          <stop offset="50%" stop-color="#7c3aed" />
          <stop offset="100%" stop-color="#c026d3" />
        </linearGradient>
        <linearGradient id="grad-fuchsia-purple" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0%" stop-color="#c026d3" />
          <stop offset="100%" stop-color="#7e22ce" />
        </linearGradient>
      </defs>
    </svg>
    """
  end
end
