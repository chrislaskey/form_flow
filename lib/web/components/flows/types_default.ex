defmodule FormFlow.Web.Components.Flows.Types.Default do
  use FormFlow.Config.Flows.Type

  def form_progress_component(assigns) do
    FormFlow.Web.Instances.Components.Flows.Progress.flow_progress(assigns)
  end
end
