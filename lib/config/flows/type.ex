defmodule FormFlow.Config.Flows.Type do
  @moduledoc """
  Flow type definition: one way a "forms" flow presents its forms to the
  user filling them out.

  A host passes a list of these as the `flow_types` attr of
  `FormFlow.Web.router/1` and the LiveComponents — the same list on the
  admin pages, where a type is chosen, and on every instance page, where it
  acts — usually from one function of its own that starts from `defaults/0`.
  The struct is what the host describes, and its `:module` — `use`ing this
  behaviour — is what the type does. `:id` is the value stored in the flow's
  `properties["form_flow_type"]`.

  Two lists on the struct are what an admin sets per flow of the type.
  `:properties` are the type's settings (`FormFlow.Config.Property`), one
  field each on the identity form. `:perspectives` are the kinds of user a
  flow of this type can be for (`FormFlow.Config.Flows.Perspective`) — a
  review type declares its reviewers and approvers, a plain wizard declares
  none and is for everyone. The identity form offers the picked type's as a
  multi-select, and the picked ids are stored on the flow. A host sets both
  lists when it builds the struct, the library's built-in types included:
  its `flow_types` can be `defaults/0` with `perspectives` filled in.

  Every callback takes the `FormFlow.Context` of one form in one flow
  instance — `:form_progress` is the form, `:flow_progress` its flow's forms
  in order — plus `callback_data`, the host's own map from the attr of that
  name. The defaults, `FormFlow.Config.Flows.Type.Default`,
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

  defstruct [:id, :module, :name, :description, properties: [], perspectives: []]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          module: module(),
          name: String.t(),
          description: String.t() | nil,
          properties: [FormFlow.Config.Property.t()],
          perspectives: [FormFlow.Config.Flows.Perspective.t()]
        }

  @doc """
  The library's flow types, in display order: the in-order wizard first —
  the fallback for a flow that never chose — then the any-order wizard. What
  the `flow_types` attr defaults to, and what a host's own list starts from:

      def flow_types do
        FormFlow.Config.Flows.Type.defaults() ++ [checklist()]
      end

  Flow types apply to "forms" flows; the pages offer none for a "subflows"
  flow, whatever the list.
  """
  @spec defaults() :: [t()]
  def defaults do
    [
      %__MODULE__{
        id: "wizard_in_order",
        module: FormFlow.Web.Components.Flows.Types.WizardInOrder,
        name: "Wizard (in order)",
        description: "Form wizard. Users must complete in order."
      },
      %__MODULE__{
        id: "wizard_any_order",
        module: FormFlow.Web.Components.Flows.Types.WizardAnyOrder,
        name: "Wizard (any order)",
        description: "Form wizard. Users can jump ahead and complete in any order."
      }
    ]
  end

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
  `:context` and `:callback_data`.
  """
  @callback progress_component(map()) :: Phoenix.LiveView.Rendered.t() | nil

  defmacro __using__(_opts) do
    quote do
      @behaviour FormFlow.Config.Flows.Type

      def visible?(context, callback_data) do
        FormFlow.Config.Flows.Type.Default.visible?(context, callback_data)
      end

      def editable?(context, callback_data) do
        FormFlow.Config.Flows.Type.Default.editable?(context, callback_data)
      end

      def handle_complete(context, callback_data) do
        FormFlow.Config.Flows.Type.Default.handle_complete(context, callback_data)
      end

      def progress_component(assigns) do
        FormFlow.Config.Flows.Type.Default.progress_component(assigns)
      end

      defoverridable visible?: 2, editable?: 2, handle_complete: 2, progress_component: 1
    end
  end
end
