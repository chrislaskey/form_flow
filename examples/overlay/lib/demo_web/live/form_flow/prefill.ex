defmodule DemoWeb.FormFlowLive.Prefill do
  @moduledoc """
  The demo's own form type, behind the `"demo_prefill"` option
  `DemoWeb.FormFlowLive.Config` offers: a form whose `name` question starts
  filled in from the host application — here a constant standing in for a
  database lookup.

  It shows the shape every prefill takes: load the host's data, then merge
  the user's stored answers *over* it, so a returning user never sees their
  edits replaced. The stored answers come from the default type's
  `initial_data/2`, reached the same way a custom config module reaches
  `FormFlow.Config.Default`.
  """

  use FormFlow.Config.Forms.Type

  alias FormFlow.Config.Forms.Type

  @impl true
  def initial_data(context, config_data) do
    Map.merge(%{"name" => "Demo User"}, Type.Default.initial_data(context, config_data))
  end
end
