defmodule FormFlow.Web.Instances.Components.Forms.Tabs do
  @moduledoc """
  `FormFlow.Web.Instances.Components.Forms.Tabs` function component renders
  the three views of one form inside a flow instance as a segmented control
  (`FormFlow.Web.Components.Tabs`) - **Edit**, **View**, **History** - each
  a link to its own URL:

    * Edit - `/:id/forms/*path/edit`, `FormFlow.Web.Instances.Forms.Edit`
    * View - `/:id/forms/*path`, `FormFlow.Web.Instances.Forms.Show`
    * History - `/:id/forms/*path/history`, `FormFlow.Web.Instances.Forms.History`

  All three are always offered: a view with nothing to show says so on its
  own page - Edit on a submitted form says it was submitted and points back
  at the answers - so the row never changes shape as the form moves along.

  `reopen_first?` is the one exception to going straight there. A submitted
  form that may be reopened has nothing to edit until it is, so from View
  and History the Edit tab asks - it pushes `"request_reopen"` at `target`,
  which draws `FormFlow.Web.Instances.Components.ReopenDialog`, and only a
  confirmed reopen lands on Edit. Cancelling leaves the user where they
  were. Edit's own page keeps its Reopen button for whoever arrives at that
  URL directly.

  Sits among the header's actions on the three pages, right of the page's
  own buttons.
  """

  use Phoenix.Component

  alias FormFlow.Web.Components.Tabs
  alias FormFlow.Web.Instances.Paths

  attr(:base, :string, required: true)
  attr(:flow_instance_id, :string, required: true)
  attr(:path, :list, required: true, doc: "the position, as the pages address it")
  attr(:active, :atom, required: true, values: [:edit, :show, :history])

  attr(:reopen_first?, :boolean,
    default: false,
    doc:
      "Edit asks to reopen the form rather than going to a page that would only say it was submitted"
  )

  attr(:target, :any, default: nil, doc: "the LiveComponent asked, when `reopen_first?`")
  attr(:class, :any, default: nil)

  def tabs(assigns) do
    %{base: base, flow_instance_id: id, path: path} = assigns

    assigns =
      assigns
      |> assign(:items, [
        {:show, "View", Paths.form_path(base, id, path)},
        {:history, "History", Paths.form_history_path(base, id, path)},
        {:edit, "Edit", Paths.form_edit_path(base, id, path)}
      ])
      |> assign(:events, (assigns.reopen_first? && %{edit: "request_reopen"}) || %{})

    ~H"""
    <Tabs.tabs items={@items} active={@active} events={@events} target={@target} class={@class} />
    """
  end
end
