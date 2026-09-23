defmodule FormFlow.Config.Property do
  @moduledoc """
  One setting a flow or form type asks an admin for - its definition: what
  it's called, how its field renders, what it accepts.

  A `FormFlow.Config.Flows.Type` or `FormFlow.Config.Forms.Type` declares its
  properties as a list of these. The edit pages render one field per property
  under the type dropdown - the type picked decides which fields appear - and
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
      the two form pointers, `:related_form` and `:related_form_in_any_flow`
    * `:options` - the choices, as `[{label, value}]`, for the choice types
      `:dropdown`, `:radiogroup`, and `:checkbox`. Both form pointers' are
      filled in by the library, so leave them out
    * `:required` - whether saving without a value is refused
    * `:default_value` - the value a fresh field starts with, or `nil`
    * `:clear_on_copy` - whether copying the flow drops the value rather
      than carrying it into the copy; see "Clearing on copy"

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
  | `:related_form_in_any_flow` | a select of the forms of every root flow of the tenant | `flow_position/2`'s string |

  ## Related forms

  A `:related_form` points at another form of the same flow, for a type whose
  behavior involves it - a review form showing an earlier form's answers, a
  form copying values from one. Its options are the forms that come *before*
  the one being edited, in the order a user works them, labeled the way the
  user-facing pages label them ("Documents / Proof of address"); a form has
  no earlier forms until it sits in a flow, so a catalog form's field offers
  none. The stored value is the chosen form's path - its node ids from the
  root flow down, joined with `/` - which is what identifies one form
  position even when a reusable form or subflow appears twice in a flow.

  ## Related forms in any flow

  A `:related_form_in_any_flow` points at a form of *another* flow - last
  year's licence, for a form prefilling this year's from it
  (`"prefill_with_answers_from"` on the library's form types). Its options
  are every form position of every root flow of the tenant, labeled with the
  flow's name in front ("Dog License 2026 / Documents / Proof of address").

  The value names both the flow and the position, because a path alone means
  nothing outside the flow it was read in. `flow_position/2` writes it and
  `parse_flow_position/1` reads it back:

      iex> FormFlow.Config.Property.flow_position("f1", ["n1", "n2"])
      "flow:f1/n1/n2"

      iex> FormFlow.Config.Property.parse_flow_position("flow:f1/n1/n2")
      {"f1", ["n1", "n2"]}

  The `flow:` prefix is not decoration. `FormFlow.Data.Templates.Flows.copy/2`
  re-points any property value that looks like a path - every segment a UUID
  - at the copied nodes, and this value points outside what is being copied,
  so the prefix is what keeps it out of that pass.

  A pointer into another flow is absolute, so unlike a `:related_form` it
  means the same thing wherever it is read: a catalog form reused by two
  flows can hold one.

  ## Clearing on copy

  A property marked `clear_on_copy: true` arrives in a copied flow with no
  value, and the admin sets it again. Copying is the whole rule -
  `FormFlow.Data.Templates.Flows.copy/2` drops the marked values and asks
  nothing about what they mean.

  It is for a value that points *out* of the flow holding it. A
  `:related_form` needs no flag: it points inside its own flow, so the copy
  re-points it at the copied nodes and it stays right. A
  `:related_form_in_any_flow` names a flow the copy did not touch, so the
  copy would carry it forward unchanged and it would go on resolving -
  perfectly, and at the wrong year. There is nothing to re-point it *to*,
  and clearing guesses nothing where carrying it forward guesses that last
  year's source was wanted again.

  `clear_on_copy` rather than `cleared_on_copy`, though `required:` beside it
  is an adjective: this one names an action the copy takes, not a state the
  field is in, and "clear on copy" is the sentence an admin would say.
  """

  @types [
    :text,
    :comment,
    :number,
    :dropdown,
    :radiogroup,
    :checkbox,
    :boolean,
    :related_form,
    :related_form_in_any_flow
  ]

  @choice_types [:dropdown, :radiogroup, :checkbox, :related_form, :related_form_in_any_flow]

  @flow_prefix "flow:"

  defstruct [
    :id,
    :name,
    :description,
    :options,
    :default_value,
    type: :text,
    required: false,
    clear_on_copy: false
  ]

  @type property_type ::
          :text
          | :comment
          | :number
          | :dropdown
          | :radiogroup
          | :checkbox
          | :boolean
          | :related_form
          | :related_form_in_any_flow

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          description: String.t() | nil,
          type: property_type(),
          options: [{String.t(), String.t()}] | nil,
          required: boolean(),
          default_value: any(),
          clear_on_copy: boolean()
        }

  @doc "Every property type."
  def types, do: @types

  @doc "Whether a property's type takes `:options`."
  def choice?(%__MODULE__{type: type}), do: type in @choice_types

  @doc """
  A `:related_form_in_any_flow` value from the root flow it names and the
  path of the position inside it - see "Related forms in any flow".
  """
  @spec flow_position(Ecto.UUID.t(), [Ecto.UUID.t()]) :: String.t()
  def flow_position(flow_id, [_ | _] = path) when is_binary(flow_id) do
    @flow_prefix <> Enum.join([flow_id | path], "/")
  end

  @doc """
  The flow and the path a `:related_form_in_any_flow` value names, or `nil`
  for anything that is not one - unset, blank, or a string written by hand.
  """
  @spec parse_flow_position(any()) :: {Ecto.UUID.t(), [Ecto.UUID.t()]} | nil
  def parse_flow_position(@flow_prefix <> rest) do
    case String.split(rest, "/") do
      [flow_id | [_ | _] = path] -> {flow_id, path}
      _no_position -> nil
    end
  end

  def parse_flow_position(_value), do: nil
end
