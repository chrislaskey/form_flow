defmodule DemoWeb.FormFlowLive.Admin.Config do
  @moduledoc """
  The admin page's `FormFlow.Config`: demonstrates extending a callback while
  keeping the library's defaults — the demo offers one custom flow type on top
  of the built-in wizards. The defaults are reachable through
  `FormFlow.Config.config_module/1` exactly for this, so an override doesn't
  have to restate the core options.
  """

  use FormFlow.Config

  @impl true
  def enabled_flow_types(context, config_data) do
    defaults = FormFlow.Config.config_module(nil)

    defaults.enabled_flow_types(context, config_data) ++
      [
        %FormFlow.Config.Flows.Type{
          id: "demo_checklist",
          module: DemoWeb.FormFlowLive.Checklist,
          name: "Demo checklist",
          description: "A checklist rather than a wizard.",
          properties: []
        }
      ]
  end
end
