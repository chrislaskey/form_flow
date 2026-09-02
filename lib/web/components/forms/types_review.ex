defmodule FormFlow.Web.Components.Forms.Types.Review do
  @moduledoc """
  Form type `"review"`: a form for checking an earlier form's answers. Both
  pages show that form read-only on the left — the same rendering the
  user-facing Show page gives submitted answers — and this form on the
  right: as designed and editable on the edit page, read-only on Show.

  Which earlier form is the type's one property, `"source"`, a
  `:related_form` an admin picks on the form edit page from the forms before
  this one in the flow. At render it resolves through
  `FormFlow.Config.Forms.Type.related_form/2` to that form as it stands in
  this flow instance. A source that doesn't resolve — unset, blank, or a path
  the flow no longer has, however it came about — is one error with one fix,
  an administrator choosing again, and is said so in its place; a source the
  user hasn't reached yet is not an error and says that instead. The review
  form itself stays editable either way.

  ## What was reviewed

  Submitting the review records what it reviewed on its own completion event
  (`snapshot_data/2`): the source's id, its pinned version id, its
  `completed_at`, and its answers as they were rendered, under `"reviewed"`
  in the event's `snapshot_data`. Structure by reference — the version is
  immutable — and answers by copy, because the source can be resubmitted,
  reconciled, or deleted, and a review that carries its own record is
  stronger evidence than one reconstructed from other tables. The library
  blanks the copy when the source is deleted
  (`FormFlow.Data.Instances.Forms.redact_snapshots/1`). A host that cannot
  hold duplicated personal data overrides `snapshot_data/2` in its own
  review type to store identifiers only.

  A source that did not resolve, or had no instance, at review time records
  `%{"path" => …, "instance_id" => nil}` — that nothing was reviewed is
  itself worth recording.

  ## Staleness

  At render, the type reads that record and the source instance's event
  trail (`FormFlow.Data.Instances.Forms.list_events/2`) and calls the review
  stale when the source has any event newer than the review's completion.
  The headline is the latest thing that happened to the source — submitted
  again, reopened, moved to a new version, replaced, deleted — and a diff of
  the recorded answers against the source's current ones follows where one
  makes sense. A structure change since the review rides along as a caveat on
  the diff rather than outranking a change to the answers. Staleness is
  information, never action: nothing is reopened, blocked, or sent. The
  review stays editable on the edit page in every state, and resubmitting it
  writes a fresh record, which is how a review becomes current again.

  `staleness/4` and `diff/4` are pure, so the rules are tested without a
  database; the pages call them with what they load.
  """

  use FormFlow.Config.Forms.Type
  use Phoenix.Component

  alias FormFlow.Config.Forms.Type
  alias FormFlow.Config.Property
  alias FormFlow.Data.Instances
  alias FormFlow.Data.Instances.FlowProgress
  alias FormFlow.Data.Instances.Form.Event
  alias FormFlow.Data.Instances.FormProgress
  alias FormFlow.Data.Templates

  @typedoc """
  What has happened to the reviewed form since the review:

    * `:never_reviewed` — the review has no completion on record
    * `:current` — nothing has happened to the source since, or nothing was
      reviewed (the source had not been started)
    * `:redacted` — the review stands, but the record of what it reviewed
      was erased when the source was deleted out of the journey
    * `{:stale, cause, structure_changed?: boolean()}` — the source moved on;
      `cause` is the latest thing that happened to it, and
      `structure_changed?` says whether its pinned version differs from the
      one reviewed
  """
  @type staleness ::
          :never_reviewed
          | :current
          | :redacted
          | {:stale, cause(), structure_changed?: boolean()}

  @type cause :: :resubmitted | :reopened | :migrated | :replaced | :deleted

  @typedoc "One changed answer: its title as reviewed, its title now, and both values rendered."
  @type change ::
          {old_title :: String.t(), new_title :: String.t(), old :: String.t(), new :: String.t()}

  @doc "The type's properties: the form to review."
  def properties do
    [
      %Property{
        id: "source",
        name: "Form to review",
        description: "The earlier form whose answers this one shows for checking.",
        type: :related_form,
        required: true
      }
    ]
  end

  @impl true
  def edit_component(assigns) do
    # A plain map from the edit page, not a component's assigns — merged, not
    # assign/2'd, and rendered without change tracking
    assigns = Map.merge(assigns, review_assigns(assigns))

    ~H"""
    <.panes id={@id} review={@review}>
      {Type.Default.edit_component(assigns)}
    </.panes>
    """
  end

  @impl true
  def show_component(assigns) do
    assigns = Map.merge(assigns, review_assigns(assigns))

    ~H"""
    <.panes id={@id} review={@review}>
      {Type.Default.show_component(assigns)}
    </.panes>
    """
  end

  @impl true
  def snapshot_data(context, _config_data) do
    path = (context.form_type_property_values || %{})["source"]

    %{"reviewed" => reviewed(path, Type.related_form(context, "source"))}
  end

  defp reviewed(path, %FormProgress{instance: %Instances.Form{} = instance}) do
    %{
      "path" => path,
      "instance_id" => instance.id,
      "version_id" => instance.template_form_version_id,
      "completed_at" => instance.completed_at && DateTime.to_iso8601(instance.completed_at),
      "data" => instance.data
    }
  end

  defp reviewed(path, _source), do: %{"path" => path, "instance_id" => nil}

  @doc """
  What has happened to the source since the review, from the review's
  completion event (`review_completion`, the clock), the `"reviewed"` record
  that event holds (`snapshot`), the source as it stands (`source`), and the
  source instance's event trail (`source_events`). The rules, in order:

  1. No completion, or one with no record → `:never_reviewed`.
  2. The record names no instance → `:current`; nothing was reviewed, and
     the source pane already says why.
  3. The record was redacted → `:redacted`; no diff is possible.
  4. The source has no instance now → `{:stale, :deleted, …}`.
  5. The source's instance is not the one recorded → `{:stale, :replaced, …}`.
  6. The source events strictly newer than the completion decide: none →
     `:current`; otherwise the latest gives the cause — `status_changed` is
     `:resubmitted`; `reopened` is `:reopened` when a user did it and
     `:migrated` when a publish policy did (`to_version_id` set), as is
     `migrated` itself.

  `structure_changed?` is true when any newer event moved the pin or the
  source's pinned version differs from the recorded one.
  """
  @spec staleness(Event.t() | nil, map() | nil, FormProgress.t() | nil, [Event.t()]) ::
          staleness()
  def staleness(review_completion, snapshot, source, source_events)

  def staleness(nil, _snapshot, _source, _events), do: :never_reviewed
  def staleness(_completion, nil, _source, _events), do: :never_reviewed
  def staleness(_completion, %{"instance_id" => nil}, _source, _events), do: :current
  def staleness(_completion, %{"redacted_at" => _at}, _source, _events), do: :redacted

  def staleness(%Event{} = completion, snapshot, source, events) do
    reviewed_id = snapshot["instance_id"]

    case source && source.instance do
      nil ->
        {:stale, :deleted, structure_changed?: false}

      %Instances.Form{id: id} = instance when id != reviewed_id ->
        {:stale, :replaced, structure_changed?: version_changed?(instance, snapshot)}

      %Instances.Form{} = instance ->
        newer =
          Enum.filter(events, fn event ->
            event.event != "created" and
              DateTime.compare(event.inserted_at, completion.inserted_at) == :gt
          end)

        case List.last(newer) do
          nil ->
            :current

          latest ->
            {:stale, cause(latest),
             structure_changed?:
               Enum.any?(newer, & &1.to_version_id) or version_changed?(instance, snapshot)}
        end
    end
  end

  defp cause(%Event{event: "status_changed"}), do: :resubmitted
  defp cause(%Event{event: "reopened", to_version_id: nil}), do: :reopened
  defp cause(%Event{event: "reopened"}), do: :migrated
  defp cause(%Event{event: "migrated"}), do: :migrated

  defp version_changed?(instance, snapshot),
    do: instance.template_form_version_id != snapshot["version_id"]

  @doc """
  The answers that differ between what was reviewed and what the source holds
  now, one `t:change/0` per key from the union of both maps, in the order the
  definitions ask the questions. Titles come from the definitions — the
  reviewed version's for the old side, the current one's for the new — and
  fall back to the key; either definition may be nil. Values render through
  one rule: lists joined with commas, maps as compact JSON, booleans as
  Yes/No, nothing as an empty string, everything else `to_string/1`.
  """
  @spec diff(map(), map(), DynamicForm.Instance.t() | nil, DynamicForm.Instance.t() | nil) ::
          [change()]
  def diff(old_data, new_data, old_definition, new_definition) do
    old_data = old_data || %{}
    new_data = new_data || %{}
    old_titles = titles(old_definition)
    new_titles = titles(new_definition)

    for key <- ordered_keys(old_data, new_data, new_titles ++ old_titles),
        Map.get(old_data, key) != Map.get(new_data, key) do
      {title(old_titles, key), title(new_titles, key), render_value(Map.get(old_data, key)),
       render_value(Map.get(new_data, key))}
    end
  end

  # The definitions' question order first (the current one's, then the
  # reviewed one's for questions it no longer asks), then anything answered
  # outside either, sorted
  defp ordered_keys(old_data, new_data, titles) do
    keys = MapSet.new(Map.keys(old_data) ++ Map.keys(new_data))

    known =
      titles |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.filter(&MapSet.member?(keys, &1))

    known ++ Enum.sort(Enum.reject(keys, &(&1 in known)))
  end

  # `{name, title}` pairs over a definition's elements in question order,
  # panels and dynamic panels included; [] for no definition
  defp titles(nil), do: []
  defp titles(%{elements: elements}), do: elements |> collect_titles([]) |> Enum.reverse()

  defp title(titles, key) do
    case List.keyfind(titles, key, 0) do
      {_key, title} -> title
      nil -> key
    end
  end

  defp collect_titles(nil, acc), do: acc

  defp collect_titles(elements, acc) do
    Enum.reduce(elements, acc, fn element, acc ->
      acc =
        case {Map.get(element, :name), Map.get(element, :title)} do
          {name, title} when is_binary(name) and is_binary(title) -> [{name, title} | acc]
          _other -> acc
        end

      acc
      |> then(&collect_titles(Map.get(element, :elements), &1))
      |> then(&collect_titles(Map.get(element, :templateElements), &1))
    end)
  end

  defp render_value(nil), do: ""
  defp render_value(true), do: "Yes"
  defp render_value(false), do: "No"
  defp render_value(list) when is_list(list), do: Enum.map_join(list, ", ", &render_value/1)
  defp render_value(map) when is_map(map), do: Jason.encode!(map)
  defp render_value(other), do: to_string(other)

  # --- rendering --------------------------------------------------------------

  # Everything both pages draw around the review form: the source and its
  # parsed definition, and what has happened to it since the review. Two
  # queries — the review's completion and the source's trail — in a render
  # path, on top of the version load; accepted for now.
  defp review_assigns(%{context: context}) do
    source = Type.related_form(context, "source")

    completion =
      context.form_instance &&
        Instances.Forms.latest_event(context.form_instance, "status_changed")

    snapshot = completion && get_in(completion.snapshot_data, ["reviewed"])

    source_events =
      case source do
        %FormProgress{instance: %Instances.Form{} = instance} ->
          Instances.Forms.list_events(instance)

        _other ->
          []
      end

    # An unresolved source is the "missing" error and nothing else (D8)
    staleness =
      if source, do: staleness(completion, snapshot, source, source_events), else: :never_reviewed

    %{
      review: %{
        source: source,
        source_parsed: parse(source),
        completion: completion,
        snapshot: snapshot,
        source_events: source_events,
        staleness: staleness
      }
    }
  end

  attr(:id, :string, required: true)
  attr(:review, :map, required: true, doc: "what review_assigns/1 loaded")
  slot(:inner_block, required: true)

  defp panes(assigns) do
    assigns = assign(assigns, :source, assigns.review.source)

    ~H"""
    <div class="flex flex-wrap gap-6">
      <section class="min-w-0 flex-1">
        <h3 class="mb-2 text-xs font-medium text-zinc-500">
          Reviewing{if @source, do: ": #{FlowProgress.qualified_label(@source)}"}
        </h3>
        <p :if={is_nil(@source)} class="text-sm text-red-600">
          The form to review is missing — an administrator needs to choose it on this form's settings.
        </p>
        <p :if={@source && is_nil(@source.instance)} class="text-sm text-zinc-500">
          {FlowProgress.qualified_label(@source)} hasn't been started yet, so there is nothing to review.
        </p>
        <.notice :if={@source} id={"#{@id}-review-notice"} review={@review} />
        <%!-- Read-only the way the Show page does it: a disabled fieldset
              around the form, its submit button hidden --%>
        <fieldset :if={@review.source_parsed} disabled class="max-w-md">
          <DynamicForm.form
            id={"#{@id}-source-#{@source.instance.id}"}
            instance={@review.source_parsed}
            data={@source.instance.data}
            hide_submit
          />
        </fieldset>
      </section>
      <section class="min-w-0 flex-1">
        {render_slot(@inner_block)}
      </section>
    </div>
    """
  end

  attr(:id, :string, required: true)
  attr(:review, :map, required: true)

  defp notice(%{review: %{staleness: :never_reviewed}} = assigns) do
    ~H""
  end

  defp notice(%{review: %{staleness: :current}} = assigns) do
    ~H"""
    <p id={@id} class="mb-2 text-xs text-zinc-500">
      Reviewed {stamp(@review.completion.inserted_at)}. Unchanged since.
    </p>
    """
  end

  defp notice(%{review: %{staleness: :redacted}} = assigns) do
    ~H"""
    <p id={@id} class="mb-2 text-xs text-zinc-500">
      Reviewed {stamp(@review.completion.inserted_at)}. The record of what was reviewed has been erased.
    </p>
    """
  end

  defp notice(
         %{review: %{staleness: {:stale, cause, structure_changed?: structure_changed?}}} =
           assigns
       ) do
    assigns =
      assigns
      |> assign(:cause, cause)
      |> assign(:structure_changed?, structure_changed?)
      |> assign(:label, FlowProgress.qualified_label(assigns.review.source))
      |> assign(:latest, List.last(assigns.review.source_events))

    ~H"""
    <div
      id={@id}
      class="mb-3 rounded-md border border-amber-300 bg-amber-50 px-3 py-2 text-xs text-amber-800"
    >
      <p class="font-medium">
        <%= case @cause do %>
          <% :resubmitted -> %>
            {@label} was submitted again on {stamp(@latest.inserted_at)}, after this review.
          <% :reopened -> %>
            {@label} is being edited — reopened on {stamp(@latest.inserted_at)}, not yet resubmitted.
          <% :migrated -> %>
            {@label}'s form changed after this review (a new version was published).
          <% :replaced -> %>
            The {@label} reviewed here was replaced; these are the new answers.
          <% :deleted -> %>
            The {@label} reviewed here has been deleted.
        <% end %>
      </p>
      <p :if={@structure_changed? and @cause in [:resubmitted, :migrated, :replaced]} class="mt-1">
        The form's structure also changed since this review, so these may not line up.
      </p>
      <.changes
        :if={@cause in [:resubmitted, :migrated, :replaced]}
        changes={changed_answers(@review, @structure_changed?)}
      />
      <.reviewed_answers :if={@cause == :deleted} snapshot={@review.snapshot} />
    </div>
    """
  end

  attr(:changes, :list, required: true)

  defp changes(%{changes: []} = assigns) do
    ~H"""
    <p class="mt-1">The answers are the same as reviewed.</p>
    """
  end

  defp changes(assigns) do
    ~H"""
    <table class="mt-2 w-full text-left">
      <thead>
        <tr class="text-amber-700">
          <th class="pr-3 font-medium">Question</th>
          <th class="pr-3 font-medium">Reviewed</th>
          <th class="font-medium">Now</th>
        </tr>
      </thead>
      <tbody>
        <tr :for={{old_title, new_title, old, new} <- @changes} class="align-top">
          <td class="pr-3">
            {new_title}<span :if={old_title != new_title} class="text-amber-600">
              (was {old_title})</span>
          </td>
          <td class="pr-3 font-mono">{old}</td>
          <td class="font-mono">{new}</td>
        </tr>
      </tbody>
    </table>
    """
  end

  attr(:snapshot, :map, required: true)

  defp reviewed_answers(assigns) do
    titles = assigns.snapshot["version_id"] |> load_definition() |> titles()
    data = assigns.snapshot["data"] || %{}

    assigns =
      assign(
        assigns,
        :answers,
        for(
          key <- ordered_keys(data, %{}, titles),
          do: {title(titles, key), render_value(data[key])}
        )
      )

    ~H"""
    <p class="mt-1">The answers as reviewed:</p>
    <dl class="mt-1 grid grid-cols-[auto_1fr] gap-x-3">
      <%= for {title, value} <- @answers do %>
        <dt class="font-medium">{title}</dt>
        <dd class="font-mono">{value}</dd>
      <% end %>
    </dl>
    """
  end

  # The diff between the recorded answers and the source's current ones. The
  # current pinned definition titles both sides unless the structure moved,
  # when the reviewed version is loaded for the old side — the rare path.
  defp changed_answers(
         %{snapshot: snapshot, source: source, source_parsed: parsed},
         structure_changed?
       ) do
    old_definition =
      if structure_changed?, do: load_definition(snapshot["version_id"]), else: parsed

    diff(snapshot["data"], source.instance.data, old_definition, parsed)
  end

  defp stamp(%DateTime{} = at), do: Calendar.strftime(at, "%Y-%m-%d %H:%M") <> " UTC"

  # The source's pinned definition, parsed — nil with no instance to show,
  # and nil rather than a crash for a malformed definition (the same posture
  # as the form pages)
  defp parse(%{instance: %{template_form_version_id: version_id}}),
    do: load_definition(version_id)

  defp parse(_source), do: nil

  defp load_definition(nil), do: nil

  defp load_definition(version_id) do
    case Templates.Forms.get_version(version_id) do
      nil -> nil
      version -> DynamicForm.Parser.FromData.parse!(version.definition)
    end
  rescue
    _error -> nil
  end
end
