defmodule FormFlow.Web.Templates.Components.Flows.Tabs do
  @moduledoc """
  `FormFlow.Web.Templates.Components.Flows.Tabs` function component renders
  the four views of one flow template as a segmented control
  (`FormFlow.Web.Components.Tabs`) - **Edit**, **View**, **Overview**,
  **History** - each a link to its own URL:

    * Edit - the canvas editable, `FormFlow.Web.Templates.Flows.Edit`:
      `/flows/:id/edit`, or `/flows/:root_id/nodes/:node_id/edit` for an
      owned subflow reached through its step
    * View - the same level read-only, `FormFlow.Web.Templates.Flows.Show`
    * Overview - the whole root flow at once, every level, read-only,
      `FormFlow.Web.Templates.Flows.Overview` at `/flows/:root_id/overview`
    * History - the root's log, `FormFlow.Web.Templates.Flows.History` at
      `/flows/:root_id/history`

  Edit and View are one level at a time, so from inside a subflow they stay
  inside it; Overview and History are the root's from any depth, as its
  health is. The Overview and History pages are root pages, so their Edit
  and View lead to the root's.

  It replaced three things that sat apart in the header: the Show / Edit
  switch, the Flow Overview button, and the History button.

  `target` is the flow editor's: every way off that page goes through its
  `"navigate"` event so unsaved changes prompt first, and the tabs go the
  same way when it is set.
  """

  use Phoenix.Component

  alias FormFlow.Web.Components.Tabs

  attr(:base, :string, required: true)
  attr(:flow, :map, required: true, doc: "the `FormFlow.Data.Templates.Flow` on the page")

  attr(:root_id, :string,
    default: nil,
    doc: "the root's id when the page is a drill-in through a step; nil at the root"
  )

  attr(:node_id, :string,
    default: nil,
    doc: "the step the subflow was reached through; nil at the root"
  )

  attr(:active, :atom, required: true, values: [:edit, :show, :overview, :history])
  attr(:target, :any, default: nil, doc: "the editor's `@myself`, to leave through its event")
  attr(:class, :any, default: nil)

  def tabs(assigns) do
    root_id = assigns.root_id || assigns.flow.id

    assigns =
      assign(assigns, :items, [
        {:edit, "Edit", level_path(assigns) <> "/edit"},
        {:show, "View", level_path(assigns)},
        {:overview, "Overview", "#{assigns.base}/flows/#{root_id}/overview"},
        {:history, "History", "#{assigns.base}/flows/#{root_id}/history"}
      ])

    ~H"""
    <Tabs.tabs items={@items} active={@active} target={@target} class={@class} />
    """
  end

  # This level's show URL: the flow's own, or the step it was reached through
  defp level_path(%{node_id: nil} = assigns), do: "#{assigns.base}/flows/#{assigns.flow.id}"

  defp level_path(assigns),
    do: "#{assigns.base}/flows/#{assigns.root_id}/nodes/#{assigns.node_id}"
end
