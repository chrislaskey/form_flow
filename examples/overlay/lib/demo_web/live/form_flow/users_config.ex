defmodule DemoWeb.FormFlowLive.Users.Config do
  @moduledoc """
  The users page's `FormFlow.Config`: resolves the demo's own form flow type
  to the module implementing it.

  A custom type has two halves, one per callback, and they land on different
  pages. The admin page's config *offers* "Demo checklist"
  (`form_flow_type_options/2` — see `DemoWeb.FormFlowLive.Admin.Config`);
  this one turns a flow saved with that choice into behavior for the person
  filling it out (`form_flow_type_module/3` →
  `DemoWeb.FormFlowLive.Users.Checklist`).

  The second clause hands every other value back to `FormFlow.Config`, so the
  built-in wizards keep working — overriding a callback doesn't mean
  reimplementing it.
  """

  use FormFlow.Config

  @impl true
  def form_flow_type_module("demo_checklist", _context, _config_data) do
    DemoWeb.FormFlowLive.Users.Checklist
  end

  def form_flow_type_module(value, context, config_data) do
    FormFlow.Config.form_flow_type_module(value, context, config_data)
  end
end
