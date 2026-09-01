defmodule DemoWeb.FormFlowLive.Config do
  @moduledoc """
  The demo's `FormFlow.Config`, passed to both the admin and users pages:
  demonstrates extending a callback while keeping the library's defaults —
  the demo offers one custom flow type on top of the built-in wizards. The
  defaults are reachable through `FormFlow.Config.config_module/1` exactly
  for this, so an override doesn't have to restate the core options.

  One module serves both pages because a type is chosen on the admin side
  (the flow edit page's dropdown) and acted on in the users side (which forms
  a user may edit) — the same list has to answer in both places. What the
  checklist *does* is `DemoWeb.FormFlowLive.Checklist`.
  """

  use FormFlow.Config

  # The checklist joins the built-in types wherever they are offered; a flow
  # the defaults give no types (a "subflows" flow) gets none here either.
  @impl true
  def enabled_flow_types(context, config_data) do
    defaults = FormFlow.Config.config_module(nil)

    case defaults.enabled_flow_types(context, config_data) do
      [] -> []
      types -> types ++ [checklist()]
    end
  end

  defp checklist do
    %FormFlow.Config.Flows.Type{
      id: "demo_checklist",
      module: DemoWeb.FormFlowLive.Checklist,
      name: "Demo checklist",
      description: "A checklist rather than a wizard.",
      properties: []
    }
  end
end
