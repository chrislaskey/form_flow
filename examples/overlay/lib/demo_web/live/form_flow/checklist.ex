defmodule DemoWeb.FormFlowLive.Checklist do
  @moduledoc """
  The demo's own flow type, behind the `"demo_checklist"` option the admin
  page offers (see `DemoWeb.FormFlowLive.Admin.Config`).
  """

  use FormFlow.Config.Flows.Type
end
