defmodule FormFlow.Config.Flows.Type.Default do
  @moduledoc """
  The public face of `FormFlow.Config.Flows.Type`'s defaults — the in-order
  wizard's behavior, for a custom type to reach when its override wants to
  build on the default rather than replace it.

  Delegates to the private internal implementation in
  `FormFlow.Web.Components.Flows.Types.Default`,
  """

  @behaviour FormFlow.Config.Flows.Type

  alias FormFlow.Web.Components.Flows.Types

  defdelegate editable?(context, config_data), to: Types.Default
  defdelegate handle_complete(context, config_data), to: Types.Default
  defdelegate progress_component(assigns), to: Types.Default
end
