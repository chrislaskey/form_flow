defmodule DemoWeb.FormFlowLive.Users.Checklist do
  @moduledoc """
  The demo's own form flow type, behind the `"demo_checklist"` option the
  admin page offers: a checklist rather than a wizard.

  It overrides all three `FormFlow.Flows.Types` callbacks, which is the whole
  surface a type has:

    * every form is open until it's done, so there is no order to obey
    * finishing one returns to the top of the list — the first form still
      open — rather than pushing forward through the flow
    * the list is always drawn, even for a flow with a single form, because
      here it is the point rather than a progress indicator

  A type that only wanted to change *one* of those would override just that
  callback and inherit the rest from `FormFlow.Flows.Types` (the in-order
  wizard's behavior), the same way this app's config modules extend
  `FormFlow.Config`.
  """

  use FormFlow.Flows.Types

  @impl true
  def show_progress?(_forms), do: true

  @impl true
  def openable?(form, _forms), do: open?(form)

  @impl true
  def next_form(forms, _current_path), do: Enum.find(forms, &open?(&1))

  defp open?(form), do: form.status != :completed
end
