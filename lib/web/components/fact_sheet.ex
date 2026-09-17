defmodule FormFlow.Web.Components.FactSheet do
  @moduledoc """
  `FormFlow.Web.Components.FactSheet` function components draw a page's
  facts about the thing it shows - a flow's name, slug, status, and kind;
  an instance's status and when it was started - read here rather than
  edited: a bordered box, four cells to a row, each cell a label over its
  value.

  Both sides of the library draw one. The templates pages put it under the
  canvas or the form (`FormFlow.Web.Templates.Flows.Show`,
  `FormFlow.Web.Templates.Forms.Show`), the instance page under its list of
  forms (`FormFlow.Web.Instances.Flows.Show`); the cells are one component
  so the sheets cannot drift apart.

      <FactSheet.fact_sheet>
        <FactSheet.detail label="Name">{@flow.name}</FactSheet.detail>
        <FactSheet.detail label="Slug">
          <FactSheet.detail_value value={@flow.slug} code />
        </FactSheet.detail>
      </FactSheet.fact_sheet>

  `detail_value/1` is for a value that may be missing - it draws a dash
  for none - and for a slug or id, which it draws in monospace when asked
  with `code`.
  """

  use Phoenix.Component

  attr(:class, :any, default: nil)
  slot(:inner_block, required: true, doc: "the `detail/1` cells")

  def fact_sheet(assigns) do
    ~H"""
    <div class={["p-6 border border-zinc-300 rounded-lg", @class]}>
      <dl class="grid grid-cols-1 gap-4 md:grid-cols-4">
        {render_slot(@inner_block)}
      </dl>
    </div>
    """
  end

  @doc "One cell of the sheet: the label a field would carry, the value under it."
  attr(:label, :string, required: true)
  slot(:inner_block, required: true)

  def detail(assigns) do
    ~H"""
    <div class="min-w-0">
      <dt class="text-sm font-medium text-zinc-500">{@label}</dt>
      <dd class="mt-0.5 text-sm">{render_slot(@inner_block)}</dd>
    </div>
    """
  end

  @doc "A value of the sheet: a dash for none, monospace for a slug or id."
  attr(:value, :any, default: nil)
  attr(:code, :boolean, default: false)

  def detail_value(%{value: empty} = assigns) when empty in [nil, ""] do
    ~H"""
    <span class="text-zinc-400">-</span>
    """
  end

  def detail_value(%{code: true} = assigns) do
    ~H"""
    <code class="text-xs">{@value}</code>
    """
  end

  def detail_value(assigns) do
    ~H"""
    {@value}
    """
  end
end
