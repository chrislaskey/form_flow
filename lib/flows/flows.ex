defmodule FormFlow.Flows do
  @moduledoc """
  `FormFlow.Flows` namespace for how a flow *behaves* — neither its storage
  (`FormFlow.Data`) nor its presentation (`FormFlow.Web`), but the rules both
  of those defer to.

  Today that is one thing: `FormFlow.Flows.Types`, the `form_flow_type`
  behaviour deciding how a "forms" flow's forms are presented to the person
  filling them out, and which of them that person may open.
  """
end
