defmodule FormFlow.Web.Templates.Forms.Components.Canvas do
  @moduledoc """
  `FormFlow.Web.Templates.Forms.Components.Canvas` function component is the
  surface a form preview sits on: the dotted canvas the flow editor draws,
  at the scale of one form, with the preview on it as a card at `max-w-3xl`.
  Given more width the canvas grows around the form rather than stretching
  it, and the dots keep the same 16px pitch the editor uses, so a form and a
  flow are looked at on the same kind of surface.

  A definition holding no elements gets the `:empty` slot in place of the
  card — such a definition renders as a form whose only control is Submit,
  which reads as broken rather than unstarted. The definition arrives either
  as the JSON string an editor holds or as the map a saved version carries.
  One that cannot be parsed is not empty: it goes to the preview, which says
  what is wrong with it.

  Rendered by `FormFlow.Web.Templates.Forms.Show` and `Edit`.
  """

  use Phoenix.Component

  attr(:definition, :any,
    required: true,
    doc: "the definition being previewed, as a JSON string or a map"
  )

  attr(:components, :atom,
    default: nil,
    doc: "the host's components module, for whatever this draws through `Core`"
  )

  attr(:class, :any, default: nil)

  slot(:empty, doc: "the line under \"Nothing to preview yet\", saying how to fill this version")
  slot(:inner_block, required: true, doc: "the preview itself")

  def canvas(assigns) do
    assigns = assign(assigns, :empty?, empty?(assigns.definition))

    ~H"""
    <div class={[
      "rounded-md border border-zinc-200 bg-white p-6",
      "bg-[radial-gradient(#d4d4d8_1px,transparent_1px)] [background-size:16px_16px]",
      @class
    ]}>
      <div :if={@empty?} class="mx-auto max-w-3xl px-6 py-16 text-center">
        <p class="font-medium text-zinc-900">Nothing to preview yet</p>
        <p :if={@empty != []} class="mx-auto mt-1 max-w-sm text-sm text-zinc-500">
          {render_slot(@empty)}
        </p>
      </div>
      <div
        :if={!@empty?}
        class="mx-auto max-w-3xl rounded-lg border border-zinc-200 bg-white p-6 shadow-sm"
      >
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  defp empty?(json) when is_binary(json) do
    case Phoenix.json_library().decode(json) do
      {:ok, definition} -> empty?(definition)
      {:error, _} -> false
    end
  end

  defp empty?(%{"elements" => [_ | _]}), do: false
  defp empty?(%{"pages" => [_ | _]}), do: false
  defp empty?(%{}), do: true
  defp empty?(_), do: false
end
