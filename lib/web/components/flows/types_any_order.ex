defmodule FormFlow.Web.Components.Flows.Types.AnyOrder do
  @moduledoc """
  Flow type `"any_order"`: a "subflows" flow whose subflows can be worked in
  any order. Any unfinished step can be entered, whatever comes before it,
  and finishing one moves to the next still unfinished - wrapping back to
  the front, since the user may have skipped something there. The any-order
  wizard's rule, one level up; the flows inside keep their own.
  """

  use FormFlow.Config.Flows.Type

  alias FormFlow.Context
  alias FormFlow.Data.Instances.SubflowProgress

  @impl true
  def enterable?(%Context{subflow_progress: %SubflowProgress{} = step}, _callback_data),
    do: unfinished?(step)

  def enterable?(%Context{subflow_progress: nil}, _callback_data), do: false

  @impl true
  def handle_complete(%Context{complex_progress: steps, subflow_progress: current}, _data) do
    steps = steps || []
    index = current && Enum.find_index(steps, &(&1.path == current.path))
    {before_current, after_current} = Enum.split(steps, (index || -1) + 1)

    Enum.find(after_current ++ before_current, &unfinished?/1)
  end

  defp unfinished?(%SubflowProgress{status: status}), do: status != :completed
end
