defmodule FormFlow.Config.Flows.Type do
  @moduledoc """
  Flow type definition: one way a "forms" flow presents its forms to the
  user filling them out.

  `FormFlow.Config.enabled_flow_types/2` returns a list of these; the struct
  is what the config describes, and its `:module` — `use`ing this behaviour —
  is what the type does. `:id` is the value stored in the flow's
  `properties["form_flow_type"]`.

  Every callback takes the `FormFlow.Context` of one form in one flow
  instance — `:form_progress` is the form, `:flow_progress` its flow's forms
  in order — plus `config_data`. The defaults, `FormFlow.Config.Flows.Type.Default`,
  are the in-order wizard: a form can be edited where the flow allows it, and
  finishing a form moves to the nearest place work can happen next. A type
  overrides only what it changes, and can call the defaults from an override.

  Two callbacks answer two different questions about the viewer. `visible?/2`
  is whether the flow's forms are *for* this viewer at all — the default
  reads the flow's perspectives (`FormFlow.Config.Flows.Perspective`), so a
  reviewer never sees the applicant's forms, and the pages hide, skip, and
  refuse a position that is not. `editable?/2` is whether the flow allows
  work at this position *now* — the order rule. The pages ask `visible?/2`
  first, so a type's `editable?/2` never has to repeat the perspective test.
  """

  alias FormFlow.Context
  alias FormFlow.Data.Instances.FormProgress
  alias FormFlow.Data.Templates.Flow

  defstruct [:id, :module, :name, :description, properties: []]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          module: module(),
          name: String.t(),
          description: String.t() | nil,
          properties: [FormFlow.Config.Property.t()]
        }

  @doc """
  What an admin entered for the flow's type's `:properties`, keyed by
  property key — stored on the flow under
  `properties["form_flow_type_property_values"]`. Empty when the type
  declares none or nothing was entered.
  """
  @spec property_values(Flow.t() | nil) :: map()
  def property_values(%Flow{properties: properties}) do
    Map.get(properties || %{}, "form_flow_type_property_values", %{})
  end

  def property_values(nil), do: %{}

  @doc """
  Whether the forms of the flow at `:subflow` are for this viewer — shown on
  the flow instance's page, counted toward where they go next, and openable
  at all. The default is `FormFlow.Config.Flows.Perspective.visible?/1`: the
  flow's stored perspectives against the viewer's `:perspectives`, with a
  flow naming none for everyone and a viewer with none seeing everything.
  Asked with `:form_progress` set, like `editable?/2`, so a type can answer
  per form; the pages then treat a form that is not visible as not editable.
  """
  @callback visible?(Context.t(), map()) :: boolean()

  @doc """
  Whether the user may edit the form at `:form_progress` — start it when it
  has no instance yet, or keep working on one already started. The order
  rule only: the pages ask `visible?/2` first.
  """
  @callback editable?(Context.t(), map()) :: boolean()

  @doc """
  Where the user goes after completing the form at `:form_progress`: the
  next form of this flow, or `nil` when the flow has nothing left for them —
  the flow instance then carries them on to whatever follows it. The context
  is derived fresh after the write, so the form just submitted counts as done.

  `FormFlow.Config.Forms.Type` has a `handle_complete/2` too, given the same
  context; that one is a hook for the form's type to react at and answers
  nothing.
  """
  @callback handle_complete(Context.t(), map()) :: FormProgress.t() | nil

  @doc """
  The flow's progress, drawn above the form being edited — return `nil` to
  draw nothing. `assigns` are those of
  `FormFlow.Web.Instances.Components.Flows.Progress.flow_progress/1`, plus
  `:context` and `:config_data`.
  """
  @callback progress_component(map()) :: Phoenix.LiveView.Rendered.t() | nil

  defmacro __using__(_opts) do
    quote do
      @behaviour FormFlow.Config.Flows.Type

      def visible?(context, config_data) do
        FormFlow.Config.Flows.Type.Default.visible?(context, config_data)
      end

      def editable?(context, config_data) do
        FormFlow.Config.Flows.Type.Default.editable?(context, config_data)
      end

      def handle_complete(context, config_data) do
        FormFlow.Config.Flows.Type.Default.handle_complete(context, config_data)
      end

      def progress_component(assigns) do
        FormFlow.Config.Flows.Type.Default.progress_component(assigns)
      end

      defoverridable visible?: 2, editable?: 2, handle_complete: 2, progress_component: 1
    end
  end
end
