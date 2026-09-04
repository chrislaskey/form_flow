defmodule DemoWeb.FormFlowLive.Checklist do
  @moduledoc """
  The demo's own flow type, behind the `"demo_checklist"` option
  `DemoWeb.FormFlowLive.Config` offers: a checklist rather than a wizard.

  It overrides all three `FormFlow.Config.Flows.Type` callbacks, which is the
  whole surface a type has:

    * every form can be edited until it's done, so there is no order to obey
    * finishing one returns to the top of the list — the first form still
      unfinished — rather than pressing forward through the flow
    * the list is always drawn, even for a flow with a single form, because
      here it is the point rather than a progress indicator

  A type that only wanted to change *one* of those would override just that
  callback and inherit the rest (the in-order wizard's behavior), the same
  way the demo's type lists extend the library's defaults.
  """

  use FormFlow.Config.Flows.Type

  @impl true
  def editable?(%{form_progress: form}, _callback_data), do: unfinished?(form)

  @impl true
  def handle_complete(%{flow_progress: forms}, _callback_data),
    do: Enum.find(forms, &unfinished?/1)

  @impl true
  def progress_component(assigns) do
    FormFlow.Web.Instances.Components.Flows.Progress.flow_progress(assigns)
  end

  defp unfinished?(form), do: form.status != :completed
end
