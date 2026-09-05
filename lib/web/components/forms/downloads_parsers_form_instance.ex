defmodule FormFlow.Web.Components.Forms.Downloads.Parsers.FormInstance do
  @moduledoc """
  Turns one form instance — a user's answers at one position of a flow
  instance — into a `FormFlow.Web.Downloads.Document`.

  This is the first of the download parsers, and the shape the ones after it
  follow: it knows one resource, produces the shared document, and knows
  nothing about PDFs. It sits among the components that draw a form because
  it reads the same thing they do — the pinned definition and the answers
  against it — only onto paper rather than onto a page. It reads the same
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
      group per entry the user added, each group the template answered for
      that entry and headed the way the page heads it — the template's
      `templateTitle` with `{panelIndex}` filled in, and no heading where the
      template sets none
    * nesting is followed all the way down: a panel inside a template is a
      group inside the entry's group, and a repeating question inside one —
      users, each with their email addresses — is a group of groups
    * a static content element becomes a line of prose, its markup stripped
      — a definition's headings and notes are part of what the form said
    * every other question becomes a field: its title, and its answer
      rendered through `render_value/2`

  A question the definition hides at these answers (`visibleIf`) is left
  out, so the printout shows the form the user actually saw rather than
  every branch of it. A question the user did not answer is kept, because a
  record says what was left blank as much as what was filled in.

  A label prints what `DynamicForm` draws, and nothing it does not: a
  placeholder it leaves alone — `{panel.field}` in a heading, say — is
  printed as written, and an entry it heads with nothing is headed with
  nothing here. Teaching the printout to say more would make the paper
  disagree with the screen, which is the one thing this parser is for.
  `{panelIndex}` is filled in because `DynamicForm` fills it in.

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
  alias FormFlow.Web.Downloads.Document
  alias FormFlow.Web.Downloads.Document.Section

  # The placeholder a `templateTitle` puts the entry's 1-based number in —
  # SurveyJS's, and what `DynamicForm` substitutes when it draws the heading
  @panel_index "{panelIndex}"

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
    opened = [%Section{title: label(question), entries: []} | sections]
    filled = Enum.reduce(panel_groups(question, data, data), opened, &push(&2, &1))

    [%Section{title: nil, entries: []} | filled]
  end

  defp element(sections, %Instance.Question{} = question, data) do
    push(
      sections,
      {:field, label(question), render_value(Map.get(data, question.name), question)}
    )
  end

  # --- inside a repeating question --------------------------------------------

  # Below the top level there are no more sections to open, so everything a
  # template holds becomes entries: a titled panel is a nested group, a
  # repeating question is a nested group of groups, and the rest is fields
  # and prose. `data` is what answers are read from and `seen` is what
  # visibility is judged against — the same two the browser's renderer keeps
  # apart, and equal everywhere except inside an entry.
  defp entries(elements, data, seen) do
    elements
    |> List.wrap()
    |> DynamicForm.Visibility.visible_elements(seen)
    |> Enum.flat_map(&entry(&1, data, seen))
  end

  defp entry(%Instance.Element{type: "panel", title: title} = panel, data, seen)
       when is_binary(title) and title != "" do
    [{:group, title, entries(panel.elements, data, seen)}]
  end

  defp entry(%Instance.Element{type: "panel"} = panel, data, seen) do
    entries(panel.elements, data, seen)
  end

  defp entry(%Instance.Element{type: "html", html: html}, _data, _seen) when is_binary(html) do
    case strip_markup(html) do
      "" -> []
      text -> [{:text, text}]
    end
  end

  defp entry(%Instance.Element{}, _data, _seen), do: []

  defp entry(%Instance.Question{type: "paneldynamic"} = question, data, seen) do
    [{:group, label(question), panel_groups(question, data, seen)}]
  end

  defp entry(%Instance.Question{} = question, data, _seen) do
    [{:field, label(question), render_value(Map.get(data, question.name), question)}]
  end

  # One group per entry the user added, each the template answered for that
  # entry. A form that nests a repeating question inside a repeating question
  # — users, each with their email addresses — nests here the same way: a
  # printout is only useful if it has the shape the answers do.
  defp panel_groups(question, data, seen) do
    data
    |> Map.get(question.name)
    |> List.wrap()
    |> Enum.with_index()
    |> Enum.map(fn {entry, index} ->
      entry = if is_map(entry), do: entry, else: %{}

      {:group, entry_title(question, index),
       entries(question.templateElements, entry, entry_seen(entry, seen))}
    end)
  end

  # What an entry's template is judged visible against, built the way
  # `DynamicForm.NestedForms` builds it: the entry's own values over the
  # enclosing form's, plus the `panel.`-prefixed copies a `{panel.field}`
  # reference resolves through. Answers still come from the entry alone, so a
  # question the entry never answered stays blank rather than borrowing the
  # form's value of the same name.
  defp entry_seen(entry, seen) do
    seen
    |> Map.merge(entry)
    |> Map.merge(Map.new(entry, fn {key, value} -> {"panel.#{key}", value} end))
  end

  defp push([%Section{} = section | rest], entry) do
    [%{section | entries: [entry | section.entries]} | rest]
  end

  defp label(%Instance.Question{} = question) do
    Instance.label_text(question) || question.name
  end

  # The per-entry heading, the way `DynamicForm` draws it: the template's
  # `templateTitle` with `{panelIndex}` filled in, and no heading at all when
  # the template sets none. The entry is still its own group either way —
  # what separates two untitled entries on the page is the card drawn around
  # each, not a heading.
  defp entry_title(%Instance.Question{templateTitle: title}, index) do
    unless Instance.blank?(title) do
      String.replace(title, @panel_index, to_string(index + 1))
    end
  end

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
