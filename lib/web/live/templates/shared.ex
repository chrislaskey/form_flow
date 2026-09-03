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
  alias FormFlow.Data.Instances.FlowProgress
  alias FormFlow.Data.Templates

  @prefix "property_"
  @path_separator "/"

  @doc "The type among `types` with `id`, or nil."
  def type(types, id), do: Enum.find(types, &(&1.id == id))

  @doc "The properties the type with `id` declares — none for no type."
  def properties(types, id) do
    case type(types, id) do
      nil -> []
      type -> type.properties
    end
  end

  @doc """
  The types with every `:related_form` property's options filled in: the
  forms of the root flow `root_id` that come before the node `node_id` —
  the one embedding what is being edited — in the order a user works them,
  as `{qualified label, path}`. A related form is a choice whose choices the
  flow supplies, so filling them here lets the rest of the page treat it as
  any other choice type.

  The property's description gains a note when there is something to say: no
  node in scope (a catalog form, a root flow) means no earlier forms to offer;
  and a saved value (`property_values`, the template's) that none of the
  options match — the flow was rearranged, or the value was edited by hand —
  is a choice the admin has to make again, since the field can't show it.
  """
  def fill_related_forms(types, root_id, node_id, property_values \\ %{}) do
    if Enum.any?(types, fn type -> Enum.any?(type.properties, &(&1.type == :related_form)) end) do
      options = related_forms(root_id, node_id)

      for type <- types do
        %{
          type
          | properties:
              Enum.map(type.properties, &fill_related_form(&1, options, property_values))
        }
      end
    else
      types
    end
  end

  @no_earlier_forms "No earlier forms to choose from — open this form from its flow."
  @stale_choice "The saved choice is no longer in this flow — choose again."

  defp fill_related_form(%Property{type: :related_form} = property, options, property_values) do
    notes = [
      property.description,
      if(options == [], do: @no_earlier_forms),
      if(stale?(options, property_values[property.id]), do: @stale_choice)
    ]

    %{property | options: options, description: Enum.join(Enum.reject(notes, &is_nil/1), " ")}
  end

  defp fill_related_form(property, _options, _property_values), do: property

  defp stale?(_options, blank) when blank in [nil, ""], do: false
  defp stale?(options, value), do: not List.keymember?(options, value, 1)

  defp related_forms(nil, _node_id), do: []
  defp related_forms(_root_id, nil), do: []

  defp related_forms(root_id, node_id) do
    root_id
    |> Templates.Flows.resolve_tree()
    |> FlowProgress.forms([])
    |> earlier_forms(node_id)
  end

  @doc """
  The forms before the node `node_id`, as `{qualified label, path}` options.
  `forms` is a flow tree's forms in the order a user works them
  (`FormFlow.Data.Instances.FlowProgress.forms/2`); the cut is the first
  form at or inside that node, so a form node's own form and everything after
  it are excluded, as is everything inside a subflow node.
  """
  def earlier_forms(forms, node_id) do
    forms
    |> Enum.take_while(&(node_id not in &1.path))
    |> Enum.map(&{FlowProgress.qualified_label(&1), Enum.join(&1.path, @path_separator)})
  end

  def field_name(%Property{id: id}), do: @prefix <> id

  @doc """
  The `DynamicForm` question type a property renders as. Every property type
  is a `DynamicForm` type of the same name, except `:number`, which is a
  `text` question with a number `input_type/1`, and `:related_form`, a
  `dropdown` of the flow's earlier forms.
  """
  def field_type(%Property{type: :number}), do: "text"
  def field_type(%Property{type: :related_form, options: []}), do: "text"
  def field_type(%Property{type: :related_form}), do: "dropdown"

  def field_type(%Property{type: type}), do: Atom.to_string(type)

  @doc """
  Whether a property's field renders read-only: a related form with no
  earlier forms to offer, which shows its note instead of an empty select.
  """
  def read_only?(%Property{type: :related_form, options: []}), do: true
  def read_only?(%Property{}), do: false

  @doc "The HTML input type a property's field passes through, or nil."
  def input_type(%Property{type: :number}), do: "number"
  def input_type(%Property{}), do: nil

  @doc "A property's choices for its field — nil for a type without any."
  def field_options(%Property{type: :related_form, options: []}), do: nil

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

  # A related form's value is a path; one the flow no longer has is the one
  # error there is, however it came about
  def display_value(%Property{type: :related_form, options: options}, value) do
    case List.keyfind(options || [], value, 1) do
      {label, _path} -> label
      nil -> "Missing — no longer in this flow"
    end
  end

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

  @doc """
  The message a failed template save shows. A slug the changeset refused —
  taken, or malformed — is named, since it is the one field an admin can
  fix by typing; anything else is the generic retry.
  """
  def save_error(%Ecto.Changeset{errors: errors}, fallback) do
    case Keyword.get(errors, :slug) do
      {message, _opts} -> "The slug #{message}."
      nil -> fallback
    end
  end
end
