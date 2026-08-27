defmodule FormFlow.Flows.Types do
  @moduledoc """
  `use FormFlow.Flows.Types` behaviour for a form flow type — how a "forms"
  flow presents its forms to the person filling them out.

  *Which* module a flow gets is a `FormFlow.Config` decision
  (`form_flow_type_module/3`, keyed off the flow's stored
  `properties["form_flow_type"]` — see `for_flow/4`); what that module *does*
  is this behaviour. Two types ship with the library:

    * `FormFlow.Flows.Types.WizardInOrder` — the flow's forms are completed
      front to back. The baseline: every callback below is its
      implementation, and an unset or unrecognized type falls back to it.
    * `FormFlow.Flows.Types.WizardAnyOrder` — every form is reachable at any
      time.

  Every callback takes the forms of *one* flow — one "forms" flow's
  `FormFlow.Data.Instances.FormProgress` structs in order, which is what
  `FormFlow.Data.Instances.FlowProgress.forms_in_flow/2` returns — so a type
  never has to reason about the rest of the flow instance. A type that declines
  (`next_form/2` returning `nil`) hands the filler back to the flow, which
  carries them on to whatever comes after this one.

  The callbacks are deliberately independent: `next_form/2` does not consult
  `openable?/2`, so a custom type overriding one usually wants to override
  the other too.
  """

  alias FormFlow.Config
  alias FormFlow.Data.Instances.FormProgress
  alias FormFlow.Data.Templates.Flow

  @doc """
  Whether the flow's progress is worth drawing — false for a flow with a
  single form, which is no sequence.
  """
  @callback show_progress?([FormProgress.t()]) :: boolean()

  @doc "Whether the filler may navigate to a form and work on it."
  @callback openable?(FormProgress.t(), [FormProgress.t()]) :: boolean()

  @doc """
  Where the filler goes after completing the form at `current_path`, or
  `nil` when this flow has nothing left for them.
  """
  @callback next_form([FormProgress.t()], current_path :: [binary()]) :: FormProgress.t() | nil

  defmacro __using__(_opts) do
    quote do
      @behaviour FormFlow.Flows.Types

      # Callbacks

      def show_progress?(forms) do
        unquote(__MODULE__).show_progress?(forms)
      end

      def openable?(form, forms) do
        unquote(__MODULE__).openable?(form, forms)
      end

      def next_form(forms, current_path) do
        unquote(__MODULE__).next_form(forms, current_path)
      end

      defoverridable show_progress?: 1,
                     openable?: 2,
                     next_form: 2
    end
  end

  @doc """
  The type module for one "forms" flow: its stored `form_flow_type` resolved
  through `FormFlow.Config.form_flow_type_module/3`. `config` is the host's
  config module, or `nil` for the library's own defaults.
  """
  @spec for_flow(Flow.t() | nil, Config.Context.t(), module() | nil, map()) :: module()
  def for_flow(flow, context, config, config_data) do
    type = flow && flow.properties["form_flow_type"]

    (config || Config).form_flow_type_module(type, context, config_data)
  end

  # Public functions
  #
  # Defined outside the macro so these can be called from custom type
  # modules. Sometimes it's useful to override just part of a behaviour, so
  # this makes it possible to reuse the core logic from within custom type
  # modules too.
  #
  # Together they are the in-order wizard: work happens where the flow says
  # it can, and finishing a form moves to the nearest place work can happen
  # next.

  def show_progress?(forms), do: length(forms) > 1

  def openable?(form, _forms), do: actionable?(form)

  def next_form(forms, _current_path), do: Enum.find(forms, &actionable?(&1))

  # Where the flow itself allows work: a form whose predecessors are done, or
  # one already started. Anything else is gated — including, after a submit,
  # the form just completed.
  defp actionable?(form), do: form.status in [:available, :in_progress]
end
