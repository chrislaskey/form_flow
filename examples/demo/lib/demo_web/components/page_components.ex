defmodule DemoWeb.PageComponents do
  @moduledoc """
  The demo's shared typography: one definition of what a heading and a
  paragraph look like, wherever they are written.

  These began in the docs pages and are now every page's — the admin, user,
  and reviewer pages share them, so a heading is the same size and weight
  whichever side of the demo it is on. Docs-only furniture (the left nav,
  the anchored sections it links to) stays in `DemoWeb.DocsComponents`.

  Every component takes an optional `class` for the spacing one call needs,
  appended so it wins over the shared classes.
  """

  use Phoenix.Component

  @doc "A page's title. One per page, above everything else."
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def h1(assigns) do
    ~H"""
    <h1 class={["text-3xl", @class]}>{render_slot(@inner_block)}</h1>
    """
  end

  @doc """
  A section heading. `scroll-mt` is here rather than at the docs' call site
  because any of these can become an anchor's target.
  """
  attr :id, :string, default: nil
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def h2(assigns) do
    ~H"""
    <h2 id={@id} class={["scroll-mt-8 mb-6 text-2xl font-semibold", @class]}>
      {render_slot(@inner_block)}
    </h2>
    """
  end

  @doc "A heading inside a section."
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def h3(assigns) do
    ~H"""
    <h3 class={["mt-6 font-bold", @class]}>{render_slot(@inner_block)}</h3>
    """
  end

  @doc "A paragraph, held to a readable measure."
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def p(assigns) do
    ~H"""
    <p class={["max-w-3xl", @class]}>{render_slot(@inner_block)}</p>
    """
  end

  @doc """
  An aside in the muted voice — what to take away from the thing above it.
  Newlines in the text are kept, so it can carry paragraphs of its own.
  """
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def note(assigns) do
    ~H"""
    <p class={["max-w-3xl whitespace-pre-line text-base-content/70", @class]}>
      {render_slot(@inner_block)}
    </p>
    """
  end
end
