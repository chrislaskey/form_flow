defmodule DemoWeb.FormFlowLive.Admin.Config do
  @moduledoc """
  The admin page's `FormFlow.Config`: demonstrates extending a callback while
  keeping the library's defaults — the demo offers one custom form flow type
  on top of the built-in wizards. The public function on `FormFlow.Config`
  is reusable exactly for this, so an override doesn't have to restate the
  core options.

  Offering the choice is half of a custom type; the users page's config is
  where `"demo_checklist"` becomes behavior — see
  `DemoWeb.FormFlowLive.Users.Config`.
  """

  use FormFlow.Config

  @impl true
  def form_flow_type_options(context, config_data) do
    FormFlow.Config.form_flow_type_options(context, config_data) ++
      [{"Demo checklist", "demo_checklist"}]
  end
end
