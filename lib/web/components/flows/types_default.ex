defmodule FormFlow.Web.Components.Flows.Types.Default do
  @moduledoc """
  `FormFlow.Config.Flows.Type`'s defaults - what every flow type inherits for
  the callbacks it doesn't override. Together they are "in order" for both
  kinds of flow. For a "forms" flow, the in-order wizard: its forms are for
  the viewer when its perspectives say so, a form can be edited where the
  flow allows work (its predecessors done, or itself already started),
  completing one moves to the nearest such form, and the flow's progress is
  drawn whenever there is a sequence to draw. For a "subflows" flow: a step
  can be entered once every step before it is done - which is what its
  derived status already says (`FormFlow.Data.Instances.FlowProgress`'s
  AND-join) - and finishing one moves to the first step the flow allows work
  in.

  `handle_complete/2` answers whichever question the context asks: the step
  question when it carries `:complex_progress`, the form question otherwise.
  """

  use FormFlow.Config.Flows.Type

  alias FormFlow.Config.Flows.Perspective
  alias FormFlow.Context
  alias FormFlow.Data.Instances.FlowProgress
  alias FormFlow.Data.Instances.SubflowProgress
  alias FormFlow.Web.Instances.Components

  @impl true
  def visible?(%Context{} = context, _callback_data), do: Perspective.visible?(context)

  @impl true
  def editable?(%Context{form_progress: form}, _callback_data), do: FlowProgress.actionable?(form)

  @impl true
  def enterable?(%Context{subflow_progress: %SubflowProgress{status: status}}, _callback_data),
    do: status in [:available, :in_progress]

  def enterable?(%Context{subflow_progress: nil}, _callback_data), do: false

  @impl true
  def handle_complete(%Context{complex_progress: steps}, _callback_data) when is_list(steps) do
    Enum.find(steps, &(&1.status in [:available, :in_progress]))
  end

  def handle_complete(%Context{flow_progress: forms}, _callback_data) do
    Enum.find(forms || [], &FlowProgress.actionable?/1)
  end

  # A lone form is no sequence.
  @impl true
  def progress_component(%{forms: forms}) when length(forms) < 2, do: nil
  def progress_component(assigns), do: Components.Flows.Progress.flow_progress(assigns)
end
