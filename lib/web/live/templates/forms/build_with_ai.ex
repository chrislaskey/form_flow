defmodule FormFlow.Web.Templates.Forms.BuildWithAI do
  @moduledoc """
  What `FormFlow.Web.Templates.Forms.Edit` asks a model for when an admin
  presses Build, and what it makes of the answer: the instruction, the
  request built around one admin's words, and the definition read back out
  of the text that came back.

  The page owns the panel, the button, and where the answer lands; this
  module owns everything about the conversation. The split is what makes the
  parts most likely to change — the instruction's wording, the shapes a
  model's answer arrives in — testable without a LiveView.

  The instruction is **generated from the form builder's own tables**
  (`FormFlow.Web.Templates.Forms.Builder.type_options/0` and
  `allowed_properties/1`), not written out beside them, so an answer that
  follows the instruction is an answer `Builder.unsupported/1` accepts. A
  model told about a type the builder dropped, or a property it never had,
  would write definitions that open as JSON with a warning — which is the
  failure this generation exists to prevent.

  Nothing here talks to a provider. `FormFlow.Config.AI` is the module that
  does, and this one hands it a `FormFlow.Config.AI.Request`.
  """

  alias FormFlow.Config.AI.Request
  alias FormFlow.Web.Templates.Forms.Builder

  # A model told not to use a code fence uses one often enough that the
  # answer is read out of the first one when it is there
  @fence ~r/```[a-zA-Z]*\s*(.*?)\s*```/s

  # The two element types that store nothing under their name
  @answerless ["panel", "html"]

  @doc """
  The request for one press of Build: what the model is told a definition is,
  the definition as it stands, and what the admin asked for.

  The definition arrives as the JSON text the page already holds rather than
  as a map, because that text is what the admin is looking at — including an
  edit they have typed and not saved.
  """
  @spec request(String.t(), String.t(), String.t() | nil) :: Request.t()
  def request(prompt, definition_json, model) do
    %Request{
      model: model,
      system: instructions(),
      prompt: """
      The form's definition as it stands:

      #{definition_json}

      What to do:

      #{prompt}
      """
    }
  end

  @doc """
  What a model is told a definition is, generated from the tables that decide
  what the form builder can show — so an answer that follows the instruction
  is an answer the builder can open
  (`FormFlow.Web.Templates.Forms.Builder.unsupported/1`).
  """
  @spec instructions() :: String.t()
  def instructions do
    """
    You write SurveyJS-compatible form definitions for a form builder.

    Answer with one JSON object and nothing else: no prose, no markdown code
    fence, no explanation. The object has an "elements" key holding a list of
    elements, in the order the user fills them in.

    Every element has a "type" and a "name", and every question also has a
    "title". The "title" is the question as the user reads it — the words on
    screen, and the only name anybody but you sees. The "name" is the key the
    answer is stored under: lowercase, words joined by underscores, unique in
    the form, and never shown to anyone.

    The element types, and what each is for:

    #{type_lines()}

    The properties each type accepts:

    #{property_lines()}

    Two of those properties take one of a fixed set of values, and nothing
    else:

    #{value_lines()}

    Rules:

    * Use only the types and properties listed above.
    * A "panel" holds its members under "elements"; a "paneldynamic" holds its
      template under "templateElements". Those members are questions and HTML
      content: a "panel" or a "paneldynamic" never goes inside another one.
    * "choices" is a list of strings, or of {"value": …, "text": …} objects
      with those two keys and nothing else.
    * "rateMin", "rateMax", "rateStep", "minPanelCount" and "maxPanelCount" are
      numbers, not strings; "isRequired" is true or false.
    * Keep every top-level key of the definition you were given that you were
      not asked to change, including "title" and "description".
    * When asked to change an existing form, return the whole definition with
      the change applied, not just the new elements.
    * Give every question a "title".
    * When asked to rename a question, or to change what it is called or what
      it says, change its "title". Keep the "name" it already has: it is not
      on screen, and changing it throws away every answer already given to
      that question. Change a "name" only when the request is explicitly
      about the stored key or the field name.
    """
  end

  @doc """
  The definition in a model's answer: a JSON object with a list of elements.

  The answer is text, and a model told not to use a code fence sometimes uses
  one anyway, so the fence comes off first. Everything else is an error
  sentence for the admin — the prompt is still on screen to change and press
  again.

  An object with no elements is refused here rather than left to
  `FormFlow.Web.Templates.Forms.Builder.unsupported/1`, which answers `[]`
  for it: the builder is asked whether it can show a definition, and there is
  nothing in an empty map it cannot show. The question here is whether this
  is a form at all, so a model answering `{}` or
  `{"error": "I can't do that"}` stops here instead of replacing the draft
  with it.
  """
  @spec definition(String.t()) :: {:ok, map()} | {:error, String.t()}
  def definition(text) do
    case Phoenix.json_library().decode(strip_fence(text)) do
      {:ok, %{"elements" => elements} = definition} when is_list(elements) ->
        {:ok, definition}

      {:ok, answer} when is_map(answer) ->
        {:error, "Build with AI returned an answer with no form elements."}

      {:ok, _other} ->
        {:error, "Build with AI returned something that is not a form definition."}

      {:error, _reason} ->
        {:error, "Build with AI returned an answer that is not valid JSON."}
    end
  end

  @doc """
  What an answer did to the form's questions: the names it `:added`, the ones
  it `:removed` — renamed counts as removed, since a name is all a stored
  answer has to find its question by — and the ones it `:changed` but kept, each
  in the order they are asked.

  Everything is empty when there is nothing to compare against: a definition
  that would not parse, and a form built from a blank draft, where every
  question is new and the admin is looking at the only evidence they need.

  An answer can lose a question without looking wrong at all. A model asked to
  put three fields on one line has merged them into one before now and reported
  success; nothing in a definition says which questions used to exist.

  Groups and HTML blocks are not counted. Neither holds an answer under its
  name, so neither losing one loses anything, and a model rearranging groups is
  the commonest shape of a *correct* answer. A nested form does count: its own
  name holds the list of entries.

  Two limits worth knowing, both of which under-report rather than cry wolf —
  the right way round for a warning nobody asked for. Names are compared across
  the whole definition rather than per scope, so a form using one name in two
  scopes can hide a change. And a question is `:changed` by its own properties
  only: moving one into a different group is not a change to the question.
  """
  @type changes :: %{added: [String.t()], removed: [String.t()], changed: [String.t()]}

  @spec changes(String.t(), map()) :: changes()
  def changes(previous_json, %{} = definition) do
    case Phoenix.json_library().decode(to_string(previous_json)) do
      {:ok, %{} = previous} -> compare(questions(previous), questions(definition))
      _other -> %{added: [], removed: [], changed: []}
    end
  end

  defp compare([], _now), do: %{added: [], removed: [], changed: []}

  defp compare(before, now) do
    was = Map.new(before)
    is_now = Map.new(now)

    %{
      added: for({name, _properties} <- now, not is_map_key(was, name), do: name),
      removed: for({name, _properties} <- before, not is_map_key(is_now, name), do: name),
      changed: for({name, properties} <- now, was[name] && was[name] != properties, do: name)
    }
  end

  @doc """
  Whether a set of `changes/2` has anything in it worth saying.
  """
  @spec changes?(changes()) :: boolean()
  def changes?(%{added: added, removed: removed, changed: changed}),
    do: added != [] or removed != [] or changed != []

  # Every question in the definition, in order, as `{name, its own
  # properties}` — its members left out, so a group holding a changed question
  # is not itself reported as changed
  defp questions(container) do
    container
    |> members()
    |> Enum.flat_map(fn element -> own_question(element) ++ questions(element) end)
  end

  defp own_question(%{"type" => type, "name" => name} = element)
       when is_binary(name) and type not in @answerless,
       do: [{name, Map.drop(element, ["elements", "templateElements"])}]

  defp own_question(_element), do: []

  defp members(%{"elements" => elements}) when is_list(elements), do: elements
  defp members(%{"templateElements" => elements}) when is_list(elements), do: elements
  defp members(_element), do: []

  defp type_lines do
    Enum.map_join(Builder.type_options(), "\n", fn {label, type} -> "  * #{type} — #{label}" end)
  end

  # A property whose value is a closed set is worth spelling out: a model told
  # only that a panel takes a "groupType" invents one, and an invented group
  # type is the one value in a definition that makes the renderer raise
  # instead of draw.
  defp value_lines do
    "  * groupType: #{values_of(Builder.group_type_options())}\n" <>
      "  * inputType: #{values_of(Builder.input_type_options())}"
  end

  defp values_of(options), do: Enum.map_join(options, ", ", &elem(&1, 1))

  # `allowed_properties/1`, never `properties/0`: the second names the
  # builder's `children`, and the definition spells it `elements` or
  # `templateElements` by type
  defp property_lines do
    Enum.map_join(Builder.type_options(), "\n", fn {_label, type} ->
      "  * #{type}: #{Enum.join(Builder.allowed_properties(type), ", ")}"
    end)
  end

  defp strip_fence(text) do
    case Regex.run(@fence, text, capture: :all_but_first) do
      [fenced] -> fenced
      nil -> text
    end
  end
end
