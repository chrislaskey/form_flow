defmodule FormFlow.Web.Components.Dialog do
  @moduledoc """
  `FormFlow.Web.Components.Dialog` function component renders the box every
  confirmation in this library asks its question in: a dimmed page, and a
  white panel centred on it.

  It is the panel alone - the title, the prose, the choices and the buttons
  are the caller's, because no two of these questions are shaped alike. What
  it owns is what every one of them had copied: the overlay, the border, the
  shadow, the padding inside, and how wide the panel may grow.

      <Dialog.dialog :if={@confirming?} width={:medium}>
        <p class="mb-2 text-base font-semibold text-zinc-900">Reopen form?</p>
        ...
      </Dialog.dialog>

  `width` is a size, not a measurement, so the nine dialogs land on three
  widths instead of on five: `:small` for a yes-or-no, `:medium` for one
  that explains itself first, `:large` for one carrying a form. Each is a
  maximum - the panel shrinks on a narrow screen rather than running off it,
  and the overlay's own padding keeps it off the edges.

  A panel taller than the window scrolls inside itself. It never scrolls
  sideways: a panel is only as wide as it is allowed to be, so anything that
  does not fit has to wrap. That is the rule the publish dialog was breaking
  when its radio labels ran out past the border.
  """

  use Phoenix.Component

  attr(:width, :atom,
    default: :medium,
    values: [:small, :medium, :large],
    doc: "how wide the panel may grow - see the moduledoc"
  )

  attr(:class, :any, default: nil, doc: "extra classes for the panel")
  slot(:inner_block, required: true, doc: "the question, its choices, and its buttons")

  def dialog(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4">
      <div class={[
        "max-h-[90vh] w-full overflow-y-auto overflow-x-hidden",
        "rounded-xl border border-zinc-300 bg-white p-6 shadow-lg",
        width_class(@width),
        @class
      ]}>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  defp width_class(:small), do: "max-w-sm"
  defp width_class(:medium), do: "max-w-lg"
  defp width_class(:large), do: "max-w-2xl"
end
