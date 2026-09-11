defmodule FormFlow.Web.Templates.Components.Health do
  @moduledoc """
  `FormFlow.Web.Templates.Components.Health` function component draws one
  root flow's health as a badge that links to its health page
  (`FormFlow.Web.Templates.Flows.Health`): a bordered icon button with a
  mark on its shoulder — the count of open **errors and warnings** in the
  colour of the worst, a check when there are none, and a grey dash for a
  flow never checked. The check is green when nothing at all is open, and in
  the info colour when only `:info` entries are — a draft with unpublished
  changes is the normal state of a form being worked on, and a flow with
  nothing wrong should read as healthy while that work goes on; the tooltip
  says "healthy · 2 to review", and the page lists them. The stethoscope is
  `FormFlow.Web.Components.Core.icon/1`'s own clause — Heroicons has none,
  so it is drawn inline rather than asked of the host, and a host needs no
  icon set for it.

  It reads the **cached status** off the flow struct it is given
  (`FormFlow.Data.Templates.Flows.Health.status/1`) and runs nothing: the
  flows index draws one per row from the rows it already has, and the flow
  pages one in their header from the root they already loaded. The page it
  links to runs the check and writes the cache, so a flow never checked
  gets its badge on its first visit. A drill-in page passes its **root**:
  health is the root's, and a subflow's own properties never carry it.

      <Health.health base={@base} flow={@root || @flow} components={@components} />

  With `target` — the flow edit page's own `@myself` — the badge pushes the
  `"navigate"` event with `phx-value-to` instead of linking directly, the
  same way that page's crumbs and buttons do, so an unsaved edit still
  prompts before the badge leaves the page.
  """

  use Phoenix.Component

  alias FormFlow.Data.Templates.Flows.Health
  alias FormFlow.Web.Components.Core

  attr(:base, :string, required: true)
  attr(:flow, :map, required: true, doc: "the root `FormFlow.Data.Templates.Flow`")

  attr(:components, :atom,
    default: nil,
    doc: "the host's components module, for whatever this draws through `Core`"
  )

  attr(:target, :any,
    default: nil,
    doc: "set to go through the \"navigate\" event instead of linking directly"
  )

  def health(assigns) do
    status = Health.status(assigns.flow)

    assigns =
      assign(assigns,
        status: status,
        to: "#{assigns.base}/flows/#{assigns.flow.id}/health",
        words: "Health: #{words(status)}"
      )

    ~H"""
    <.link :if={!@target} navigate={@to} class={button_class()} aria-label={@words} title={@words}>
      <.badge status={@status} components={@components} />
    </.link>
    <button
      :if={@target}
      type="button"
      phx-click="navigate"
      phx-value-to={@to}
      phx-target={@target}
      class={button_class()}
      aria-label={@words}
      title={@words}
    >
      <.badge status={@status} components={@components} />
    </button>
    """
  end

  attr(:status, :map, default: nil)
  attr(:components, :atom, default: nil)

  defp badge(assigns) do
    ~H"""
    <Core.icon components={@components} name="stethoscope" class="size-5" />
    <span class={[
      "absolute -right-1 -top-1 inline-flex h-5 min-w-5 items-center justify-center rounded-full px-1 text-[10px] font-semibold ring-2 ring-white",
      colors(@status)
    ]}>
      {mark(@status)}
    </span>
    """
  end

  defp button_class do
    "relative inline-flex size-10 items-center justify-center rounded-lg bg-white text-zinc-700 hover:bg-zinc-50 mx-1"
  end

  # The shoulder: a dash for a flow never checked, a check for one with
  # nothing wrong, else the count of what is
  defp mark(nil), do: "–"
  defp mark(status), do: if(Health.healthy?(status), do: "✓", else: Health.wrong(status))

  # The badges' colours, solid, in the worst open level's; grey for none
  defp colors(nil), do: "bg-zinc-200 text-zinc-600"
  defp colors(%{level: :ok}), do: "bg-success text-success-content"
  defp colors(%{level: :error}), do: "bg-error text-error-content"
  defp colors(%{level: :warning}), do: "bg-warning text-warning-content"
  defp colors(%{level: :info}), do: "bg-info text-info-content"

  # For the button's label, since the icon says nothing on its own
  defp words(nil), do: "not checked yet — open to check"
  defp words(%{level: :ok}), do: "healthy"
  defp words(%{level: :info, counts: counts}), do: "healthy · #{counts.info} to review"
  defp words(status), do: "#{Health.wrong(status)} to look at"
end
