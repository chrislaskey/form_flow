defmodule FormFlow.Config do
  @moduledoc """
  `use FormFlow.Config` behaviour for customizing FormFlow's behavior.

  Every callback takes the value it's customizing, a `FormFlow.Config.Context`
  — one common shape every callback shares, so adding a new callback never
  means learning a new payload — and `config_data` (passed through unmodified
  from wherever `use`s this — see `FormFlow.Web.Router`'s `:config_data`
  attr).
  """

  alias FormFlow.Config.Context

  @callback form_flow_type_options(Context.t(), map()) :: [{String.t(), String.t()}]
  @callback form_flow_type_module(String.t() | nil, Context.t(), map()) :: module()

  defmacro __using__(_opts) do
    quote do
      @behaviour FormFlow.Config

      # Callbacks

      def form_flow_type_options(context, config_data) do
        unquote(__MODULE__).form_flow_type_options(context, config_data)
      end

      def form_flow_type_module(value, context, config_data) do
        unquote(__MODULE__).form_flow_type_module(value, context, config_data)
      end

      defoverridable form_flow_type_options: 2,
                     form_flow_type_module: 3
    end
  end

  # Public functions
  #
  # Defined outside the macro so these can be called from custom config
  # modules. Sometimes it's useful to override just part of a behaviour, so
  # this makes it possible to reuse the core logic from within custom config
  # modules too.

  def form_flow_type_options(_context, _config_data) do
    [
      {"Wizard (any order)", "wizard_any_order"},
      {"Wizard (in order)", "wizard_in_order"}
    ]
  end

  @doc """
  The `FormFlow.Flows.Types` module for a stored `form_flow_type`. An unset (`nil`)
  or unrecognized value resolves to the in-order wizard — the baseline, so a
  flow always has a type even before anyone picks one.
  """
  def form_flow_type_module(value, context, _config_data) do
    case value do
      "wizard_any_order" -> form_flow_type_wizard_any_order(context)
      "wizard_in_order" -> form_flow_type_wizard_in_order(context)
      _unset_or_unknown -> form_flow_type_wizard_in_order(context)
    end
  end

  def form_flow_type_wizard_any_order(_context), do: FormFlow.Flows.Types.WizardAnyOrder

  def form_flow_type_wizard_in_order(_context), do: FormFlow.Flows.Types.WizardInOrder
end
