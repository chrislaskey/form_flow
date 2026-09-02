defmodule FormFlow.Config do
  @moduledoc """
  Module for configuring FormFlow from the parent app

  ## Implementation details

  Every callback takes a `FormFlow.Context` — one common shape every callback
  shares, so adding a new callback never means learning a new payload — and
  `config_data`, passed through unmodified from wherever `use`s this (see
  `FormFlow.Web.Router`'s `:config_data` attr).

  The defaults are `FormFlow.Config.Default`. A custom module `use`s this
  behaviour and overrides only what it changes; an override that wants to
  extend a default rather than replace it calls `FormFlow.Config.Default`'s
  and adds to the result. The pages resolve the module to ask with
  `config_module/1` — the host's, or the defaults when the host set none —
  and then call its callbacks directly.
  """

  alias FormFlow.Context

  @doc "The flow types a flow may be given, in display order."
  @callback enabled_flow_types(Context.t(), map()) :: [FormFlow.Config.Flows.Type.t()]

  @doc "The form types a form may be given, in display order."
  @callback enabled_form_types(Context.t(), map()) :: [FormFlow.Config.Forms.Type.t()]

  defmacro __using__(_opts) do
    quote do
      @behaviour FormFlow.Config

      def enabled_flow_types(context, config_data) do
        FormFlow.Config.Default.enabled_flow_types(context, config_data)
      end

      def enabled_form_types(context, config_data) do
        FormFlow.Config.Default.enabled_form_types(context, config_data)
      end

      defoverridable enabled_flow_types: 2, enabled_form_types: 2
    end
  end

  @doc "Return the FormFlow.Config module, either the one passed in or the default"
  @spec config_module(module() | nil) :: module()
  def config_module(nil), do: FormFlow.Config.Default
  def config_module(config), do: config
end
