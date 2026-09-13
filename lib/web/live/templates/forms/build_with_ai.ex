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

    Every element has a "type" and a "name". The name is the key the answer is
    stored under: lowercase, words joined by underscores, unique in the form,
    and never changed for an element that already exists — a renamed element
    loses the answers already given to it.

    The element types, and what each is for:

    #{type_lines()}

    The properties each type accepts:

    #{property_lines()}

    Rules:

    * Use only the types and properties listed above.
    * A "panel" holds its members under "elements"; a "paneldynamic" holds its
      template under "templateElements". Nothing nests inside those members.
    * "choices" is a list of strings, or of {"value": …, "text": …} objects
      with those two keys and nothing else.
    * "rateMin", "rateMax", "rateStep", "minPanelCount" and "maxPanelCount" are
      numbers, not strings; "isRequired" is true or false.
    * Keep every top-level key of the definition you were given that you were
      not asked to change, including "title" and "description".
    * When asked to change an existing form, return the whole definition with
      the change applied, not just the new elements.
    * Give every question a "title" — the question as the user reads it.
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

      {:ok, %{}} ->
        {:error, "Build with AI returned an answer with no form elements."}

      {:ok, _other} ->
        {:error, "Build with AI returned something that is not a form definition."}

      {:error, _reason} ->
        {:error, "Build with AI returned an answer that is not valid JSON."}
    end
  end

  defp type_lines do
    Enum.map_join(Builder.type_options(), "\n", fn {label, type} -> "  * #{type} — #{label}" end)
  end

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
