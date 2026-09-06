defmodule FormFlow.Web.Templates.Forms.Builder do
  @moduledoc """
  `FormFlow.Web.Templates.Forms.Builder` converts between a definition's
  `elements` and the entries of the form builder on
  `FormFlow.Web.Templates.Forms.Edit`.

  The form builder is a `DynamicForm` nested form: one entry per element,
  with the entry's fields named after the SurveyJS properties they set
  (`isRequired`, `visibleIf`, `rateMin`), so each one can be looked up in
  `DynamicForm.Instance.Question` or the SurveyJS documentation directly.
  Two shapes differ from the JSON and are translated here: `choices` is
  typed one per line (`value | Label` for a choice whose stored value differs
  from its label), and the rating bounds arrive as the decimals a number
  input casts to.

  The builder covers a subset of what a definition can hold — the properties
  in `properties/0`, for the types in `type_options/0`. `unsupported/1` names
  everything else, so the page can refuse to open a definition in the
  builder rather than drop those properties the moment the admin switched
  back to JSON. The builder edits `elements` only; `definition/2` keeps every
  other top-level key of the definition it is given.
  """

  import DynamicForm.Helpers.Map, only: [put_unless_nil: 3]

  @type_options [
    {"Text", "text"},
    {"Comment (multi-line text)", "comment"},
    {"Dropdown", "dropdown"},
    {"Radio group", "radiogroup"},
    {"Checkboxes", "checkbox"},
    {"Boolean (yes/no)", "boolean"},
    {"Rating", "rating"},
    {"Tag box (multi-select)", "tagbox"},
    {"HTML content", "html"}
  ]

  @types Enum.map(@type_options, &elem(&1, 1))

  @input_types ~w(text email number tel url date time datetime-local password)

  @choice_types ~w(dropdown radiogroup checkbox tagbox)

  @not_html @types -- ["html"]

  # Which element types each editable property applies to. This one table
  # drives what the page shows for a type (`visible_if/1`), what an entry
  # writes back (`element/1` ignores anything else — a hidden field keeps
  # the value it had, and that value must not leak into the JSON), and what
  # `unsupported/1` accepts.
  @properties %{
    "title" => @not_html,
    "inputType" => ["text"],
    "choices" => @choice_types,
    "rateMin" => ["rating"],
    "rateMax" => ["rating"],
    "rateStep" => ["rating"],
    "html" => ["html"],
    "placeholder" => ~w(text comment dropdown tagbox),
    "description" => @not_html,
    "defaultValue" => ~w(text comment dropdown radiogroup),
    "isRequired" => @not_html,
    "visibleIf" => @types
  }

  @numbers ~w(rateMin rateMax rateStep)
  @booleans ~w(isRequired)
  @strings ~w(title inputType html placeholder description defaultValue visibleIf)

  @doc "The element types the builder offers, as dropdown options."
  def type_options, do: @type_options

  @doc "The `inputType` values offered for a `text` element, as dropdown options."
  def input_type_options, do: Enum.map(@input_types, &{&1, &1})

  @doc "The editable properties and the element types each applies to."
  def properties, do: @properties

  @doc """
  The `visible_if` expression showing a property's field only for the element
  types it applies to, evaluated per entry against that entry's `type`.

  A brand-new entry has no type yet and shows nothing but Type and Name until
  one is picked, which is what `notempty` is for.
  """
  def visible_if(property) do
    types = Map.fetch!(@properties, property)
    "{panel.type} notempty and {panel.type} anyof [#{Enum.map_join(types, ", ", &"'#{&1}'")}]"
  end

  @doc """
  The builder's entries for a definition: one string-keyed map per element,
  in the shape the nested form's `data` expects.
  """
  def entries(%{"elements" => elements}) when is_list(elements), do: Enum.map(elements, &entry/1)
  def entries(_definition), do: []

  defp entry(element) when is_map(element) do
    %{"type" => element["type"], "name" => element["name"]}
    |> put_unless_nil("choices", choices_text(element["choices"]))
    |> put_properties(element, @strings ++ @numbers ++ @booleans)
  end

  defp put_properties(entry, element, properties) do
    Enum.reduce(properties, entry, fn property, acc ->
      put_unless_nil(acc, property, element[property])
    end)
  end

  @doc """
  The definition with the builder's entries written as its `elements`. Every
  other top-level key of `definition` is kept as it was.

  Entries arrive either as the atom-keyed, cast maps of a `DynamicForm`
  payload or as the string-keyed maps `entries/1` produced. An entry writes
  only the properties that apply to its type and only those with a value —
  `isRequired: false` is the default and is left out, as the JSON would be
  written by hand.
  """
  def definition(definition, entries) when is_map(definition) and is_list(entries) do
    Map.put(definition, "elements", Enum.map(entries, &element/1))
  end

  @doc """
  The entries that are elements already: those with both a type and a name.

  A row the admin has added but not finished is not an element yet. Save
  refuses it anyway (both fields are required), and the preview renders the
  form without it rather than failing on a question with no name.
  """
  def complete_entries(entries) when is_list(entries) do
    Enum.filter(entries, fn entry ->
      entry = Map.new(entry, fn {key, value} -> {to_string(key), value} end)
      entry["type"] not in [nil, ""] and entry["name"] not in [nil, ""]
    end)
  end

  defp element(entry) do
    entry = Map.new(entry, fn {key, value} -> {to_string(key), value} end)
    type = entry["type"]

    # An unfinished entry writes what it has; a missing name or type is a
    # parse error the JSON editor and its preview can point at, not a null
    base =
      %{}
      |> put_unless_nil("type", property_value("type", type))
      |> put_unless_nil("name", property_value("name", entry["name"]))

    @properties
    |> Enum.filter(fn {_property, types} -> type in types end)
    |> Enum.map(fn {property, _types} -> property end)
    |> Enum.sort()
    |> Enum.reduce(base, fn property, acc ->
      put_unless_nil(acc, property, property_value(property, entry[property]))
    end)
  end

  defp property_value(_property, blank) when blank in [nil, ""], do: nil
  defp property_value("choices", text), do: choices_from_text(text)
  defp property_value(property, value) when property in @numbers, do: number(value)
  defp property_value(property, value) when property in @booleans, do: if(value, do: true)
  defp property_value(_property, value) when is_binary(value), do: value
  defp property_value(_property, value), do: value

  @doc """
  Why the builder cannot show a definition — one sentence per problem, or
  `[]` when it can. A blank definition can always be shown.

  Checks each element's type against `type_options/0`, its properties
  against `properties/0` for that type, and each value's shape against what
  the entry's control can hold: a string, a number, a boolean, or a list of
  choices that are strings or `value`/`text` objects.
  """
  def unsupported(definition) when definition == %{}, do: []

  def unsupported(%{"elements" => elements}) when is_list(elements) do
    elements
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {element, position} -> unsupported_element(element, position) end)
  end

  def unsupported(%{"elements" => _other}), do: ["\"elements\" is not a list."]
  def unsupported(%{}), do: []

  defp unsupported_element(element, position) when is_map(element) do
    type = element["type"]
    label = element_label(element, position)

    cond do
      type not in @types ->
        ["#{label} has type #{inspect(type)}, which the form builder does not offer."]

      not is_binary(element["name"]) or element["name"] == "" ->
        ["#{label} has no name."]

      true ->
        allowed = for {property, types} <- @properties, type in types, do: property

        unknown =
          element
          |> Map.keys()
          |> Kernel.--(["type", "name" | allowed])
          |> Enum.sort()

        unknown_reasons =
          if unknown == [],
            do: [],
            else: ["#{label} uses #{Enum.map_join(unknown, ", ", &inspect/1)}."]

        shape_reasons =
          for property <- allowed,
              Map.has_key?(element, property),
              not valid_shape?(property, element[property]) do
            "#{label} has a #{inspect(property)} the form builder cannot edit."
          end

        unknown_reasons ++ shape_reasons
    end
  end

  defp unsupported_element(_element, position), do: ["Element #{position} is not an object."]

  defp element_label(%{"name" => name}, _position) when is_binary(name) and name != "",
    do: "Element #{inspect(name)}"

  defp element_label(_element, position), do: "Element #{position}"

  defp valid_shape?("choices", choices) when is_list(choices) do
    Enum.all?(choices, fn
      choice when is_binary(choice) ->
        not String.contains?(choice, ["|", "\n"])

      %{"value" => value, "text" => text} = choice when map_size(choice) == 2 ->
        scalar?(value) and scalar?(text)

      _other ->
        false
    end)
  end

  defp valid_shape?("choices", _choices), do: false
  defp valid_shape?(property, value) when property in @numbers, do: is_number(value)
  defp valid_shape?(property, value) when property in @booleans, do: is_boolean(value)
  defp valid_shape?(property, value) when property in @strings, do: is_binary(value)

  defp scalar?(value), do: is_binary(value) or is_number(value)

  # Choices, one per line: a bare line is a choice whose stored value is its
  # label; `value | Label` stores the part before the bar and shows the part
  # after it.
  defp choices_text(nil), do: nil

  defp choices_text(choices) when is_list(choices) do
    Enum.map_join(choices, "\n", fn
      %{"value" => value, "text" => text} -> "#{value} | #{text}"
      choice -> to_string(choice)
    end)
  end

  defp choices_from_text(text) when is_binary(text) do
    text
    |> String.split(~r/\r?\n/)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(fn line ->
      case String.split(line, "|", parts: 2) do
        [value, label] -> %{"value" => String.trim(value), "text" => String.trim(label)}
        [choice] -> choice
      end
    end)
    |> case do
      [] -> nil
      choices -> choices
    end
  end

  defp choices_from_text(choices) when is_list(choices), do: choices

  # A number input casts to a Decimal; the JSON wants a plain number, an
  # integer when the value is whole.
  defp number(%Decimal{} = decimal) do
    if Decimal.integer?(decimal), do: Decimal.to_integer(decimal), else: Decimal.to_float(decimal)
  end

  defp number(value) when is_number(value), do: value

  defp number(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} ->
        integer

      _other ->
        case Float.parse(value) do
          {float, ""} -> float
          _other -> nil
        end
    end
  end

  defp number(_value), do: nil
end
