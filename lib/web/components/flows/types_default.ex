defmodule FormFlow.Web.Components.Flows.Types.Default do
  @moduledoc """
  `FormFlow.Config.Flows.Type`'s defaults — what every flow type inherits for
  the callbacks it doesn't override. Together they are the in-order wizard:
  a form can be edited where the flow allows work (its predecessors done, or
  itself already started), completing one moves to the nearest such form,
  and the flow's progress is drawn whenever there is a sequence to draw.
  """

  use FormFlow.Config.Flows.Type

  alias FormFlow.Context
  alias FormFlow.Data.Instances.FlowProgress
  alias FormFlow.Web.Instances.Components

  @impl true
  def editable?(%Context{form_progress: form}, _config_data), do: FlowProgress.actionable?(form)

  @impl true
  def handle_complete(%Context{flow_progress: forms}, _config_data) do
    Enum.find(forms, &FlowProgress.actionable?/1)
  end

  # A lone form is no sequence.
  @impl true
  def progress_component(%{forms: forms}) when length(forms) < 2, do: nil
  def progress_component(assigns), do: Components.Flows.Progress.flow_progress(assigns)
end
