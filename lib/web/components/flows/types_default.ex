defmodule FormFlow.Web.Components.Flows.Types.Default do
  @moduledoc """
  `FormFlow.Config.Flows.Type`'s defaults — what every flow type inherits for
  the callbacks it doesn't override.
  """

  use FormFlow.Config.Flows.Type

  @impl true
  def form_progress_component(assigns) do
    FormFlow.Web.Instances.Components.Flows.Progress.flow_progress(assigns)
  end
end
