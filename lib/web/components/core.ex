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
  attr(:kind, :atom, default: :neutral, values: [:neutral, :info, :success, :warning, :error])
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
