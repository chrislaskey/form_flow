defmodule FormFlow.Downloads.Instances.Form do
  @moduledoc """
  Turns one form instance — a user's answers at one position of a flow
  instance — into a `FormFlow.Downloads.Document`.

  This is the first of the download entry points, and the shape the ones
  after it follow: a builder that knows one resource, produces the shared
  document, and knows nothing about PDFs. It reads the same
  `FormFlow.Context` the user-facing Show page renders from
  (`FormFlow.Web.Instances.Forms.Shared.resolve/1` builds it), so a download
  and the page it was started from can never disagree about what the answers
  are.

  ## What it prints

  The pinned definition, walked in the order it asks its questions, filled
  in with what the instance holds:

    * a static panel becomes a section, its title the heading; questions
      outside any panel land in the untitled section before the first one
    * a repeating question (`paneldynamic`) becomes a section holding one
      group per entry the user added, each group the template's questions
      answered for that entry
    * a static content element becomes a line of prose, its markup stripped
      — a definition's headings and notes are part of what the form said
    * every other question becomes a field: its title, and its answer
      rendered through `render_value/2`

  A question the definition hides at these answers (`visibleIf`) is left
  out, so the printout shows the form the user actually saw rather than
  every branch of it. A question the user did not answer is kept, because a
  record says what was left blank as much as what was filled in.

  Values render for reading, not for round-tripping: a choice prints the
  text an admin wrote beside it rather than its stored value, a boolean
  prints Yes or No, a list prints comma-separated, and anything structured
  the definition has no question for falls back to compact JSON.
  """

  alias DynamicForm.Instance
  alias FormFlow.Context
  alias FormFlow.Data.Instances
  alias FormFlow.Data.Instances.FlowProgress
  alias FormFlow.Data.Instances.FormProgress
  alias FormFlow.Downloads.Document
  alias FormFlow.Downloads.Document.Section

  @doc """
  The document for the form instance the context is aimed at.

  `{:error, :not_started}` when the context has no `:form_instance` — the
  position exists but nobody has opened it, so there is nothing to print;
  the caller answers that rather than sending an empty file.
  `{:error, :no_definition}` when the pinned version cannot be parsed, which
  is the same malformed-definition case the Show page reports inline.
  """
  @spec document(Context.t(), DynamicForm.Instance.t() | nil) ::
          {:ok, Document.t()} | {:error, :not_started | :no_definition}
  def document(context, parsed \\ nil)

  def document(%Context{form_instance: nil}, _parsed), do: {:error, :not_started}

  def document(%Context{form_instance: %Instances.Form{} = instance} = context, parsed) do
    case parsed || parse(context) do
      %Instance{} = definition ->
        {:ok,
         %Document{
           title: title(context),
           subtitle: subtitle(context),
           filename: filename(context),
           details: details(instance, context),
           sections: sections(definition, instance.data || %{})
         }}

      nil ->
        {:error, :no_definition}
    end
  end

  @doc """
  A stored answer as the words a reader should see: `nil` and `""` are
  nothing at all, booleans are Yes and No, a value the question offers as a
  choice is that choice's text, a list is its members joined with commas,
  and a map — an answer to a question the definition no longer has — is
  compact JSON. `question` may be `nil`, which is what an answer with no
  question left to explain it gets.
  """
  @spec render_value(term(), Instance.Question.t() | nil) :: String.t()
  def render_value(value, question \\ nil)

  def render_value(nil, _question), do: ""
  def render_value(true, _question), do: "Yes"
  def render_value(false, _question), do: "No"

  def render_value(values, question) when is_list(values) do
    Enum.map_join(values, ", ", &render_value(&1, question))
  end

  def render_value(value, _question) when is_map(value), do: Jason.encode!(value)

  def render_value(value, question) do
    case choice_text(question, value) do
      nil -> to_string(value)
      text -> text
    end
  end

  # --- the definition, walked -------------------------------------------------

  # Sections accumulate in reverse and the run being filled is the head, so a
  # panel closing simply pushes the next run on top. The first run has no
  # title: it is the questions before any panel.
  defp sections(%Instance{elements: elements}, data) do
    [%Section{title: nil, entries: []}]
    |> walk(elements, data)
    |> Enum.reverse()
    |> Enum.map(fn %Section{} = section ->
      %{section | entries: Enum.reverse(section.entries)}
    end)
  end

  defp walk(sections, nil, _data), do: sections

  defp walk(sections, elements, data) do
    elements
    |> DynamicForm.Visibility.visible_elements(data)
    |> Enum.reduce(sections, &element(&2, &1, data))
  end

  # A titled panel opens a section of its own; an untitled one is a grouping
  # for layout, so its questions belong to the run already open
  defp element(sections, %Instance.Element{type: "panel", title: title} = panel, data)
       when is_binary(title) and title != "" do
    [%Section{title: title, entries: []} | sections]
    |> walk(panel.elements, data)
    |> then(&[%Section{title: nil, entries: []} | &1])
  end

  defp element(sections, %Instance.Element{type: "panel"} = panel, data) do
    walk(sections, panel.elements, data)
  end

  defp element(sections, %Instance.Element{type: "html", html: html}, _data)
       when is_binary(html) do
    case strip_markup(html) do
      "" -> sections
      text -> push(sections, {:text, text})
    end
  end

  defp element(sections, %Instance.Element{}, _data), do: sections

  defp element(sections, %Instance.Question{type: "paneldynamic"} = question, data) do
    entries = data |> Map.get(question.name) |> List.wrap()
    opened = [%Section{title: label(question), entries: []} | sections]

    filled =
      entries
      |> Enum.with_index(1)
      |> Enum.reduce(opened, fn {entry, index}, sections ->
        group = {:group, "#{entry_label(question)} #{index}", entry_fields(question, entry)}

        push(sections, group)
      end)

    [%Section{title: nil, entries: []} | filled]
  end

  defp element(sections, %Instance.Question{} = question, data) do
    push(
      sections,
      {:field, label(question), render_value(Map.get(data, question.name), question)}
    )
  end

  # One entry of a repeating question: its template's questions, answered
  # from the entry's own map. Visibility inside an entry is judged against
  # that entry, which is how SurveyJS scopes it.
  defp entry_fields(question, entry) when is_map(entry) do
    (question.templateElements || [])
    |> DynamicForm.Visibility.visible_elements(entry)
    |> Enum.flat_map(fn
      %Instance.Question{type: "paneldynamic"} -> []
      %Instance.Question{} = q -> [{:field, label(q), render_value(Map.get(entry, q.name), q)}]
      %Instance.Element{} -> []
    end)
  end

  defp entry_fields(_question, _entry), do: []

  defp push([%Section{} = section | rest], entry) do
    [%{section | entries: [entry | section.entries]} | rest]
  end

  defp label(%Instance.Question{} = question) do
    Instance.label_text(question) || question.name
  end

  defp entry_label(%Instance.Question{templateTitle: title})
       when is_binary(title) and title != "",
       do: title

  defp entry_label(_question), do: "Entry"

  defp choice_text(%Instance.Question{choices: choices}, value) when is_list(choices) do
    Enum.find_value(choices, fn
      {text, ^value} -> text
      {text, choice} -> to_string(choice) == to_string(value) && text
      _other -> nil
    end)
  end

  defp choice_text(_question, _value), do: nil

  # A definition's static content is authored as HTML. A printed document has
  # no markup, so the tags come out and the entities that survive them are
  # decoded — enough to read, which is all this content is for.
  defp strip_markup(html) do
    html
    |> String.replace(~r/<(script|style)\b[^>]*>.*?<\/\1>/is, " ")
    |> String.replace(~r/<br\s*\/?>|<\/(p|div|li|h[1-6])>/i, " ")
    |> String.replace(~r/<[^>]*>/, "")
    |> String.replace("&nbsp;", " ")
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  # --- the heading ------------------------------------------------------------

  defp title(%Context{form_progress: %FormProgress{} = progress}),
    do: FlowProgress.qualified_label(progress)

  defp title(%Context{form: %{name: name}}) when is_binary(name), do: name
  defp title(_context), do: "Form"

  defp subtitle(%Context{flow: %{name: name}}) when is_binary(name), do: name
  defp subtitle(_context), do: nil

  defp filename(context) do
    Document.slugify("#{subtitle(context)} #{title(context)}", "form")
  end

  defp details(%Instances.Form{} = instance, context) do
    [
      {"Status", status(instance)},
      {"Started", stamp(instance.inserted_at)},
      {"Submitted", stamp(instance.completed_at)},
      {"Flow instance", context.flow_instance && context.flow_instance.id},
      {"Form version", instance.template_form_version_id}
    ]
    |> Enum.reject(fn {_label, value} -> value in [nil, ""] end)
  end

  defp status(%Instances.Form{status: "completed"}), do: "Submitted"
  defp status(%Instances.Form{status: "in_progress"}), do: "In progress"
  defp status(%Instances.Form{status: status}), do: to_string(status)

  defp stamp(nil), do: nil
  defp stamp(at), do: Calendar.strftime(at, "%Y-%m-%d %H:%M UTC")

  # The same posture the pages take with an admin-authored definition: a
  # malformed one is an answer the caller reports, never a crash
  defp parse(%Context{form_version: %{definition: definition}}) do
    DynamicForm.Parser.FromData.parse!(definition)
  rescue
    _error -> nil
  end

  defp parse(_context), do: nil
end
