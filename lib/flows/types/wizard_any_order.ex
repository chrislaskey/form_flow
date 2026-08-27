defmodule FormFlow.Flows.Types.WizardAnyOrder do
  @moduledoc """
  `form_flow_type` `"wizard_any_order"`: a "forms" flow's forms can be
  completed in any order. Every form that isn't done is navigable, so the
  filler can jump ahead, and completing one moves them to the next form still
  open — wrapping back to the beginning, since they may have skipped
  something there. When nothing in the flow is open any more it hands them
  back to the flow.

  `show_progress?/1` is `FormFlow.Flows.Types`' default: a lone form is still
  no sequence.
  """

  use FormFlow.Flows.Types

  alias FormFlow.Data.Instances.FormProgress

  @impl true
  def openable?(form, _forms), do: open?(form)

  @impl true
  def next_form(forms, current_path) do
    index = Enum.find_index(forms, &(&1.path == current_path))
    {before_current, after_current} = Enum.split(forms, (index || -1) + 1)

    Enum.find(after_current ++ before_current, &open?(&1))
  end

  defp open?(%FormProgress{status: status}), do: status != :completed
end
