defmodule FormFlow.Web.Templates.Components.Note do
  @moduledoc """
  `FormFlow.Web.Templates.Components.Note` function component renders a
  templates page's note: a sentence the admin should read before using the
  page, with the links it needs — where the form's details are edited, that
  a save here reaches every version.

  A bordered white card the width of the page, opening with **Note:**, so it
  reads as part of the page rather than as an alert about something that
  went wrong.

      <Note.note class="mb-6">
        These details are shared by every version.
        <.link navigate={...} class="link link-primary font-medium">Edit form details</.link>
      </Note.note>
  """

  use Phoenix.Component

  attr(:class, :any, default: nil)
  slot(:inner_block, required: true)

  def note(assigns) do
    ~H"""
    <div class={["rounded-md border border-zinc-200 bg-white px-4 py-3 text-sm text-zinc-700", @class]}>
      <span class="font-bold">Note:</span> {render_slot(@inner_block)}
    </div>
    """
  end
end
