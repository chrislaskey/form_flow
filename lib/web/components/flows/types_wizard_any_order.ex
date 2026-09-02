defmodule FormFlow.Web.Components.Flows.Types.WizardAnyOrder do
  @moduledoc """
  Flow type `"wizard_any_order"`: a "forms" flow whose forms can be completed
  in any order. Every form that isn't done can be edited, so the user can
  jump ahead, and completing one moves them to the next form still
  unfinished — wrapping back to the beginning, since they may have skipped
  something there. When every form is done it hands them back to the flow
  instance.
  """

  use FormFlow.Config.Flows.Type

  alias FormFlow.Context
  alias FormFlow.Data.Instances.FormProgress

  @impl true
  def editable?(%Context{form_progress: form}, _config_data), do: unfinished?(form)

  @impl true
  def handle_complete(%Context{flow_progress: forms, form_progress: current}, _config_data) do
    index = current && Enum.find_index(forms, &(&1.path == current.path))
    {before_current, after_current} = Enum.split(forms, (index || -1) + 1)

    Enum.find(after_current ++ before_current, &unfinished?/1)
  end

  defp unfinished?(%FormProgress{status: status}), do: status != :completed
end
