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

  alias FormFlow.Config.Flows.Perspective
  alias FormFlow.Config.Property
  alias FormFlow.Data.Instances.FlowProgress
  alias FormFlow.Data.Templates

  @prefix "property_"
  @path_separator "/"

  @doc "The type among `types` with `id`, or nil."
  def type(types, id), do: Enum.find(types, &(&1.id == id))

  @doc """
  The type id a stored value amounts to: itself when set, otherwise the first
  of `types` — the one every page resolves an unset type to
  (`FormFlow.Web.Instances.Forms.Shared.flow_type/2`), so the edit and show
  pages present a flow that never chose as what it will behave as. `nil`
  when there are no types to choose from.
  """
  def effective_type(types, nil), do: with(%{id: id} <- List.first(types), do: id)
  def effective_type(_types, id), do: id

  @doc """
  The page's `flow_types` for the flow at the context's `:subflow`: flow
  types apply to "forms" flows, so a "subflows" flow — or no flow — gets
  none, and no dropdown.
  """
  def flow_types_for(%FormFlow.Context{subflow: %{label: "forms"}}, assigns),
    do: assigns.flow_types

  def flow_types_for(_context, _assigns), do: []

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
  The forms a root flow's steps point at, subflows included, in the order a
  user works them, as `{qualified label, form, node}` — the label is the
  step's (`FormFlow.Data.Instances.FlowProgress.qualified_label/1`,
  "Documents / Proof of address"), the form the lineage it points at, the
  node the step itself, whose `slug` is how the pages name a flow's form
  (an owned form has none of its own). Each form once, at its first step,
  so a catalog form reused at two steps is offered once. Empty with no
  root, or a root that no longer exists.
  """
  def flow_forms(nil), do: []

  def flow_forms(root_id) do
    case Templates.Flows.resolve_tree(root_id) do
      nil ->
        []

      tree ->
        tree
        |> FlowProgress.forms([])
        |> Enum.flat_map(&flow_form/1)
        |> Enum.uniq_by(fn {_label, form, _node} -> form.id end)
    end
  end

  # The step's form: the node's form_id is the lineage. A node whose form is
  # gone offers nothing.
  defp flow_form(%{node: node} = progress) do
    case node.form_id && Templates.Forms.get(node.form_id) do
      %{} = form -> [{FlowProgress.qualified_label(progress), form, node}]
      _none -> []
    end
  end

  @doc """
  Where a form is used, one line per step, from
  `FormFlow.Data.Templates.Flows.form_usages/1`: the root flow's name, then
  the containing flow's when the step sits in a subflow — "Dog License /
  Application", or "Dog License" for a step in the root itself. Each place
  once: two steps of one flow pointing at the same form read as one use.
  """
  def usage_labels(usages) do
    usages
    |> Enum.map(fn %{flow: flow, root: root} ->
      if flow.id == root.id, do: root.name, else: "#{root.name} / #{flow.name}"
    end)
    |> Enum.uniq()
  end

  @doc """
  Names joined as a sentence lists them: "A", "A and B", "A, B, and C".
  """
  def list_names([]), do: ""
  def list_names([one]), do: one
  def list_names([one, two]), do: "#{one} and #{two}"

  def list_names(names) do
    {rest, [last]} = Enum.split(names, -1)
    Enum.join(rest, ", ") <> ", and " <> last
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
  payload; the set is bounded by what the type declares.
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
  The perspectives the type with `id` declares (`FormFlow.Config.Flows.Type`'s
  `:perspectives`) — the identity form's multi-select for a flow of that
  type. None for no type, or a type that declares none.
  """
  def perspectives(types, id) do
    case type(types, id) do
      nil -> []
      type -> type.perspectives
    end
  end

  @doc """
  Every perspective any of `types` declares, once each by id — what a
  canvas needs to name the perspectives of subflow nodes whose embedded
  flows may be of different types.
  """
  def all_perspectives(types) do
    types |> Enum.flat_map(& &1.perspectives) |> Enum.uniq_by(& &1.id)
  end

  @doc "The perspectives as the checkbox field's `{label, id}` options."
  def perspective_options(perspectives), do: Enum.map(perspectives, &{&1.name, &1.id})

  @perspectives_help "Which kinds of user this flow's forms are for. None means everyone."

  @doc """
  The perspectives field's help text — with a note when the flow stores an id
  the type no longer declares: the field cannot show it, and the next save
  drops it, so the admin should know.
  """
  def perspectives_description(flow, perspectives) do
    case Perspective.stale_ids(flow, perspectives) do
      [] ->
        @perspectives_help

      stale ->
        @perspectives_help <>
          " The saved choice #{Enum.join(stale, ", ")} is no longer offered — it is dropped on save."
    end
  end

  @doc """
  The name the copy dialog prefills for a copy of `flow`: the source's with
  "(copy)" after it, so two rows on the index never read the same. The word
  is what most tools say of a copy; an admin naming a new year types over it.
  """
  def copy_name(%Templates.Flow{name: name}), do: "#{name || "Untitled"} (copy)"

  @doc """
  The copy dialog's submit: `FormFlow.Data.Templates.Flows.copy/2` of `flow`
  with the dialog's `name` and `slug` — a blank name is the one the dialog
  offered (`copy_name/1`), a blank slug leaves the choice to `copy/2` — and
  the host's `types` (`flow_types:`, `form_types:`) so the copy's health is
  checked once and cached. Returns the copy, or the message the dialog
  shows: a refused slug by name, anything else as a retry.
  """
  def copy_flow(%Templates.Flow{} = flow, params, types) do
    name = blank_to_nil(params["name"]) || copy_name(flow)
    opts = [name: name, slug: blank_to_nil(params["slug"])] ++ types

    case Templates.Flows.copy(flow, opts) do
      {:ok, copy} ->
        {:ok, copy}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, save_error(changeset, "Could not copy the flow. Please try again.")}

      {:error, _reason} ->
        {:error, "Could not copy the flow. Please try again."}
    end
  end

  @doc """
  A flow status as the badge and the dropdown say it: the atom's words,
  capitalised once (`"winding_down"` → "Winding down").
  """
  def status_label(status) when is_binary(status) do
    status |> String.replace("_", " ") |> String.capitalize()
  end

  @doc "The status dropdown's options, in `FormFlow.Data.Templates.Flow.statuses/0` order."
  def status_options, do: Enum.map(Templates.Flow.statuses(), &{status_label(&1), &1})

  @doc """
  What a status means for users, in one or two sentences — drawn under the
  dropdown on the flow edit page as the choice is made, and as a badge's
  title. The three facts of `FormFlow.Data.Templates.Flow.allows?/2` — start,
  continue, see — said as what a user can do.
  """
  def status_summary("draft"),
    do:
      "Not offered to users, and hidden from them: nobody can start it, and anyone who " <>
        "already has an instance cannot continue or see it until the flow is opened."

  def status_summary("open"),
    do: "Offered to users: anyone the page allows can start it, continue it, and see it."

  def status_summary("winding_down"),
    do:
      "No longer taking new starts. Anyone who already has an instance can continue and " <>
        "can see it."

  def status_summary("read_only"),
    do:
      "Nothing changes: nobody can start or continue. Everyone can still see their own " <>
        "instances, and download or print them."

  def status_summary("archived"),
    do:
      "Put away. Users see nothing of it — not even their own instances — while admins " <>
        "keep the flow, its instances, and its history."

  def status_summary(_unknown), do: nil

  @doc """
  The badge kind a status draws in: a draft is quiet, an open flow is the
  good state, a winding-down one is worth a glance.
  """
  def status_kind("open"), do: :success
  def status_kind("winding_down"), do: :warning
  def status_kind("read_only"), do: :info
  def status_kind(_draft_archived_or_other), do: :neutral

  @doc """
  How many instances a root flow has, and how many are still in progress —
  the sentence under the status dropdown, so an admin reads who a change
  reaches before making it. `nil` for an owned flow, whose instances are
  the root's.
  """
  def instance_counts(%Templates.Flow{owner_flow_id: nil} = flow),
    do: Templates.Flows.instance_counts(flow)

  def instance_counts(_owned), do: nil

  @doc "The counts as a sentence, or nothing when there is nothing to say."
  def instance_counts_sentence(nil), do: nil

  def instance_counts_sentence(%{"in_progress" => in_progress, "completed" => completed}) do
    case in_progress + completed do
      0 -> "Nobody has started this flow yet."
      started -> "#{count(started, "instance")} started, #{in_progress} still in progress."
    end
  end

  defp count(1, noun), do: "1 #{noun}"
  defp count(n, noun), do: "#{n} #{noun}s"

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(_value), do: nil

  @doc """
  The message a failed template save shows. A slug the changeset refused —
  taken, or malformed — is named, since it is the one field an admin can
  fix by typing. A refusal on `:nodes` — a step pasted from a source that is
  gone, a step the tree does not own, a removed form that still has data —
  is already a sentence saying what to do, and is shown as it is; anything
  else is the generic retry.
  """
  def save_error(%Ecto.Changeset{errors: errors}, fallback) do
    cond do
      message = error_message(errors, :slug) -> "The slug #{message}."
      message = error_message(errors, :nodes) -> sentence(message)
      true -> fallback
    end
  end

  defp error_message(errors, key) do
    case Keyword.get(errors, key) do
      {message, _opts} -> message
      nil -> nil
    end
  end

  defp sentence(message) do
    {first, rest} = String.split_at(message, 1)
    String.upcase(first) <> rest <> "."
  end
end
