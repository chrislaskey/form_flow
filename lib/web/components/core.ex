defmodule FormFlow.Web.Components.Core do
  @moduledoc """
  Thin HEEx wrappers around `FormFlow.Web.ComponentResolver`, so FormFlow's own
  templates can write `<Core.button components={@components} ...>` the way
  they'd write `<.button>` directly, while still dispatching through a host's
  `components` module when one is given.

  Each function here mirrors the attrs of its `FormFlow.Web.CoreComponents`
  counterpart that FormFlow's own markup actually uses — not the module's
  full contract, since a host overriding `components` implements the real
  functions with whatever attrs it needs; this module only shapes the calls
  FormFlow itself makes. `components` is stripped before dispatch, so it
  never leaks into a target `input`/`button`'s own `:rest, :global`.
  """

  use Phoenix.Component

  alias FormFlow.Web.ComponentResolver

  attr(:components, :atom, default: nil)

  attr(:rest, :global,
    include: ~w(href navigate patch method download name type value disabled form)
  )

  attr(:class, :any)
  attr(:variant, :string, values: ~w(primary))
  slot(:inner_block, required: true)

  def button(assigns) do
    ComponentResolver.render(assigns.components, :button, Map.delete(assigns, :components))
  end

  attr(:components, :atom, default: nil)
  slot(:inner_block, required: true)

  def error(assigns) do
    ComponentResolver.render(assigns.components, :error, Map.delete(assigns, :components))
  end

  attr(:components, :atom, default: nil)
  attr(:kind, :atom, default: :neutral, values: [:neutral, :info, :success, :warning, :error])
  attr(:class, :any, default: nil)
  attr(:rest, :global)
  slot(:inner_block, required: true)

  def alert(assigns) do
    ComponentResolver.render(assigns.components, :alert, Map.delete(assigns, :components))
  end

  attr(:components, :atom, default: nil)

  attr(:name, :string,
    required: true,
    doc: ~s|a Heroicons name, e.g. "hero-trash", or "stethoscope", which FormFlow draws itself|
  )

  attr(:class, :any, default: "size-4")

  @doc """
  An icon, by Heroicons name, drawn by the host's `icon/1` when it has one.

  Asking by name is what lets a host's own delete icon show up on FormFlow's
  pages: the name travels, the drawing does not.

  `"stethoscope"` is the exception. Heroicons has none, so it never goes to
  a host — a host's `icon/1` written for `hero-*` names would raise on it —
  and FormFlow draws it inline. A host that wants its own draws it in the
  health badge's place, not here.
  """
  def icon(%{name: "stethoscope"} = assigns) do
    ~H"""
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.75"
      stroke-linecap="round"
      stroke-linejoin="round"
      class={@class}
      aria-hidden="true"
    >
      <path d="M11 2v2" />
      <path d="M5 2v2" />
      <path d="M5 3H4a2 2 0 0 0-2 2v4a6 6 0 0 0 12 0V5a2 2 0 0 0-2-2h-1" />
      <path d="M8 15a6 6 0 0 0 12 0v-3" />
      <circle cx="20" cy="10" r="2" />
    </svg>
    """
  end

  def icon(assigns) do
    ComponentResolver.render(assigns.components, :icon, Map.delete(assigns, :components))
  end

  attr(:components, :atom, default: nil)
  attr(:kind, :atom, default: :neutral, values: [:neutral, :info, :success, :warning, :error])
  attr(:variant, :string, default: nil, values: [nil, "solid"])
  attr(:class, :any, default: nil)
  attr(:rest, :global)
  slot(:inner_block, required: true)

  def badge(assigns) do
    ComponentResolver.render(assigns.components, :badge, Map.delete(assigns, :components))
  end

  attr(:components, :atom, default: nil)
  attr(:id, :any, default: nil)
  attr(:name, :any)
  attr(:label, :string, default: nil)
  attr(:value, :any, default: nil)
  attr(:type, :string, default: "text")
  attr(:errors, :list, default: [])
  attr(:class, :any, default: nil)
  attr(:error_class, :any, default: nil)
  attr(:options, :list, doc: "for `type=\"select\"`: `Phoenix.HTML.Form.options_for_select/2`'s")
  attr(:prompt, :string, default: nil, doc: "for `type=\"select\"`: the blank first option")

  attr(:rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)
  )

  def input(assigns) do
    ComponentResolver.render(assigns.components, :input, Map.delete(assigns, :components))
  end

  attr(:components, :atom, default: nil)
  attr(:id, :string, required: true)
  attr(:rows, :list, required: true)
  attr(:row_id, :any, default: nil)
  attr(:row_click, :any, default: nil)
  attr(:row_item, :any, default: &Function.identity/1)

  slot :col, required: true do
    attr(:label, :string)
  end

  slot(:action)

  def table(assigns) do
    ComponentResolver.render(assigns.components, :table, Map.delete(assigns, :components))
  end

  attr(:components, :atom, default: nil)

  slot :item, required: true do
    attr(:title, :string, required: true)
  end

  def list(assigns) do
    ComponentResolver.render(assigns.components, :list, Map.delete(assigns, :components))
  end
end
