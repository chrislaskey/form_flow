defmodule FormFlow.Web.Templates.Shared do
  @moduledoc """
  `FormFlow.Web.Templates.Shared` is what the flow and form edit pages have in
  common: the type dropdown and, under it, one field per property the picked
  type declares (`FormFlow.Config.Property`).

  Both pages render their identity form through `DynamicForm`, and both track
  pending values so nothing persists until Save. The property fields ride
  along: they render for the *pending* type, so switching the dropdown swaps
  them in place, and their values save into the template's properties under
  the type's own key.

  Field names carry a prefix so a property can never collide with the form's
  own fields (`name`, `description`, the type itself).
  """

  alias FormFlow.Config.Property

  @prefix "property_"

  @doc "The type among `types` with `id`, or nil."
  def type(types, id), do: Enum.find(types, &(&1.id == id))

  @doc "The properties the type with `id` declares — none for no type."
  def properties(types, id) do
    case type(types, id) do
      nil -> []
      type -> type.properties
    end
  end

  @doc "The `DynamicForm` field name for a property."
  def field_name(%Property{id: id}), do: @prefix <> id

  @doc """
  The `DynamicForm` question type a property renders as. Every property type
  is a `DynamicForm` type of the same name, except `:number`, which is a
  `text` question with a number `input_type/1`.
  """
  def field_type(%Property{type: :number}), do: "text"
  def field_type(%Property{type: type}), do: Atom.to_string(type)

  @doc "The HTML input type a property's field passes through, or nil."
  def input_type(%Property{type: :number}), do: "number"
  def input_type(%Property{}), do: nil

  @doc "A property's choices for its field — nil for a type without any."
  def field_options(%Property{options: options} = property) do
    if Property.choice?(property), do: options || [], else: nil
  end

  @doc """
  The stored property values as the identity form's `data` entries — one per
  property the type declares, under the field name.
  """
  def field_data(properties, property_values) do
    for %Property{} = property <- properties, into: %{} do
      {String.to_atom(field_name(property)), property_values[property.id]}
    end
  end

  @doc """
  The property values a `DynamicForm` payload carries for these properties,
  keyed by property id, blanks dropped. Field names become atoms in a
  payload; the set is bounded by what the config declares.
  """
  def payload_property_values(payload_data, properties) do
    properties
    |> Enum.flat_map(fn %Property{} = property ->
      case payload_data[String.to_atom(field_name(property))] do
        blank when blank in [nil, "", []] -> []
        value -> [{property.id, value}]
      end
    end)
    |> Map.new()
  end

  @doc """
  A stored property value as the read-only pages show it: a choice by its
  label, a list of choices joined, a boolean as Yes or No, anything else as
  text.
  """
  def display_value(%Property{} = property, value) when is_list(value) do
    Enum.map_join(value, ", ", &display_value(property, &1))
  end

  def display_value(%Property{type: :boolean}, value),
    do: if(value in [true, "true"], do: "Yes", else: "No")

  def display_value(%Property{} = property, value) do
    if Property.choice?(property) do
      case List.keyfind(property.options || [], value, 1) do
        {label, _value} -> label
        nil -> to_string(value)
      end
    else
      to_string(value)
    end
  end
end
