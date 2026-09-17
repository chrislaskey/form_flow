defmodule FormFlow.Web.Components.Tabs do
  @moduledoc """
  `FormFlow.Web.Components.Tabs` function component renders a **segmented
  control**: a few views of one thing side by side in a grey capsule, the
  chosen one white, each of the others a link to its own URL.

  Both sides of the library draw one in the page header. A flow template's
  pages offer Edit | View | Overview | History
  (`FormFlow.Web.Templates.Components.Flows.Tabs`); a form inside a flow
  instance offers Edit | View | History
  (`FormFlow.Web.Instances.Components.Forms.Tabs`). Those two modules know
  the URLs; this one only draws what it is given.

  The views are **paths**, not a mode held in the page, so each is a link
  someone can be sent, survives a refresh, and is the same URL it was before
  the control existed. The chosen one is text with `aria-current="page"`,
  never a link to itself.

  Two navigation styles, as `FormFlow.Web.Templates.Components.Header` has:

    * `target` unset - every other tab is a plain `<.link navigate>`
    * `target` set - every other tab is a button pushing `"navigate"` with
      `phx-value-to` to that target, the way the flow editor leaves through
      its own event so unsaved changes prompt first
  """

  use Phoenix.Component

  attr(:items, :list, required: true, doc: "`{key, label, path}` triples, in order")
  attr(:active, :atom, required: true, doc: "the key of the view this page is")
  attr(:label, :string, default: "Views", doc: "the control's `aria-label`")

  attr(:target, :any,
    default: nil,
    doc: "set to leave through the \"navigate\" event instead of linking directly"
  )

  attr(:class, :any, default: nil)

  def tabs(assigns) do
    ~H"""
    <nav class={["inline-flex rounded-lg bg-zinc-100 p-0.5 text-sm", @class]} aria-label={@label}>
      <%= for {key, label, to} <- @items do %>
        <span
          :if={key == @active}
          class="rounded-md bg-white px-3 py-1 font-semibold shadow-sm"
          aria-current="page"
        >
          {label}
        </span>
        <.link
          :if={key != @active and is_nil(@target)}
          navigate={to}
          class="rounded-md px-3 py-1 text-zinc-500 hover:text-zinc-900"
        >
          {label}
        </.link>
        <button
          :if={key != @active and not is_nil(@target)}
          type="button"
          phx-click="navigate"
          phx-value-to={to}
          phx-target={@target}
          class="rounded-md px-3 py-1 text-zinc-500 hover:text-zinc-900"
        >
          {label}
        </button>
      <% end %>
    </nav>
    """
  end
end
