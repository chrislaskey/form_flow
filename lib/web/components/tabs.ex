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
    * `target` set and `events` empty - every other tab is a button pushing
      `"navigate"` with `phx-value-to` to that target, the way the flow
      editor leaves through its own event so unsaved changes prompt first

  `events` names one tab at a time rather than all of them: the key's own
  event goes to `target` in place of its link, which is how a form's Edit
  tab asks to reopen a submitted form instead of walking to a page that
  would only say it was submitted. Naming one tab leaves the rest ordinary
  links - a caller that wants every tab routed through itself names none.
  """

  use Phoenix.Component

  attr(:items, :list, required: true, doc: "`{key, label, path}` triples, in order")
  attr(:active, :atom, required: true, doc: "the key of the view this page is")
  attr(:label, :string, default: "Views", doc: "the control's `aria-label`")

  attr(:target, :any,
    default: nil,
    doc: "set to leave through the \"navigate\" event instead of linking directly"
  )

  attr(:events, :map,
    default: %{},
    doc:
      "one key's own event at `target` in place of its link - " <>
        "`%{edit: \"request_reopen\"}` for a tab that has to ask before it goes"
  )

  attr(:class, :any, default: nil)

  def tabs(assigns) do
    assigns =
      assign(
        assigns,
        :items,
        Enum.map(assigns.items, fn {key, label, to} -> {key, label, to, mode(key, assigns)} end)
      )

    ~H"""
    <nav class={["inline-flex rounded-lg bg-zinc-100 p-1 text-sm", @class]} aria-label={@label}>
      <%= for {key, label, to, mode} <- @items do %>
        <span
          :if={mode == :current}
          class="rounded-md bg-white px-3 py-1.5 font-semibold text-primary shadow-sm"
          aria-current="page"
        >
          {label}
        </span>
        <.link
          :if={mode == :link}
          navigate={to}
          class="rounded-md px-3 py-1.5 text-zinc-500 hover:text-zinc-900"
        >
          {label}
        </.link>
        <button
          :if={mode == :ask}
          type="button"
          phx-click={@events[key]}
          phx-target={@target}
          class="rounded-md px-3 py-1.5 text-zinc-500 hover:text-zinc-900"
        >
          {label}
        </button>
        <button
          :if={mode == :navigate}
          type="button"
          phx-click="navigate"
          phx-value-to={to}
          phx-target={@target}
          class="rounded-md px-3 py-1.5 text-zinc-500 hover:text-zinc-900"
        >
          {label}
        </button>
      <% end %>
    </nav>
    """
  end

  # What one tab is: the page itself; its own event, when `events` names it;
  # the "navigate" event, when the caller routes every tab through itself;
  # an ordinary link otherwise. Naming one tab in `events` leaves the rest
  # links - only a caller that names none is asking for all of them.
  defp mode(key, %{active: key}), do: :current

  defp mode(key, assigns) do
    cond do
      assigns.events[key] -> :ask
      assigns.target && assigns.events == %{} -> :navigate
      true -> :link
    end
  end
end
