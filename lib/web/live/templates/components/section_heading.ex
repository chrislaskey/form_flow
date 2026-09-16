defmodule FormFlow.Web.Templates.Components.SectionHeading do
  @moduledoc """
  `FormFlow.Web.Templates.Components.SectionHeading` function component
  heads a part of a templates page: its title and one line saying what
  belongs there, styled like DynamicForm's own nested-form heading so a
  page's sections read as one family with its Elements.

  Actions ride on the right of the title's line. A plain-string
  `description` sits under the title on the left, sharing the row with the
  actions; anything richer - links, conditional spans - goes in the inner
  block, which takes the full line under both so a sentence that reads
  across is not squeezed into the column beside the controls.

      <SectionHeading.section_heading
        title="Form details"
        description="What every version of this form shares."
      >
        <:actions>
          <Core.button navigate={...}>Edit form details</Core.button>
        </:actions>
      </SectionHeading.section_heading>
  """

  use Phoenix.Component

  attr(:title, :string, required: true)
  attr(:description, :string, default: nil)
  attr(:class, :any, default: nil)
  slot(:actions)
  slot(:inner_block)

  def section_heading(assigns) do
    ~H"""
    <div class={["min-w-0", @class]}>
      <div class="flex items-center justify-between gap-3">
        <div class="min-w-0">
          <h3 class="text-lg font-bold">{@title}</h3>
          <div :if={@description} class="text-gray-500">{@description}</div>
        </div>
        <div :if={@actions != []} class="flex shrink-0 items-center gap-2">
          {render_slot(@actions)}
        </div>
      </div>
      <div :if={@inner_block != []} class="text-gray-500">{render_slot(@inner_block)}</div>
    </div>
    """
  end
end
