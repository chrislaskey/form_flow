defmodule FormFlow.Web.Templates.Forms.Shared do
  @moduledoc """
  `FormFlow.Web.Templates.Forms.Shared` is what the form pages have in
  common: the details they edit, and the prefills they fill their preview
  with.

  A form's **details** — its name, slug, description, and type with the
  type's property values — belong to the lineage, not to a version. They
  change the moment they are saved, and every version shows the change,
  published ones included. Two pages edit them through the same `DynamicForm`
  fields: `FormFlow.Web.Templates.Forms.Edit` while the form has never been
  published, beside the draft's definition, since nothing published can be
  disturbed yet; and `FormFlow.Web.Templates.Forms.Details` on its own page
  once it has, so that an edit reaching every published version is made
  deliberately, on a page that says so. This module is the data those
  fields read and write, so the two pages agree on what a save does.

  Through a step the Name and Slug fields are the step's — the node's
  label, which is what the instance pages show users, and the node's slug.
  An owned form's name is the same value, written alongside; a catalog
  form's name and slug are its own, edited on its catalog page, and from a
  step the save leaves them alone. Standalone (no node), both fields are
  the form's own.

  ## Prefills

  `FormFlow.Web.Templates.Forms.Show` and `FormFlow.Web.Templates.Forms.Edit`
  both draw the form's prefills beside their preview
  (`FormFlow.Web.Components.Forms.PrefillPicker`) and both write them
  (`FormFlow.Web.Components.Forms.PrefillMenu` and its dialog), so what
  these two pages agree on is here: the assigns the picker reads, and the URL
  the selection lives in. What the *three* pages that write a prefill agree
  on — the instance's Edit page is the third — is
  `FormFlow.Web.Components.Forms.Prefills`.

  What is nowhere shared is what a page does about a navigation: Show goes
  straight there, while Edit has a draft whose unsaved content a reload
  would discard, so it asks first.

  Writing a prefill never touches a version, which is why a published form —
  with no draft to edit, and so no edit page — still has somewhere to keep
  them: its Show page.
  """

  use Phoenix.Component

  alias FormFlow.Config.Forms.Type
  alias FormFlow.Data.Templates.Flows
  alias FormFlow.Data.Templates.Forms
  alias FormFlow.Web.Templates

  @doc """
  The fields' data: the saved details, with the saved type's property
  values under their field names. The type is the one the form is governed
  by — the saved one, else the first the page offers, the same fallback the
  instance pages make when they render the form
  (`FormFlow.Web.Instances.Forms.Shared.form_type/2`) — so a form that never
  picked one saves what it was already getting, explicitly.
  """
  def details(form, node, form_types) do
    type_id = type_id(form, form_types)
    values = Type.property_values(form)

    %{
      name: step_name(form, node),
      description: form.description,
      slug: step_slug(form, node),
      form_type: type_id
    }
    |> Map.merge(
      Templates.Shared.field_data(Templates.Shared.properties(form_types, type_id), values)
    )
  end

  @doc """
  What the last save wrote, in the shape `details_from/3` reports — the
  baseline a page's `dirty?` compares against, so its Save can go primary
  exactly when the fields differ from what is persisted.
  """
  def saved_details(form, node) do
    %{
      name: to_string(step_name(form, node)),
      description: to_string(form.description),
      slug: to_string(step_slug(form, node)),
      form_type: to_string(form.properties["form_type"]),
      property_values: Type.property_values(form)
    }
  end

  @doc "The details a `DynamicForm` payload holds, in the shape of `saved_details/2`."
  def details_from(payload_data, type_id, properties) do
    %{
      name: to_string(payload_data[:name] || ""),
      description: to_string(payload_data[:description] || ""),
      slug: to_string(payload_data[:slug] || ""),
      form_type: to_string(type_id),
      property_values: Templates.Shared.payload_property_values(payload_data, properties)
    }
  end

  @doc """
  The fields' data after the type dropdown changed: what was typed, with
  the new type's property fields — holding the saved values when it is the
  saved type, blank otherwise. `DynamicForm` rebuilds a form whose fields
  changed from its data, so at that moment the data becomes the pending
  values and what was typed survives. `keep` names the page's own fields
  that ride along.
  """
  def switch_type(payload_data, form, type_id, form_types, keep \\ []) do
    values = if type_id == form.properties["form_type"], do: Type.property_values(form), else: %{}

    payload_data
    |> Map.take([:name, :description, :slug | keep])
    |> Map.put(:form_type, type_id)
    |> Map.merge(
      Templates.Shared.field_data(Templates.Shared.properties(form_types, type_id), values)
    )
  end

  @doc """
  Saves the details a payload holds: each value to its owner — the step's
  name and slug to the node (`Flows.update_node/2`), the rest to the form
  row. `{:ok, form, node}`, or `{:error, reason}` for
  `save_details_error/2` to word.

  A catalog form is one lineage for every step reusing it, so a
  `:related_form` value — a position in one flow — cannot be its: the rule
  `Flows.reuse_form/3` applies when a step picks such a form, applied from
  this side when such a form picks a step. The type alone is fine; it is
  the choice that points somewhere. `FormFlow.Data.Templates.Flows.Health`
  reports the state should it arrive another way.
  """
  def save_details(form, node, payload_data, form_types) do
    type_id = presence(payload_data[:form_type])
    properties = Templates.Shared.properties(form_types, type_id)
    name = payload_data[:name]

    attrs =
      %{
        description: payload_data[:description],
        properties:
          form_properties(
            form,
            type_id,
            Templates.Shared.payload_property_values(payload_data, properties)
          )
      }
      |> put_form_name(form, node, name)
      |> put_form_slug(node, payload_data[:slug])

    with :ok <- shareable(form, attrs.properties, form_types),
         {:ok, node} <- update_step(node, name, payload_data[:slug]),
         {:ok, form} <- Forms.update(form, attrs) do
      {:ok, form, node}
    end
  end

  @doc "The sentence a refused `save_details/4` shows."
  def save_details_error(form, {:related_form_shared, property}) do
    "“#{form.name}” is shared by every flow that uses it, so it can't point " <>
      "“#{property.name}” at a step of one flow. Copy the form into this flow instead — " <>
      "the Copy form choice on the step's page — or clear the choice."
  end

  def save_details_error(_form, %Ecto.Changeset{} = changeset) do
    Templates.Shared.save_error(changeset, "Could not save. Please try again.")
  end

  @doc """
  The form's stored `properties` map with a type applied — an unset type
  removes the key and the property values with it, so "no choice" stays
  "use the configured default" rather than pinning whatever the default
  happened to be at save time. A type's property values are replaced whole,
  so switching types leaves nothing of the old one behind — and a type with
  nothing entered stores no values key at all.
  """
  def form_properties(form, nil, _values) do
    form.properties
    |> Map.delete("form_type")
    |> Map.delete("form_type_property_values")
  end

  def form_properties(form, type_id, values) when values == %{} do
    form.properties
    |> Map.put("form_type", type_id)
    |> Map.delete("form_type_property_values")
  end

  def form_properties(form, type_id, values) do
    form.properties
    |> Map.put("form_type", type_id)
    |> Map.put("form_type_property_values", values)
  end

  @doc "The type the form is governed by: the saved one, else the first offered."
  def type_id(form, form_types),
    do: Templates.Shared.effective_type(form_types, form.properties["form_type"])

  @doc "What the Name field edits: the step's label through a node, the form's own name standalone."
  def step_name(form, nil), do: form.name
  def step_name(form, node), do: get_in(node.properties, ["data", "label"]) || form.name

  @doc "What the Slug field edits: the step's slug through a node, the form's own standalone."
  def step_slug(form, nil), do: form.slug
  def step_slug(_form, node), do: node.slug

  def name_label(nil), do: "Name"
  def name_label(_node), do: "Step name"

  def slug_label(nil), do: "Slug"
  def slug_label(_node), do: "Step slug"

  def slug_placeholder(nil) do
    "A stable name for looking this form up in code — lowercase letters, numbers, _ and -. " <>
      "It does not follow a rename."
  end

  def slug_placeholder(_node) do
    "A stable name for looking this step up in code — lowercase letters, numbers, _ and -. " <>
      "It does not follow a rename."
  end

  @doc "A catalog form reused at a step keeps its own slug, and the field is not it."
  def slug_description(%{owner_flow_id: nil, slug: slug}, %{}) when is_binary(slug) do
    "The catalog form's own slug is “#{slug}”; change it on its catalog page."
  end

  def slug_description(_form, _node), do: nil

  @doc "The step's name is this flow's; a catalog form reused here is not renamed from a step."
  def name_description(%{owner_flow_id: nil} = form, %{}) do
    "This step reuses the catalog form “#{form.name}”. Renaming the step here does not " <>
      "rename the catalog form; do that on its catalog page."
  end

  def name_description(_form, _node), do: nil

  @doc "A step whose form is the catalog's: shared, and said so."
  def reusing?(%{}, %{owner_flow_id: nil}), do: true
  def reusing?(_node, _form), do: false

  # The picked form type, named and described (`FormFlow.Config.Forms.Type`),
  # in a bordered box headed "About Review form type". Nothing for no type.
  attr(:type, :any, default: nil)

  def type_callout(%{type: nil} = assigns), do: ~H""

  def type_callout(assigns) do
    ~H"""
    <div class="rounded-md border border-zinc-200 bg-zinc-50 px-3 py-2 text-sm">
      <div class="font-medium text-zinc-800">About {@type.name} form type</div>
      <p :if={@type.description} class="mt-0.5 text-xs text-zinc-600">{@type.description}</p>
    </div>
    """
  end

  @doc """
  The form's prefills, the one the URL names, and the name it named when
  the form has not got it — assigned together, since a page draws all three
  (`FormFlow.Web.Components.Forms.PrefillPicker`).
  """
  def assign_prefills(socket, form, name) do
    name = presence(name)
    prefill = form && name && Forms.get_prefill(form, name)

    Phoenix.Component.assign(socket,
      prefills: (form && Forms.list_prefills(form)) || [],
      prefill: prefill,
      missing_prefill_name: prefill == nil && name
    )
  end

  @doc """
  `path` with the prefill named, and with the params a form page carries
  across its own links. A `nil` name drops the key, which is what selecting
  nothing means.
  """
  def prefill_path(path, params, name) do
    query = Map.take(params, ["mode", "start"])
    query = if name, do: Map.put(query, "prefill", name), else: query

    case query do
      empty when empty == %{} -> path
      query -> "#{path}?#{URI.encode_query(query)}"
    end
  end

  # A part of the page: its title and one line saying what belongs there,
  # styled like DynamicForm's own nested-form heading so a page's sections
  # read as one family with its Elements. Actions ride on the title's line
  # and the description takes the line under both — sharing a row with the
  # controls would leave it a narrow column, wrapping a sentence that reads
  # across.
  attr(:title, :string, required: true)
  attr(:class, :any, default: nil)
  slot(:actions)
  slot(:inner_block, required: true)

  def section_heading(assigns) do
    ~H"""
    <div class={["min-w-0", @class]}>
      <div class="flex items-center justify-between gap-3">
        <h3 class="text-lg font-bold">{@title}</h3>
        <div :if={@actions != []} class="flex shrink-0 items-center gap-2">
          {render_slot(@actions)}
        </div>
      </div>
      <div class="text-gray-500">{render_slot(@inner_block)}</div>
    </div>
    """
  end

  defp put_form_name(attrs, %{owner_flow_id: nil}, %{} = _node, _name), do: attrs
  defp put_form_name(attrs, _form, _node, name), do: Map.put(attrs, :name, name)

  defp put_form_slug(attrs, nil, slug), do: Map.put(attrs, :slug, slug)
  defp put_form_slug(attrs, _node, _slug), do: attrs

  defp update_step(nil, _name, _slug), do: {:ok, nil}
  defp update_step(node, name, slug), do: Flows.update_node(node, %{label: name, slug: slug})

  defp shareable(%{owner_flow_id: nil} = form, properties, form_types) do
    form = %{form | properties: properties}
    values = Type.property_values(form)
    property = Type.related_form_property(form_types, form)

    if property && values[property.id] not in [nil, ""],
      do: {:error, {:related_form_shared, property}},
      else: :ok
  end

  defp shareable(_owned, _properties, _form_types), do: :ok

  defp presence(empty) when empty in [nil, ""], do: nil
  defp presence(value), do: value
end
