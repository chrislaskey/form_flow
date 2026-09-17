defmodule FormFlow.Web.Instances.Components.Flows.Tabs do
  @moduledoc """
  `FormFlow.Web.Instances.Components.Flows.Tabs` function component renders
  the two views of one flow instance as a segmented control
  (`FormFlow.Web.Components.Tabs`) - **Overview**, **History** - each a
  link to its own URL:

    * Overview - `/:id`, `FormFlow.Web.Instances.Flows.Show`: the forms
      and where the viewer stands among them
    * History - `/:id/history`, `FormFlow.Web.Instances.Flows.History`:
      what has happened in the instance, newest first

  Both are always offered. Sits among the header's actions on the two
  pages, left of Download all, as the form pages' Edit | View | History
  sits left of their buttons.
  """

  use Phoenix.Component

  alias FormFlow.Web.Components.Tabs
  alias FormFlow.Web.Instances.Paths

  attr(:base, :string, required: true)
  attr(:flow_instance_id, :string, required: true)
  attr(:active, :atom, required: true, values: [:show, :history])
  attr(:class, :any, default: nil)

  def tabs(assigns) do
    %{base: base, flow_instance_id: id} = assigns

    assigns =
      assign(assigns, :items, [
        {:show, "Overview", Paths.flow_path(base, id)},
        {:history, "History", Paths.flow_history_path(base, id)}
      ])

    ~H"""
    <Tabs.tabs items={@items} active={@active} class={@class} />
    """
  end
end
