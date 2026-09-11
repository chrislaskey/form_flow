defmodule FormFlow.Web.Templates.Components.ChoiceCard do
  @moduledoc """
  `FormFlow.Web.Templates.Components.ChoiceCard` function component renders one
  radio as a card: its name, a line under it saying what picking it does, and
  the whole card filled when it is the one picked.

  For the choices a page makes a decision out of rather than collects an
  answer to — what kind of flow to create, which editor the draft is edited in.
  A row of plain radios cannot say what each one does before it is clicked, and
  these choices differ in consequence, not just in kind.

      <ChoiceCard.choice_card name="label" value="forms" checked label="Simple flow">
        A single flow with one or more forms
      </ChoiceCard.choice_card>

  The fill is daisyUI's `primary`, so the card wears the host application's
  brand color rather than one of FormFlow's own, and the description follows
  the card's text color into it as `opacity` rather than as a second palette
  that would have to be picked for every theme a host might set. The radio is
  the browser's own, undressed: an accent that followed the fill read as a
  smudge rather than as a control.

  `name`, `value`, and `checked` are the radio's, so the control works the same
  bound to a `DynamicForm` field as it does in a plain form; `class` is the
  caller's layout (a row that shares its width, a stacked list).
  """

  use Phoenix.Component

  attr(:id, :any, default: nil)
  attr(:name, :string, required: true)
  attr(:value, :string, required: true)
  attr(:checked, :boolean, default: false)
  attr(:label, :string, required: true)
  attr(:class, :any, default: nil, doc: "layout classes for the card in its row or list")
  slot(:inner_block, required: true, doc: "what picking this choice does, in a line")

  def choice_card(assigns) do
    ~H"""
    <label class={[
      "flex cursor-pointer items-start gap-2 rounded-md border border-zinc-300 p-3 text-sm",
      "has-[:checked]:border-primary has-[:checked]:bg-primary has-[:checked]:text-primary-content",
      @class
    ]}>
      <input
        type="radio"
        id={@id}
        name={@name}
        value={@value}
        checked={@checked}
        class="mt-1"
      />
      <span class="min-w-0">
        <span class="block font-medium">{@label}</span>
        <span class="block text-xs opacity-70">{render_slot(@inner_block)}</span>
      </span>
    </label>
    """
  end
end
