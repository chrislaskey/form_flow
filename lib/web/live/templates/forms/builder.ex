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
  from its label), and numbers arrive as the decimals a number input casts
  to.

  Two element types hold other elements — a **group** (`panel`, whose
  members belong to the enclosing form) and a **nested form**
  (`paneldynamic`, a repeating template with a scope of its own). Either
  carries its members in the entry's `children`, a second nested form inside
  the entry, written back as `elements` or `templateElements` by type. The
  builder shows one level of that: a container holds questions and content,
  not another container.

  The builder covers a subset of what a definition can hold — the properties
  in `properties/0`, for the types in `type_options/0`. `unsupported/1` names
  everything else, so the page can refuse to open a definition in the
  builder rather than drop those properties the moment the admin switched
  back to JSON. The builder edits `elements` only; `definition/2` keeps every
  other top-level key of the definition it is given.
  """

  import DynamicForm.Helpers.Map, only: [put_unless_nil: 3]

  # Inputs carry a prefix so the two containers stand apart in the dropdown
  @type_options [
    {"Input - Text", "text"},
    {"Input - Comment (multi-line text)", "comment"},
    {"Input - Dropdown", "dropdown"},
    {"Input - Radio group", "radiogroup"},
    {"Input - Checkboxes", "checkbox"},
    {"Input - Boolean (yes/no)", "boolean"},
    {"Input - Rating", "rating"},
    {"Input - Tag box (multi-select)", "tagbox"},
    {"HTML content", "html"},
    {"Group of elements", "panel"},
    {"Nested form (repeating entries)", "paneldynamic"}
  ]

  @types Enum.map(@type_options, &elem(&1, 1))

  @container_types ~w(panel paneldynamic)

  @input_types ~w(text email number tel url date time datetime-local password)

  @choice_types ~w(dropdown radiogroup checkbox tagbox)

  @questions @types -- ["html" | @container_types]

  # Which element types each editable property applies to. This one table
  # drives what the page shows for a type (`visible_if/1`), what an entry
  # writes back (`element/1` ignores anything else — a hidden field keeps
  # the value it had, and that value must not leak into the JSON), and what
  # `unsupported/1` accepts. `children` is the builder's own name for a
  # container's members; the JSON key depends on the type.
  @properties %{
    "title" => @types -- ["html"],
    "groupType" => ["panel"],
    "inputType" => ["text"],
    "choices" => @choice_types,
    "rateMin" => ["rating"],
    "rateMax" => ["rating"],
    "rateStep" => ["rating"],
    "templateTitle" => ["paneldynamic"],
    "minPanelCount" => ["paneldynamic"],
    "maxPanelCount" => ["paneldynamic"],
    "addPanelText" => ["paneldynamic"],
    "html" => ["html"],
    "placeholder" => ~w(text comment dropdown tagbox),
    "description" => @questions ++ ["paneldynamic"],
    "defaultValue" => ~w(text comment dropdown radiogroup),
    "isRequired" => @questions ++ ["paneldynamic"],
    "visibleIf" => @types,
    "children" => @container_types
  }

  @numbers ~w(rateMin rateMax rateStep minPanelCount maxPanelCount)
  @booleans ~w(isRequired)
  @strings ~w(title groupType inputType templateTitle addPanelText html placeholder description defaultValue visibleIf)

  # The JSON key a container keeps its members under
  @children_key %{"panel" => "elements", "paneldynamic" => "templateElements"}

  @doc """
  The element types the builder offers, as dropdown options — every type at
  the form level, and everything but the containers inside one, since the
  builder shows one level of nesting.
  """
  def type_options(scope \\ "elements")
  def type_options("elements"), do: @type_options
  def type_options(_inside), do: Enum.reject(@type_options, &(elem(&1, 1) in @container_types))

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
  in the shape the nested form's `data` expects, a container's members under
  `children`.
  """
  def entries(%{"elements" => elements}) when is_list(elements), do: Enum.map(elements, &entry/1)
  def entries(_definition), do: []

  defp entry(element) when is_map(element) do
    %{"type" => element["type"], "name" => element["name"]}
    |> put_unless_nil("choices", choices_text(element["choices"]))
    |> put_properties(element, @strings ++ @numbers ++ @booleans)
    |> put_children(element)
  end

  defp put_properties(entry, element, properties) do
    Enum.reduce(properties, entry, fn property, acc ->
      put_unless_nil(acc, property, element[property])
    end)
  end

  defp put_children(entry, element) do
    case Map.get(@children_key, element["type"]) do
      nil -> entry
      key -> Map.put(entry, "children", Enum.map(List.wrap(element[key]), &entry/1))
    end
  end

  @doc """
  The definition with the builder's entries written as its `elements`. Every
  other top-level key of `definition` is kept as it was.

  Entries arrive either as the atom-keyed, cast maps of a `DynamicForm`
  payload or as the string-keyed maps `entries/1` produced. An entry writes
  only the properties that apply to its type and only those with a value —
  `isRequired: false` is the default and is left out, as the JSON would be
  written by hand. A container always writes its members, even none.
  """
  def definition(definition, entries) when is_map(definition) and is_list(entries) do
    Map.put(definition, "elements", Enum.map(entries, &element/1))
  end

  defp element(entry) do
    entry = stringify(entry)
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
    |> Enum.reduce(base, fn
      "children", acc ->
        Map.put(acc, @children_key[type], Enum.map(List.wrap(entry["children"]), &element/1))

      property, acc ->
        put_unless_nil(acc, property, property_value(property, entry[property]))
    end)
  end

  defp property_value(_property, blank) when blank in [nil, ""], do: nil
  defp property_value("choices", text), do: choices_from_text(text)
  defp property_value(property, value) when property in @numbers, do: number(value)
  defp property_value(property, value) when property in @booleans, do: if(value, do: true)
  defp property_value(_property, value), do: value

  @doc """
  Applies the one move an entry asked for through its `move` field — `"up"`
  or `"down"` — swapping it with its neighbour, and clears the request from
  every entry, at any level. `{:moved, entries}` when one asked; `:none`
  otherwise.

  The request rides in the form's own change, so it arrives with every other
  value as the admin left it; the page then hands the reordered entries back
  as the form's data. An entry at the edge asked to go further stays put.
  """
  def move(entries) when is_list(entries) do
    case Enum.find_index(entries, &(move_of(&1) in ["up", "down"])) do
      nil ->
        move_within(entries)

      index ->
        direction = move_of(Enum.at(entries, index))
        target = if direction == "up", do: index - 1, else: index + 1

        entries
        |> Enum.map(&clear_move/1)
        |> swap(index, target)
        |> then(&{:moved, &1})
    end
  end

  # No entry at this level asked; the first container whose members did
  defp move_within(entries) do
    Enum.reduce_while(Enum.with_index(entries), :none, fn {entry, index}, :none ->
      case move(children_of(entry)) do
        {:moved, children} ->
          moved =
            entries
            |> Enum.map(&clear_move/1)
            |> List.replace_at(index, put_children_of(entry, children))

          {:halt, {:moved, moved}}

        :none ->
          {:cont, :none}
      end
    end)
  end

  defp move_of(entry), do: entry[:move] || entry["move"]
  defp clear_move(entry), do: Map.drop(entry, [:move, "move"])
  defp children_of(entry), do: List.wrap(entry[:children] || entry["children"])

  defp put_children_of(entry, children) do
    key = if Map.has_key?(entry, "children"), do: "children", else: :children
    Map.put(entry, key, children)
  end

  defp swap(entries, _index, target) when target < 0 or target >= length(entries), do: entries

  defp swap(entries, index, target) do
    moving = Enum.at(entries, index)
    neighbour = Enum.at(entries, target)

    entries
    |> List.replace_at(index, neighbour)
    |> List.replace_at(target, moving)
  end

  @doc """
  The entries that are elements already: those with both a type and a name,
  at every level.

  A row the admin has added but not finished is not an element yet. Save
  refuses it anyway (both fields are required), and the preview renders the
  form without it rather than failing on a question with no name.
  """
  def complete_entries(entries) when is_list(entries) do
    entries
    |> Enum.filter(fn entry ->
      entry = stringify(entry)
      entry["type"] not in [nil, ""] and entry["name"] not in [nil, ""]
    end)
    |> Enum.map(fn entry ->
      case children_of(entry) do
        [] -> entry
        children -> put_children_of(entry, complete_entries(children))
      end
    end)
  end

  @doc """
  The names used by more than one element within one scope. A group's
  members belong to the form they sit in, while a nested form's template is
  a scope of its own and is checked separately. The nested forms' own `key`
  already catches a repeat among siblings; this catches a group member
  repeating a name outside its group.
  """
  def duplicate_names(entries) when is_list(entries) do
    entries
    |> Enum.map(&stringify/1)
    |> scopes()
    |> Enum.flat_map(fn scope ->
      scope
      |> Enum.map(& &1["name"])
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.frequencies()
      |> Enum.filter(fn {_name, count} -> count > 1 end)
      |> Enum.map(fn {name, _count} -> name end)
    end)
    |> Enum.uniq()
  end

  # The scopes a list of entries makes: its own (the entries themselves and
  # every group's members) first, then one per nested form
  defp scopes(entries) when is_list(entries) do
    {own, nested} =
      Enum.reduce(entries, {[], []}, fn entry, {own, nested} ->
        children = Enum.map(children_of(entry), &stringify/1)

        case entry["type"] do
          "panel" ->
            [members | more] = scopes(children)
            {own ++ [entry | members], nested ++ more}

          "paneldynamic" ->
            {own ++ [entry], nested ++ scopes(children)}

          _other ->
            {own ++ [entry], nested}
        end
      end)

    [own | nested]
  end

  @doc """
  Why the builder cannot show a definition — one sentence per problem, or
  `[]` when it can. A blank definition can always be shown.

  Checks each element's type against `type_options/0`, its properties
  against `properties/0` for that type, each value's shape against what the
  entry's control can hold — a string, a number, a boolean, a list of
  choices that are strings or `value`/`text` objects — and that no container
  sits inside another, since the builder shows one level.
  """
  def unsupported(definition) when definition == %{}, do: []

  def unsupported(%{"elements" => elements}) when is_list(elements) do
    unsupported_elements(elements, "elements")
  end

  def unsupported(%{"elements" => _other}), do: ["\"elements\" is not a list."]
  def unsupported(%{}), do: []

  defp unsupported_elements(elements, scope) do
    elements
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {element, position} -> unsupported_element(element, position, scope) end)
  end

  defp unsupported_element(element, position, scope) when is_map(element) do
    type = element["type"]
    label = element_label(element, position)

    cond do
      type not in @types ->
        ["#{label} has type #{inspect(type)}, which the form builder does not offer."]

      type in @container_types and scope != "elements" ->
        ["#{label} sits inside another group or nested form; the form builder shows one level."]

      not is_binary(element["name"]) or element["name"] == "" ->
        ["#{label} has no name."]

      true ->
        unsupported_properties(element, type, label)
    end
  end

  defp unsupported_element(_element, position, _scope),
    do: ["Element #{position} is not an object."]

  defp unsupported_properties(element, type, label) do
    allowed = allowed_properties(type)

    unknown_reasons(element, allowed, label) ++
      shape_reasons(element, allowed, label) ++
      children_reasons(element, type)
  end

  defp allowed_properties(type) do
    for {property, types} <- @properties, type in types do
      if property == "children", do: @children_key[type], else: property
    end
  end

  defp unknown_reasons(element, allowed, label) do
    unknown =
      element
      |> Map.keys()
      |> Kernel.--(["type", "name" | allowed])
      |> Enum.sort()

    if unknown == [],
      do: [],
      else: ["#{label} uses #{Enum.map_join(unknown, ", ", &inspect/1)}."]
  end

  defp shape_reasons(element, allowed, label) do
    for property <- allowed,
        Map.has_key?(element, property),
        not valid_shape?(property, element[property]) do
      "#{label} has a #{inspect(property)} the form builder cannot edit."
    end
  end

  defp children_reasons(element, type) do
    case Map.get(@children_key, type) do
      nil -> []
      key -> unsupported_elements(List.wrap(element[key]), element["name"])
    end
  end

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

  defp valid_shape?(key, members) when key in ["elements", "templateElements"],
    do: is_list(members)

  defp valid_shape?(property, value) when property in @numbers, do: is_number(value)
  defp valid_shape?(property, value) when property in @booleans, do: is_boolean(value)
  defp valid_shape?(property, value) when property in @strings, do: is_binary(value)

  defp scalar?(value), do: is_binary(value) or is_number(value)

  defp stringify(entry), do: Map.new(entry, fn {key, value} -> {to_string(key), value} end)

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
