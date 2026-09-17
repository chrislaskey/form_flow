defmodule FormFlow.Web.Components.Flows.Types.InOrder do
  @moduledoc """
  Flow type `"in_order"`: a "subflows" flow whose subflows are worked front
  to back. A step can be entered once every step before it is done, and
  finishing one moves to the first step the flow allows work in - the
  defaults, which this module inherits whole.
  """

  use FormFlow.Config.Flows.Type
end
