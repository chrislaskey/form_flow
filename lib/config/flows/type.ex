defmodule FormFlow.Config.Flows.Type do
  @moduledoc """
  Flow type definition: one way a flow is worked. A "forms" flow's type is
  how it presents its forms to the user filling them out; a "subflows" flow's
  type is the order its subflows are worked in. The struct's `:kind` says
  which - `:forms` or `:subflows`, the flow's `label` as an atom.

  A host passes a list of these, both kinds together, as the `flow_types`
  attr of `FormFlow.Web.router/1` and the LiveComponents - the same list on
  the admin pages, where a type is chosen, and on every instance page, where
  it acts - usually from one function of its own that starts from
  `defaults/0`. Every page offers a flow the types of its kind
  (`for_kind/2`). The struct is what the host describes, and its `:module` -
  `use`ing this behaviour - is what the type does. `:id` is the value stored
  in the flow's `properties["flow_type"]`.

  Two lists on the struct are what an admin sets per flow of the type.
  `:properties` are the type's settings (`FormFlow.Config.Property`), one
  field each on the identity form. `:perspectives` are the kinds of user a
  "forms" flow of this type can be for (`FormFlow.Config.Flows.Perspective`)
  - a review type declares its reviewers and approvers, a plain wizard
  declares none and is for everyone; a `:subflows` type declares none, since
  perspective is a "forms" flow's alone. The identity form offers the picked
  type's as a multi-select, and the picked ids are stored on the flow. A host
  sets both lists when it builds the struct, the library's built-in types
  included: its `flow_types` can be `defaults/0` with `perspectives` filled
  in on the `:forms` kind.

  Every callback takes a `FormFlow.Context` plus `callback_data`, the host's
  own map from the attr of that name. A `:forms` type is asked about one
  form in one flow instance - `:form_progress` is the form, `:flow_progress`
  its flow's forms in order. A `:subflows` type is asked about one subflow
  step - `:subflow_progress` is the step, `:complex_progress` the steps of
  its flow in order, `:subflow` that flow and `:subflow_node` the step's
  node. The defaults, `FormFlow.Config.Flows.Type.Default`, are in order for
  both kinds: a form can be edited where the flow allows it, a step can be
  entered once the steps before it are done, and finishing either moves to
  the nearest place work can happen next. A type overrides only what it
  changes, and can call the defaults from an override.

  Two callbacks answer two different questions about the viewer of a form.
  `visible?/2` is whether the flow's forms are *for* this viewer at all -
  the default reads the flow's perspectives
  (`FormFlow.Config.Flows.Perspective`), so a reviewer never sees the
  applicant's forms, and the pages hide, skip, and refuse a position that is
  not. `editable?/2` is whether the flow allows work at this position *now*
  - the order rule. The pages ask `visible?/2` first, so a type's
  `editable?/2` never has to repeat the perspective test.

  The two kinds compose down the tree. A form is editable when every
  "subflows" flow above it says the step on the way down may be entered
  (`enterable?/2`) *and* its own "forms" type says the form may be edited.
  Where a user lands after a form is the "forms" type's `handle_complete/2`
  first, then each "subflows" flow's upward, innermost first, until one
  names a next step.
  """

  alias FormFlow.Context
  alias FormFlow.Data.Instances.FormProgress
  alias FormFlow.Data.Instances.SubflowProgress
  alias FormFlow.Data.Templates.Flow

  defstruct [:id, :module, :name, :description, kind: :forms, properties: [], perspectives: []]

  @typedoc "Which kind of flow the type is for - the flow's `label`, as an atom."
  @type kind :: :forms | :subflows

  @type t :: %__MODULE__{
          id: String.t() | nil,
          module: module(),
          name: String.t(),
          description: String.t() | nil,
          kind: kind(),
          properties: [FormFlow.Config.Property.t()],
          perspectives: [FormFlow.Config.Flows.Perspective.t()]
        }

  @doc """
  The library's flow types, in display order, each kind's fallback first: for
  "forms" flows the in-order wizard - what a flow that never chose amounts
  to - then the any-order wizard; for "subflows" flows **In order** then
  **Any order**. What the `flow_types` attr defaults to, and what a host's
  own list starts from:

      def flow_types do
        FormFlow.Config.Flows.Type.defaults() ++ [checklist()]
      end
  """
  @spec defaults() :: [t()]
  def defaults do
    [
      %__MODULE__{
        id: "wizard_in_order",
        kind: :forms,
        module: FormFlow.Web.Components.Flows.Types.WizardInOrder,
        name: "Wizard (in order)",
        description: "Form wizard. Users must complete in order."
      },
      %__MODULE__{
        id: "wizard_any_order",
        kind: :forms,
        module: FormFlow.Web.Components.Flows.Types.WizardAnyOrder,
        name: "Wizard (any order)",
        description: "Form wizard. Users can jump ahead and complete in any order."
      },
      %__MODULE__{
        id: "in_order",
        kind: :subflows,
        module: FormFlow.Web.Components.Flows.Types.InOrder,
        name: "In order",
        description:
          "Subflows are worked front to back. Each opens when the ones before it are done."
      },
      %__MODULE__{
        id: "any_order",
        kind: :subflows,
        module: FormFlow.Web.Components.Flows.Types.AnyOrder,
        name: "Any order",
        description:
          "Any unfinished subflow can be worked. Finishing one moves to the next unfinished."
      }
    ]
  end

  @doc """
  The types among `types` for a flow of `label` (`"forms"` or `"subflows"`),
  in the list's order - the first is what a flow of that kind that never
  chose resolves to. `[]` for any other label.
  """
  @spec for_kind([t()], String.t() | nil) :: [t()]
  def for_kind(types, label) when is_binary(label) do
    Enum.filter(types, &(Atom.to_string(&1.kind) == label))
  end

  def for_kind(_types, _label), do: []

  @doc """
  What an admin entered for the flow's type's `:properties`, keyed by
  property key - stored on the flow under
  `properties["flow_type_property_values"]`. Empty when the type
  declares none or nothing was entered.
  """
  @spec property_values(Flow.t() | nil) :: map()
  def property_values(%Flow{properties: properties}) do
    Map.get(properties || %{}, "flow_type_property_values", %{})
  end

  def property_values(nil), do: %{}

  @doc """
  Whether the forms of the flow at `:subflow` are for this viewer - shown on
  the flow instance's page, counted toward where they go next, and openable
  at all. The default is `FormFlow.Config.Flows.Perspective.visible?/1`: the
  flow's stored perspectives against the viewer's `:perspectives`, with a
  flow naming none for everyone and a flow naming some for viewers sharing
  one - a viewer with none sees only the flows for everyone.
  Asked with `:form_progress` set, like `editable?/2`, so a type can answer
  per form; the pages then treat a form that is not visible as not editable.
  A `:forms` type's question.
  """
  @callback visible?(Context.t(), map()) :: boolean()

  @doc """
  Whether the user may edit the form at `:form_progress` - start it when it
  has no instance yet, or keep working on one already started. The order
  rule only: the pages ask `visible?/2` first. A `:forms` type's question.
  """
  @callback editable?(Context.t(), map()) :: boolean()

  @doc """
  Whether the subflow step at `:subflow_progress` may be entered now - the
  order rule between the steps of the "subflows" flow at `:subflow`. The
  pages ask it for every step on the way down to a form, and a form behind a
  closed step is not editable: "This form isn't available yet". A
  `:subflows` type's question.
  """
  @callback enterable?(Context.t(), map()) :: boolean()

  @doc """
  Where the user goes next. Asked of a `:forms` type after completing the
  form at `:form_progress`: the next form of this flow, or `nil` when the
  flow has nothing left for them. Asked of a `:subflows` type when the step
  at `:subflow_progress` is done and its own flow has nothing left: the next
  step of this flow to descend into, or `nil` when it has nothing left
  either - the flow above then answers, up to the journey's page. Either
  way the context is derived fresh after the write, so what was just
  finished counts as done.

  `FormFlow.Config.Forms.Type` has a `handle_complete/2` too, given the same
  context; that one is a hook for the form's type to react at and answers
  nothing.
  """
  @callback handle_complete(Context.t(), map()) :: FormProgress.t() | SubflowProgress.t() | nil

  @doc """
  The flow's progress, drawn above the form being edited - return `nil` to
  draw nothing. `assigns` are those of
  `FormFlow.Web.Instances.Components.Flows.Progress.flow_progress/1`, plus
  `:context` and `:callback_data`. A `:forms` type's.
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

      def enterable?(context, callback_data) do
        FormFlow.Config.Flows.Type.Default.enterable?(context, callback_data)
      end

      def handle_complete(context, callback_data) do
        FormFlow.Config.Flows.Type.Default.handle_complete(context, callback_data)
      end

      def progress_component(assigns) do
        FormFlow.Config.Flows.Type.Default.progress_component(assigns)
      end

      defoverridable visible?: 2,
                     editable?: 2,
                     enterable?: 2,
                     handle_complete: 2,
                     progress_component: 1
    end
  end
end
