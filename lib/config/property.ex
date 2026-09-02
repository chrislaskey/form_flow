defmodule FormFlow.Config.Property do
  @moduledoc """
  One setting a flow or form type asks an admin for — its definition: what
  it's called, how its field renders, what it accepts.

  A `FormFlow.Config.Flows.Type` or `FormFlow.Config.Forms.Type` declares its
  properties as a list of these. The edit pages render one field per property
  under the type dropdown — the type picked decides which fields appear — and
  store what the admin enters on the template, keyed by `:id`. Those entered
  values are the type's *property values*, read back through
  `FormFlow.Config.Forms.Type.property_values/1`,
  `FormFlow.Config.Flows.Type.property_values/1`, and the matching
  `FormFlow.Context` fields.

  ## Fields

    * `:id` - the stored key, a string; unique within the type
    * `:name` - the field's label
    * `:description` - help text shown below the field, or `nil`
    * `:type` - how the field renders and what it accepts, one of `@types`;
      the names are `DynamicForm`'s question types, except `:number`, which is
      its `text` question with a number input and casts to a `Decimal`, and
      `:related_form`, a dropdown of the forms earlier in the flow
    * `:options` - the choices, as `[{label, value}]`, for the choice types
      `:dropdown`, `:radiogroup`, and `:checkbox`. A `:related_form`'s are
      filled in by the library from the flow, so leave them out
    * `:required` - whether saving without a value is refused
    * `:default_value` - the value a fresh field starts with, or `nil`

  ## Types

  | Type | Renders as | Value |
  |---|---|---|
  | `:text` | a text input | string |
  | `:comment` | a textarea | string |
  | `:number` | a number input | `Decimal` |
  | `:dropdown` | a select | one option's value |
  | `:radiogroup` | radio buttons | one option's value |
  | `:checkbox` | a checkbox group | a list of option values |
  | `:boolean` | a single checkbox | `true` or `false` |
  | `:related_form` | a select of the forms earlier in the flow | the chosen form's path |

  ## Related forms

  A `:related_form` points at another form of the same flow, for a type whose
  behavior involves it — a review form showing an earlier form's answers, a
  form copying values from one. Its options are the forms that come *before*
  the one being edited, in the order a user works them, labeled the way the
  user-facing pages label them ("Documents / Proof of address"); a form has
  no earlier forms until it sits in a flow, so a catalog form's field offers
  none. The stored value is the chosen form's path — its node ids from the
  root flow down, joined with `/` — which is what identifies one form
  position even when a reusable form or subflow appears twice in a flow.
  """

  @types [:text, :comment, :number, :dropdown, :radiogroup, :checkbox, :boolean, :related_form]
  @choice_types [:dropdown, :radiogroup, :checkbox, :related_form]

  defstruct [:id, :name, :description, :options, :default_value, type: :text, required: false]

  @type property_type ::
          :text
          | :comment
          | :number
          | :dropdown
          | :radiogroup
          | :checkbox
          | :boolean
          | :related_form

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          description: String.t() | nil,
          type: property_type(),
          options: [{String.t(), String.t()}] | nil,
          required: boolean(),
          default_value: any()
        }

  @doc "Every property type."
  def types, do: @types

  @doc "Whether a property's type takes `:options`."
  def choice?(%__MODULE__{type: type}), do: type in @choice_types
end
