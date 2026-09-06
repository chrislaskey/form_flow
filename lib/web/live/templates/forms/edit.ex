defmodule FormFlow.Web.Templates.Forms.Edit do
  @moduledoc """
  `FormFlow.Web.Templates.Forms.Edit` LiveComponent edits one draft.

  Drafts only — published and archived definitions are immutable, and this
  page refuses to render them editable. The versioning chrome around the
  definition is the point: the optimistic-lock "changed under you" conflict,
  the stale-draft warning, and the picker between coexisting drafts.

  The definition is edited one of two ways, picked by the **Definition**
  radio (`definition_editor`): as **JSON** in a comment field, or in the
  **Form builder**, a `DynamicForm` nested form with one entry per element
  (`FormFlow.Web.Templates.Forms.Builder` converts between the two). Both sit
  in the one form under `visible_if`, so whichever is hidden keeps its
  content and stops being required. Content moves between them only when
  the radio changes — the `%{event: "change"}` clause decodes the JSON into
  entries, or writes the entries back into the JSON — never per keystroke.
  A definition the builder cannot show (a property it has no control for,
  JSON that does not parse) refuses the switch and says why, rather than
  dropping what it cannot show. The builder opens by default whenever it can
  show the saved definition.

  DynamicForm runs the validation lifecycle: `on_submit` is the definition
  gate (the JSON-syntax check in JSON mode, the entries written into the
  document in form mode; either way the definition map rides the payload's
  `extra`), and `on_success` routes the valid payload back to this
  LiveComponent through `send_update/2` — the `%{event: "save"}` clause of
  `update/2` performs the actual `update_draft/2`.

  Addressed like `FormFlow.Web.Templates.Forms.Show`, standalone
  (`/forms/:id/versions/:version_id/edit`) or by drill-in
  (`/flows/:root/nodes/:node_id/form/versions/:version_id/edit`).

  A draft that is blank and has never been published shows nothing but a
  choice, in place of the identity form: Custom form (an explicit no-op —
  the fields are already ready once chosen) or Copy form (pick another form
  and write its name, description, form type, and definition onto this one
  — never its slug, which already carries this form's own place). Selecting
  either is what reveals the rest of the page (`awaiting_start?`), and the
  chooser stops being offered on any later visit the moment either
  triggering fact changes — a save, a publish — so nothing tracks that a
  choice was made, beyond Custom form's own `?start=custom` (see
  `select_custom_path/1`; Copy needs no such marker, since writing the
  definition already makes the draft not blank).
  """

  use Phoenix.LiveComponent

  import FormFlow.Web.Helpers.Paths

  alias Phoenix.LiveView.JS

  alias FormFlow.Data.Templates.Flows
  alias FormFlow.Web.Components.Core
  alias FormFlow.Web.CoreComponents
  alias FormFlow.Web.Templates.Components.Breadcrumb
  alias FormFlow.Web.Templates.Shared
  alias FormFlow.Data.Templates.Forms
  alias FormFlow.Web.Templates.Forms.Builder
  alias FormFlow.Web.Templates.Forms.Preview
  alias FormFlow.Web.Templates.Forms.Components.PublishDialog

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       error: nil,
       notice: nil,
       editor_error: nil,
       preview_refresh_token: nil,
       scopes: ["elements", "children"],
       publishing?: false,
       auto_update?: true,
       preview_rev: 0,
       preview_topic: Ecto.UUID.generate(),
       chooser_selection: "custom",
       chooser_source_form_id: nil
     )}
  end

  @impl true
  def update(%{event: "publish", payload: payload}, socket) do
    preset = String.to_existing_atom(payload.data[:preset])

    case Forms.update_status(socket.assigns.version, :published, preset: preset) do
      {:ok, published} ->
        # Redirects are forbidden inside update/2; handle_async is the
        # component-owned callback where they are allowed
        to = version_show_path(socket.assigns, published)
        {:ok, start_async(socket, :navigate, fn -> to end)}

      {:error, :not_draft} ->
        {:ok, assign(socket, error: "Only drafts can be published.", publishing?: false)}

      {:error, _other} ->
        {:ok, assign(socket, error: "Could not publish. Please try again.", publishing?: false)}
    end
  end

  # The payload's content came from whichever editor was showing before this
  # change, so the definition — for dirtiness and the preview — is read by
  # that editor, and only then is a change of editor applied
  def update(%{event: "change", payload: payload}, socket) do
    {payload, moved?} = move_element(payload)
    pending_type = pending_type(payload, socket.assigns.pending_type)
    properties = Shared.properties(socket.assigns.form_types, pending_type)
    definition = current_definition(payload, socket.assigns.definition_editor)

    dirty? =
      values_from(payload.data, pending_type, properties, definition) !=
        socket.assigns.saved_values

    socket =
      socket
      |> assign(dirty?: dirty?, notice: nil, editor_error: nil, pending_type: pending_type)
      |> assign(:latest_json, definition_json(preview_definition(payload, socket, definition)))
      |> reset_form_data_on_move(moved?, payload)
      |> switch_editor(payload, definition)
      |> reset_form_data_on_switch(pending_type, payload)

    {:ok, schedule_preview_refresh(socket)}
  end

  # The debounced preview refresh, delivered by the timer schedule_preview_refresh/1
  # set. A stale token is a timer superseded by a later change, and is
  # dropped — the message can't be recalled once it is in the mailbox.
  def update(%{event: "refresh_preview", token: token}, socket) do
    if token == socket.assigns.preview_refresh_token do
      {:ok, socket |> assign(:preview_refresh_token, nil) |> force_refresh_preview()}
    else
      {:ok, socket}
    end
  end

  def update(%{event: "save", payload: payload}, socket) do
    type_id = presence(payload.data[:form_type])
    properties = Shared.properties(socket.assigns.form_types, type_id)

    identity = %{
      name: payload.data[:name],
      description: payload.data[:description],
      slug: payload.data[:slug],
      properties:
        template_properties(
          socket.assigns.form,
          type_id,
          Shared.payload_property_values(payload.data, properties)
        )
    }

    with {:ok, form} <- Forms.update(socket.assigns.form, identity),
         {:ok, version} <-
           Forms.update_draft(socket.assigns.version, %{definition: payload.extra[:definition]}) do
      {:ok,
       assign(socket,
         form: form,
         version: version,
         versions: Forms.list_versions(form.id),
         saved_values: values_from(payload.data, type_id, properties, payload.extra[:definition]),
         dirty?: false,
         error: nil,
         notice: "Saved."
       )}
    else
      {:error, :stale} ->
        {:ok,
         assign(socket,
           error:
             "This draft changed under you — someone else saved it. " <>
               "Reload to pick up their version.",
           notice: nil
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:ok,
         assign(socket,
           error: Shared.save_error(changeset, "Could not save. Please try again."),
           notice: nil
         )}
    end
  end

  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:base, fn -> "" end)
      |> assign_new(:form_id, fn -> nil end)
      |> assign_new(:version_id, fn -> nil end)
      |> assign_new(:root_id, fn -> nil end)
      |> assign_new(:node_id, fn -> nil end)
      |> assign_new(:flow_types, fn -> FormFlow.Config.Flows.Type.defaults() end)
      |> assign_new(:form_types, fn -> FormFlow.Config.Forms.Type.defaults() end)
      |> assign_new(:callback_data, fn -> %{} end)
      |> assign_new(:components, fn -> nil end)
      |> assign_new(:params, fn -> %{} end)

    {:ok, load(socket)}
  end

  defp load(socket) do
    assigns = socket.assigns
    node = assigns.node_id && Flows.get_node(assigns.node_id)
    form_id = assigns.form_id || (node && node.form_id)
    form = form_id && Forms.get(form_id)
    version = assigns.version_id && Forms.get_version(assigns.version_id)
    versions = if form, do: Forms.list_versions(form.id), else: []

    show_chooser? = show_chooser?(form, version)

    socket
    |> assign(
      form: form,
      node: node,
      version: version,
      versions: versions,
      based_on: based_on_version(versions, version),
      counts: form && Forms.instance_counts(form.id),
      form_types: form_types(assigns, form, version, node),
      pending_type: saved_type(form),
      show_chooser?: show_chooser?,
      awaiting_start?: awaiting_start?(show_chooser?, assigns.params),
      catalog_forms: catalog_forms(form)
    )
    |> assign_breadcrumb(node)
    |> assign_new(:definition_json, fn ->
      version && Phoenix.json_library().encode!(version.definition, pretty: true)
    end)
    # Kept across reloads once set, so a parent re-render leaves the admin's
    # choice alone; Copy clears it so it is derived again
    |> assign(:definition_editor, socket.assigns[:definition_editor] || initial_editor(version))
    |> then(fn socket ->
      socket
      |> assign(:saved_values, saved_values(form, version))
      |> assign(:form_data, form_data(form, socket.assigns))
      |> assign(:dirty?, false)
      # What the preview currently shows, and the editor's latest content —
      # both start at the saved definition; change events move latest_json,
      # and a refresh copies it over and bumps the rev
      |> assign_new(:preview_json, fn %{definition_json: json} -> json end)
      |> assign_new(:latest_json, fn %{definition_json: json} -> json end)
    end)
  end

  defp maybe_refresh_preview(%{assigns: %{auto_update?: true}} = socket),
    do: force_refresh_preview(socket)

  defp maybe_refresh_preview(socket), do: socket

  # Only the preview waits. Remounting or re-rendering it per keystroke would
  # be wasteful, so with auto-refresh on it follows 500ms of quiet — while
  # every other consequence of a change (the dirty flag, an editor switch, a
  # moved element) happens at once. Each change supersedes the pending
  # refresh, by token.
  defp schedule_preview_refresh(%{assigns: %{auto_update?: true}} = socket) do
    token = make_ref()

    Phoenix.LiveView.send_update_after(
      __MODULE__,
      %{id: socket.assigns.id, event: "refresh_preview", token: token},
      500
    )

    assign(socket, :preview_refresh_token, token)
  end

  defp schedule_preview_refresh(socket), do: socket

  defp force_refresh_preview(socket) do
    if FormFlow.app_config(:pubsub_server) do
      refresh_preview_by_pubsub(socket)
    else
      refresh_preview_by_re_render(socket)
    end
  end

  defp refresh_preview_by_pubsub(socket) do
    if socket.assigns.latest_json != socket.assigns.preview_json do
      pubsub_server = FormFlow.app_config(:pubsub_server)
      message = {:form_flow, :update_definition, socket.assigns.latest_json}

      Phoenix.PubSub.broadcast(pubsub_server, socket.assigns.preview_topic, message)

      # Track what was pushed so the guard above means "changed since the
      # last push", not "changed since page load" — otherwise editing back
      # to the exact saved text would skip the push and strand the preview
      # on the intermediate content. Also keeps the live_render session
      # fresh for any future remount.
      assign(socket, :preview_json, socket.assigns.latest_json)
    else
      socket
    end
  end

  # Re-rendering the preview means remounting it: a child LiveView never
  # re-reads its session, so the id carries the rev — a bump makes
  # live_render mount a fresh child with the new definition in its session
  defp refresh_preview_by_re_render(socket) do
    if socket.assigns.latest_json != socket.assigns.preview_json do
      socket
      |> assign(:preview_json, socket.assigns.latest_json)
      |> assign(:preview_rev, socket.assigns.preview_rev + 1)
    else
      socket
    end
  end

  # What the last save wrote, in the shape DynamicForm reports — the baseline
  # `dirty?` compares against, so the Save button can go primary exactly when
  # the form differs from what's persisted (matching the flows editor). The
  # definition is compared as the map that is persisted, the one shape both
  # editors produce — so re-indenting the JSON is not a change, and neither
  # is opening the builder.
  defp saved_values(nil, _version), do: nil

  defp saved_values(form, version) do
    %{
      name: to_string(form.name),
      description: to_string(form.description),
      slug: to_string(form.slug),
      form_type: to_string(form.properties["form_type"]),
      property_values: FormFlow.Config.Forms.Type.property_values(form),
      definition: version && version.definition
    }
  end

  defp values_from(payload_data, pending_type, properties, definition) do
    %{
      name: to_string(payload_data[:name] || ""),
      description: to_string(payload_data[:description] || ""),
      slug: to_string(payload_data[:slug] || ""),
      form_type: to_string(pending_type),
      property_values: Shared.payload_property_values(payload_data, properties),
      definition: definition
    }
  end

  # An element's up/down arrow sets its entry's `move` field and fires the
  # form's change, so the request arrives here with every other value as the
  # admin left it. The reordered entries replace the payload's, and become
  # the form's data — DynamicForm rebuilds from that, the same way an editor
  # switch or a form-type switch already does.
  defp move_element(payload) do
    case Builder.move(payload.data[:elements] || []) do
      {:moved, entries} -> {%{payload | data: Map.put(payload.data, :elements, entries)}, true}
      :none -> {payload, false}
    end
  end

  defp reset_form_data_on_move(socket, true, payload),
    do: assign(socket, :form_data, payload.data)

  defp reset_form_data_on_move(socket, false, _payload), do: socket

  # The definition a payload describes, read by the editor it came from. JSON
  # mode: the text, decoded when it parses so it compares to the saved map,
  # the raw text otherwise (which never compares equal, so bad JSON is dirty).
  # Form mode: the entries written into the document the JSON field still
  # holds — the builder edits `elements` and leaves every other key alone.
  defp current_definition(payload, "form") do
    Builder.definition(
      decoded_definition(payload.data[:definition]),
      payload.data[:elements] || []
    )
  end

  defp current_definition(payload, _json) do
    text = to_string(payload.data[:definition] || "")

    case Phoenix.json_library().decode(text) do
      {:ok, definition} when is_map(definition) -> definition
      _other -> text
    end
  end

  # What the preview shows: in form mode, the elements that are complete —
  # a row without a type or a name yet is not an element, and the preview
  # would otherwise fail on it with every keystroke of a new one
  defp preview_definition(payload, %{assigns: %{definition_editor: "form"}}, _definition) do
    Builder.definition(
      decoded_definition(payload.data[:definition]),
      Builder.complete_entries(payload.data[:elements] || [])
    )
  end

  defp preview_definition(_payload, _socket, definition), do: definition

  defp decoded_definition(text) do
    case Phoenix.json_library().decode(to_string(text || "")) do
      {:ok, definition} when is_map(definition) -> definition
      _other -> %{}
    end
  end

  defp definition_json(definition) when is_map(definition),
    do: Phoenix.json_library().encode!(definition, pretty: true)

  defp definition_json(text), do: to_string(text)

  # The builder opens by default when it can show the saved definition
  defp initial_editor(nil), do: "json"

  defp initial_editor(version) do
    if Builder.unsupported(version.definition) == [], do: "form", else: "json"
  end

  # The radio changed editor: move the content across by assigning new form
  # data (DynamicForm rebuilds from it, the way a form-type switch already
  # does), or refuse and snap the radio back. Refusing beats dropping: a
  # property the builder has no control for would be gone the moment the
  # admin switched back to JSON. `definition` is what the payload held, read
  # by the editor the admin is leaving.
  defp switch_editor(socket, payload, definition) do
    from = socket.assigns.definition_editor
    to = payload.data[:definition_editor]

    cond do
      to not in ["form", "json"] or to == from ->
        socket

      to == "json" ->
        form_data =
          payload.data
          |> Map.put(:definition_editor, "json")
          |> Map.put(:definition, definition_json(definition))
          # Entries stay validated while hidden, and a half-filled one left
          # behind would block Save with an error nobody could see
          |> Map.delete(:elements)

        assign(socket, definition_editor: "json", form_data: form_data)

      not is_map(definition) ->
        refuse_switch(
          socket,
          payload,
          "Fix the JSON syntax before switching to the form builder."
        )

      Builder.unsupported(definition) != [] ->
        refuse_switch(
          socket,
          payload,
          "The form builder can't show this definition, so it stays as JSON. " <>
            Enum.join(Builder.unsupported(definition), " ") <>
            " Remove those properties to edit it in the form builder."
        )

      true ->
        form_data =
          payload.data
          |> Map.put(:definition_editor, "form")
          |> Map.put(:elements, Builder.entries(definition))

        assign(socket, definition_editor: "form", form_data: form_data)
    end
  end

  defp refuse_switch(socket, payload, message) do
    form_data =
      payload.data
      |> Map.put(:definition_editor, "json")
      |> Map.delete(:elements)

    assign(socket, definition_editor: "json", form_data: form_data, editor_error: message)
  end

  # The raw param, not the applied changeset data: picking the prompt again
  # ("") must clear the pending type, and Ecto's cast treats "" as a missing
  # param rather than a change to nil — payload.data would keep the old value
  defp pending_type(%{changeset: %{params: %{"form_type" => value}}}, _current) do
    presence(value)
  end

  defp pending_type(_payload, current), do: current

  defp presence(empty) when empty in [nil, ""], do: nil
  defp presence(value), do: value

  # The one-time chooser: offered only for a draft that is both blank and
  # has never been published — nothing published means nothing at stake
  # (same test `FormFlow.Web.Templates.Forms.Show` uses to skip the
  # migration-policy dialog on a first publish), and a blank definition
  # means there is nothing here a copy would overwrite. Either fact turning
  # false — a save, a publish — is what makes the chooser stop being
  # offered; nothing tracks that a choice was made, because none is needed.
  defp show_chooser?(nil, _version), do: false
  defp show_chooser?(_form, nil), do: false

  defp show_chooser?(form, version),
    do: version.definition == %{} and not Forms.ever_published?(form.id)

  # Whether the page is still waiting on a choice: `show_chooser?/2` is the
  # data condition, `?start=custom` (`select_custom_path/1`) is Custom
  # form's own way of saying the choice was already made
  defp awaiting_start?(show_chooser?, params), do: show_chooser? and params["start"] != "custom"

  # The catalog forms this form could be copied from — every reusable form
  # but itself, computed only while the chooser is actually offered
  defp catalog_forms(nil), do: []

  defp catalog_forms(form) do
    Forms.list(tenant_id: form.tenant_id)
    |> Enum.reject(&(&1.id == form.id))
  end

  # The dropdown's own label — the slug alongside the name, the way an
  # admin looks a form up in code
  defp catalog_option_label(%{slug: nil} = source), do: source.name
  defp catalog_option_label(source), do: "#{source.name} · #{source.slug}"

  # The identity form's data: the saved values, with the saved type's property
  # values under their field names. Switching the type dropdown re-renders
  # the property fields, and DynamicForm rebuilds a form whose fields changed
  # from its data — so at that moment the data becomes the pending values
  # (reset_form_data_on_switch/3), and what the admin was typing survives.
  # Otherwise it holds still, which is what keeps in-progress input alive.
  defp saved_type(nil), do: nil
  defp saved_type(form), do: form.properties["form_type"]

  defp form_data(nil, _assigns), do: nil

  defp form_data(form, assigns) do
    type_id = form.properties["form_type"]
    values = FormFlow.Config.Forms.Type.property_values(form)

    %{
      name: form.name,
      description: form.description,
      slug: form.slug,
      form_type: type_id,
      definition: assigns.definition_json,
      definition_editor: assigns.definition_editor
    }
    |> Map.merge(Shared.field_data(Shared.properties(assigns.form_types, type_id), values))
    |> put_elements(assigns)
  end

  # The builder's entries, seeded from the saved definition when it opens in
  # the builder; absent in JSON mode, so nothing hidden is validated
  defp put_elements(form_data, %{definition_editor: "form", version: %{} = version}) do
    Map.put(form_data, :elements, Builder.entries(version.definition))
  end

  defp put_elements(form_data, _assigns), do: form_data

  defp reset_form_data_on_switch(socket, pending_type, payload) do
    if pending_type == socket.assigns.form_data[:form_type] do
      socket
    else
      %{form: form, form_types: types} = socket.assigns

      values =
        if pending_type == form.properties["form_type"],
          do: FormFlow.Config.Forms.Type.property_values(form),
          else: %{}

      form_data =
        payload.data
        |> Map.take([:name, :description, :slug, :definition, :definition_editor, :elements])
        |> Map.put(:form_type, pending_type)
        |> Map.merge(Shared.field_data(Shared.properties(types, pending_type), values))

      assign(socket, :form_data, form_data)
    end
  end

  # The form's stored `properties` map with the type applied — an unset type
  # removes the key and the property values with it, so "no choice" stays
  # "use the configured default" rather than pinning whatever the default
  # happened to be at save time. A type's property values are replaced whole,
  # so switching types leaves nothing of the old one behind — and a type with
  # nothing entered stores no values key at all.
  defp template_properties(form, nil, _values) do
    form.properties
    |> Map.delete("form_type")
    |> Map.delete("form_type_property_values")
  end

  defp template_properties(form, type_id, values) when values == %{} do
    form.properties
    |> Map.put("form_type", type_id)
    |> Map.delete("form_type_property_values")
  end

  defp template_properties(form, type_id, values) do
    form.properties
    |> Map.put("form_type", type_id)
    |> Map.put("form_type_property_values", values)
  end

  # The chooser's Copy: the source's name, description, form type and its
  # property values become *this* lineage's; the source's resolved
  # definition (latest published, else newest draft — the same fallback
  # `FormFlow.Web.Templates.Forms.Show` resolves a bare URL to) becomes
  # *this* draft's. Neither this form's id nor its slug moves — a property
  # value tied to this form's own place in the flow (a `related_form`
  # choice, say) would be meaningless copied from the source's; the existing
  # stale-choice handling (`FormFlow.Web.Templates.Shared.fill_related_forms/4`)
  # is what tells the admin to pick it again rather than silently keeping a
  # value that names a form here.
  defp copy_form_content(form, version, source_id) do
    with %{} = source <- Forms.get(source_id),
         %{} = source_version <- resolved_version(source.id),
         identity = %{
           name: source.name,
           description: source.description,
           properties:
             template_properties(
               form,
               source.properties["form_type"],
               FormFlow.Config.Forms.Type.property_values(source)
             )
         },
         {:ok, _form} <- Forms.update(form, identity),
         {:ok, _version} <- Forms.update_draft(version, %{definition: source_version.definition}) do
      {:ok, Phoenix.json_library().encode!(source_version.definition, pretty: true)}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, Shared.save_error(changeset, "Could not copy that form. Please try again.")}

      _other ->
        {:error, "Could not copy that form. Please try again."}
    end
  end

  defp resolved_version(form_id) do
    Forms.get_latest_version(form_id) || List.first(Forms.list_versions(form_id))
  end

  # The definition field's own copy, next to it: only the source's resolved
  # definition moves — name, slug, description, and form type are untouched.
  # Available any time, not gated by `show_chooser?/2`.
  defp copy_definition_content(version, source_id) do
    with %{} = source <- Forms.get(source_id),
         %{} = source_version <- resolved_version(source.id),
         {:ok, _version} <- Forms.update_draft(version, %{definition: source_version.definition}) do
      {:ok, Phoenix.json_library().encode!(source_version.definition, pretty: true)}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:error,
         Shared.save_error(changeset, "Could not copy that definition. Please try again.")}

      _other ->
        {:error, "Could not copy that definition. Please try again."}
    end
  end

  # The page's form types, with each related-form property's choices filled
  # in for this form's place in its flow. Empty means no dropdown.
  defp form_types(_assigns, nil, _version, _node), do: []

  defp form_types(assigns, form, _version, _node) do
    assigns.form_types
    |> Shared.fill_related_forms(
      assigns.root_id,
      assigns.node_id,
      FormFlow.Config.Forms.Type.property_values(form)
    )
  end

  @impl true
  def handle_async(:navigate, {:ok, to}, socket) do
    {:noreply, push_navigate(socket, to: to)}
  end

  @impl true
  def handle_event("open_publish", _params, socket) do
    if Forms.ever_published?(socket.assigns.form.id) do
      {:noreply, assign(socket, :publishing?, true)}
    else
      # Nothing has ever been published, so no instance can exist and no
      # migration policy is meaningful — publish directly, like Show does
      publish_directly(socket)
    end
  end

  @impl true
  def handle_event("cancel_publish", _params, socket) do
    {:noreply, assign(socket, :publishing?, false)}
  end

  @impl true
  def handle_event("toggle_auto_update", _params, socket) do
    socket = assign(socket, :auto_update?, !socket.assigns.auto_update?)

    # Turning it on catches the preview up to whatever was typed while off
    {:noreply, maybe_refresh_preview(socket)}
  end

  @impl true
  def handle_event("update_preview", _params, socket) do
    {:noreply, force_refresh_preview(socket)}
  end

  @impl true
  def handle_event("chooser_select", %{"selection" => selection}, socket) do
    {:noreply, assign(socket, :chooser_selection, selection)}
  end

  # Custom form changes nothing about the form or draft — there is no data
  # event that would make `show_chooser?/2` false on its own, unlike Copy.
  # `?start=custom` is what a reload of this exact page reads back to know the
  # choice was already made.
  @impl true
  def handle_event("select_custom", _params, socket) do
    {:noreply, push_navigate(socket, to: select_custom_path(socket.assigns))}
  end

  @impl true
  def handle_event("chooser_pick_source", %{"source_form_id" => source_form_id}, socket) do
    {:noreply, assign(socket, :chooser_source_form_id, presence(source_form_id))}
  end

  # The one-time copy: writes the source's identity (name, description, form
  # type and its property values) and its resolved definition onto *this*
  # lineage and draft — this form's own slug is never touched, since it
  # already carries this node's place in the flow (or its own, standalone).
  # Reloading afterwards is what makes the chooser stop offering itself: its
  # condition is the definition no longer being blank, nothing more to track.
  @impl true
  def handle_event("copy_form", _params, socket) do
    %{form: form, version: version, chooser_source_form_id: source_id} = socket.assigns

    case source_id && copy_form_content(form, version, source_id) do
      {:ok, json} ->
        {:noreply,
         socket
         |> assign(definition_json: json, latest_json: json, definition_editor: nil)
         |> load()
         |> force_refresh_preview()}

      {:error, message} ->
        {:noreply, assign(socket, :error, message)}

      nil ->
        {:noreply, socket}
    end
  end

  # Unlike Copy form, this is always available — it isn't gated by
  # `show_chooser?/2` — and it touches only the definition: no name, slug,
  # description, or form type moves. The source comes with the click: the
  # button reads it off the form's own dropdown.
  @impl true
  def handle_event("copy_definition", %{"source_form_id" => source_id}, socket) do
    %{version: version} = socket.assigns

    case presence(source_id) && copy_definition_content(version, source_id) do
      {:ok, json} ->
        {:noreply,
         socket
         |> assign(definition_json: json, latest_json: json, definition_editor: nil)
         |> load()
         |> force_refresh_preview()}

      {:error, message} ->
        {:noreply, assign(socket, :error, message)}

      nil ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("delete_draft", _params, socket) do
    case Forms.delete_draft(socket.assigns.version) do
      {:ok, _draft} ->
        # Back to the form's default view: latest published, or the newest
        # remaining draft, or the no-versions state
        {:noreply, push_navigate(socket, to: show_path(socket.assigns))}

      {:error, :has_instances} ->
        {:noreply, assign(socket, :error, "This draft can't be deleted: it has instances.")}

      {:error, _other} ->
        {:noreply, assign(socket, :error, "Only drafts can be deleted.")}
    end
  end

  defp publish_directly(socket) do
    case Forms.update_status(socket.assigns.version, :published) do
      {:ok, published} ->
        {:noreply, push_navigate(socket, to: version_show_path(socket.assigns, published))}

      {:error, :not_draft} ->
        {:noreply, assign(socket, :error, "Only drafts can be published.")}

      {:error, _other} ->
        {:noreply, assign(socket, :error, "Could not publish. Please try again.")}
    end
  end

  defp publish(payload, component_id) do
    Phoenix.LiveView.send_update(__MODULE__, %{
      id: component_id,
      event: "publish",
      payload: payload
    })
  end

  defp assign_breadcrumb(socket, nil), do: assign(socket, root: nil, parent_node: nil)

  defp assign_breadcrumb(socket, node) do
    root = Flows.get(socket.assigns.root_id)

    parent_node =
      if root && node.flow_id != root.id,
        do: Flows.embedding_node(node.flow_id, root.id)

    assign(socket, root: root, parent_node: parent_node)
  end

  # The definition gate, run by DynamicForm on every submit. In form mode the
  # entries are written into the document; in JSON mode a parse error renders
  # inline on the field like any built-in validation. Either way the
  # definition map rides the payload's extra into the "save" event above.
  defp validate_definition(%{data: %{definition_editor: "form"}} = payload) do
    payload =
      DynamicForm.Payload.put_extra(payload, :definition, current_definition(payload, "form"))

    # Siblings repeating a name are caught by each nested form's key; a group
    # member repeating a name outside its group is caught here
    case Builder.duplicate_names(payload.data[:elements] || []) do
      [] ->
        payload

      names ->
        DynamicForm.Payload.add_error(
          payload,
          :elements,
          "uses the same name more than once: #{Enum.join(names, ", ")}"
        )
    end
  end

  defp validate_definition(payload), do: validate_json(payload)

  defp validate_json(payload) do
    case Phoenix.json_library().decode(payload.data[:definition] || "") do
      {:ok, definition} when is_map(definition) ->
        DynamicForm.Payload.put_extra(payload, :definition, definition)

      _other ->
        DynamicForm.Payload.add_error(
          payload,
          :definition,
          "is not valid JSON — fix the syntax and save again"
        )
    end
  end

  defp saved(payload, component_id) do
    Phoenix.LiveView.send_update(__MODULE__, %{
      id: component_id,
      event: "save",
      payload: payload
    })
  end

  # DynamicForm's on_change hook, abused gently: no extra validation, just a
  # report of the current values so dirtiness can drive the Save button
  defp changed(payload, component_id) do
    Phoenix.LiveView.send_update(__MODULE__, %{
      id: component_id,
      event: "change",
      payload: payload
    })

    payload
  end

  @impl true
  def render(%{form: nil} = assigns) do
    ~H"""
    <div>
      <Core.alert components={@components}>
        <span>Form not found.</span>
        <.link navigate={"#{@base}/forms"} class="link link-primary">Back to forms</.link>
      </Core.alert>
    </div>
    """
  end

  def render(%{version: version} = assigns) when version == nil or version.status != "draft" do
    ~H"""
    <div>
      <Core.alert components={@components}>
        <span>Only drafts can be edited.</span>
        <.link navigate={show_path(assigns)} class="link link-primary">Back to the form</.link>
      </Core.alert>
    </div>
    """
  end

  # Nothing else on the page until a choice is made: the identity form, the
  # definition, the header's Save/Publish — none of them mean anything yet.
  # Custom form's Select has to leave a mark server-side or reloading this
  # exact page would show the chooser again forever (the data itself never
  # changes for it, unlike Copy) — a query param is the only channel that
  # survives `push_navigate`'s full remount (see `select_custom_path/1`).
  def render(%{awaiting_start?: true} = assigns) do
    ~H"""
    <div>
      <div class="mb-2 h-14 flex items-center">
        <Breadcrumb.breadcrumb
          base={@base}
          section="forms"
          root={@root}
          parent_node={@parent_node}
          mode={@params["mode"]}
          components={@components}
        >
          <.link navigate={show_path(assigns)} class="hover:underline">{@form.name}</.link>
          <span class="ml-1 text-xs font-normal text-zinc-500">draft</span>
        </Breadcrumb.breadcrumb>
      </div>

      <Core.error :if={@error} components={@components}>{@error}</Core.error>

      <div class="rounded-md border border-zinc-200 p-4">
        <fieldset class="flex flex-wrap items-center gap-4 text-sm">
          <legend class="mb-2 text-xs font-medium text-zinc-600">Start this form from</legend>
          <label class="flex items-center gap-2">
            <input
              type="radio"
              name="chooser_selection"
              value="custom"
              checked={@chooser_selection == "custom"}
              phx-click="chooser_select"
              phx-value-selection="custom"
              phx-target={@myself}
            /> Custom form
          </label>
          <label class="flex items-center gap-2">
            <input
              type="radio"
              name="chooser_selection"
              value="copy"
              checked={@chooser_selection == "copy"}
              phx-click="chooser_select"
              phx-value-selection="copy"
              phx-target={@myself}
            /> Copy form
          </label>
        </fieldset>

        <div :if={@chooser_selection == "custom"} class="mt-3">
          <Core.button
            components={@components}
            phx-click="select_custom"
            phx-target={@myself}
            variant="primary"
          >
            Select
          </Core.button>
        </div>

        <div :if={@chooser_selection == "copy"} class="mt-3 flex items-center gap-2">
          <form id={"#{@id}-chooser-copy"} phx-change="chooser_pick_source" phx-target={@myself}>
            <select name="source_form_id" class="w-full max-w-xs select">
              <option value="">Choose a form…</option>
              <option
                :for={source <- @catalog_forms}
                value={source.id}
                selected={source.id == @chooser_source_form_id}
              >
                {catalog_option_label(source)}
              </option>
            </select>
          </form>
          <Core.button
            components={@components}
            phx-click="copy_form"
            phx-target={@myself}
            disabled={is_nil(@chooser_source_form_id)}
            variant="primary"
          >
            Select
          </Core.button>
        </div>
      </div>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div>
      <div class="mb-2 h-14 flex items-center justify-between gap-4">
        <Breadcrumb.breadcrumb
          base={@base}
          section="forms"
          root={@root}
          parent_node={@parent_node}
          mode={@params["mode"]}
          components={@components}
        >
          <.link navigate={show_path(assigns)} class="hover:underline">{@form.name}</.link>
          <span class="ml-1 text-xs font-normal text-zinc-500">draft</span>
        </Breadcrumb.breadcrumb>
        <div class="flex items-center gap-2">
          <Core.button
            :if={length(@versions) > 1}
            components={@components}
            phx-click="delete_draft"
            phx-target={@myself}
            data-confirm="Delete this draft? Its unpublished changes are gone for good; published versions are untouched."
            class="btn btn-error btn-soft"
          >
            Delete draft
          </Core.button>
          <%!-- The remote submit: an HTML form= reference into the
                DynamicForm below, so Save draft lives in the header like
                every other page's primary action, and says "draft" because
                Publish sits right beside it. Styled like the flows editor's
                Save — quiet until changes exist, primary once they do. --%>
          <Core.button
            components={@components}
            form={"#{@id}-form-form"}
            class={[
              "btn phx-submit-loading:opacity-75",
              if(@dirty?, do: "btn-primary", else: "btn-primary btn-soft")
            ]}
          >
            Save draft
          </Core.button>
          <Core.button
            components={@components}
            phx-click="open_publish"
            phx-target={@myself}
            variant="primary"
          >
            Publish
          </Core.button>
        </div>
      </div>

      <Core.error :if={@error} components={@components}>{@error}</Core.error>
      <Core.alert :if={@notice} kind={:success} components={@components} class="my-3">
        {@notice}
      </Core.alert>
      <Core.alert :if={@editor_error} kind={:warning} components={@components} class="my-3">
        {@editor_error}
      </Core.alert>

      <Core.alert :if={Forms.stale_draft?(@version)} kind={:warning} components={@components} class="mb-3">
        This draft was based on a version that is no longer the latest — review before publishing.
      </Core.alert>

      <%!-- One form, one Save: the lineage's identity (name, description)
        above the version's definition, separated by a read-only strip
        saying which draft is being edited. The save event writes each
        value to its owner — identity to the form row, definition to the
        draft. Picking a different draft belongs on Show, where the
        version history lists them all.

        Two parts, one form: the identity fields run the full width, then
        the version — the draft strip and the definition editors, collected
        in the "version" group — shares a row with the preview. The
        component's root and its <form> are display: contents, so the
        field wrappers and the group are the flex items themselves: a field
        wrapper (the library's div.mb-4) takes a full line, and the group
        (the one child without that class) and the preview split the last,
        side by side from lg up and stacked below. --%>
      <div class={[
        "flex flex-wrap gap-x-6",
        "[&>:first-child]:contents [&>:first-child>form]:contents",
        "[&_form>.mb-4]:basis-full",
        "[&_form>div:not(.mb-4)]:min-w-0 [&_form>div:not(.mb-4)]:basis-full",
        "lg:[&_form>div:not(.mb-4)]:grow lg:[&_form>div:not(.mb-4)]:basis-0"
      ]}>
          <DynamicForm.form
            id={"#{@id}-form"}
            data={@form_data}
            hide_submit
            on_change={&changed(&1, @id)}
            on_submit={&validate_definition/1}
            on_success={&saved(&1, @id)}
            components={@components || CoreComponents}
          >
        <:field type="text" name="name" label="Name" required />
        <:field
          type="text"
          name="slug"
          label="Slug"
          description="A stable name for looking this form up in code — lowercase letters, numbers, _ and -. It does not follow a rename."
        />
        <:field type="comment" name="description" label="Description" />
        <:field
          :if={@form_types != []}
          type="dropdown"
          name="form_type"
          label="Form type"
          options={Enum.map(@form_types, &{&1.name, &1.id})}
        />
        <%!-- The pending type's properties (FormFlow.Config.Property), one
              field each; picking another type swaps them --%>
        <:field
          :for={property <- Shared.properties(@form_types, @pending_type)}
          type={Shared.field_type(property)}
          input_type={Shared.input_type(property)}
          name={Shared.field_name(property)}
          label={property.name}
          description={property.description}
          options={Shared.field_options(property)}
          required={property.required}
          read_only={Shared.read_only?(property)}
          default={property.default_value}
        />
        <:group name="version" type="vertical" title={false} />
        <:field group="version" type="html" name="draft_info">
          <div class="rounded-md border border-zinc-200 bg-zinc-50 px-3 py-2 text-xs text-zinc-600">
            Editing <span class="font-medium">draft</span>,
            last updated {Calendar.strftime(@version.updated_at, "%Y-%m-%d %H:%M")}<span :if={@based_on}>, based on
              <.link
                href={version_show_path(assigns, @based_on)}
                target="_blank"
                class="inline-flex items-baseline gap-0.5 border-b border-transparent text-blue-600 hover:border-blue-600"
              >
                v{@based_on.version}<svg
                  xmlns="http://www.w3.org/2000/svg"
                  viewBox="0 0 20 20"
                  fill="currentColor"
                  class="size-3 self-center"
                  aria-hidden="true"
                ><path
                    fill-rule="evenodd"
                    d="M4.25 5.5a.75.75 0 0 0-.75.75v8.5c0 .414.336.75.75.75h8.5a.75.75 0 0 0 .75-.75v-4a.75.75 0 0 1 1.5 0v4A2.25 2.25 0 0 1 12.75 17h-8.5A2.25 2.25 0 0 1 2 14.75v-8.5A2.25 2.25 0 0 1 4.25 4h5a.75.75 0 0 1 0 1.5h-5Z"
                    clip-rule="evenodd"
                  /><path
                    fill-rule="evenodd"
                    d="M6.194 12.753a.75.75 0 0 0 1.06.053L16.5 4.44v2.81a.75.75 0 0 0 1.5 0v-4.5a.75.75 0 0 0-.75-.75h-4.5a.75.75 0 0 0 0 1.5h2.553l-9.056 8.194a.75.75 0 0 0-.053 1.06Z"
                    clip-rule="evenodd"
                  /></svg>
              </.link></span>.
            <.link
              :if={other_draft_count(@versions, @version) > 0}
              navigate={show_path(assigns)}
              class="text-cyan-600 hover:underline"
            >
              {other_draft_count(@versions, @version)} other draft(s) exist — see all versions
            </.link>
          </div>
        </:field>
        <%!-- Two editors for one definition, under one radio. Each hides
              with visible_if — hidden, it keeps its content and stops being
              required — and content crosses between them only when the
              radio changes (switch_editor/3). --%>
        <:field
          group="version"
          type="radiogroup"
          name="definition_editor"
          label="Definition"
          options={[{"Form builder", "form"}, {"JSON", "json"}]}
          metadata={%{"style" => "horizontal"}}
        />
        <:field
          group="version"
          type="comment"
          name="definition"
          label="Definition (JSON)"
          required
          visible_if="{definition_editor} = 'json'"
        />
        <%!-- Copy definition belongs to the JSON editor: it writes JSON, and
              the builder is re-seeded from the saved draft anyway. Fields of
              this form rather than a form of their own, so they sit in the
              version group; the button reads the picked source off the form.
              A dropdown needs options, so neither renders with no catalog. --%>
        <:field
          :if={@catalog_forms != []}
          group="version"
          type="dropdown"
          name="definition_copy_source"
          label="Copy definition from existing form"
          options={Enum.map(@catalog_forms, &{catalog_option_label(&1), &1.id})}
          visible_if="{definition_editor} = 'json'"
        />
        <:field
          :let={form}
          :if={@catalog_forms != []}
          group="version"
          type="custom"
          name="definition_copy"
          visible_if="{definition_editor} = 'json'"
        >
          <Core.button
            components={@components}
            phx-click="copy_definition"
            phx-target={@myself}
            phx-value-source_form_id={form[:definition_copy_source].value}
            disabled={is_nil(presence(form[:definition_copy_source].value))}
          >
            Copy definition
          </Core.button>
        </:field>
        <%!-- The form builder: one entry per element, its fields named after
              the SurveyJS properties they set. Which fields show for a type,
              and which the entry writes back, come from one table in
              Builder — a hidden field keeps its held value, and that value
              must not reach the JSON.

              Two scopes render the same field list (element_fields/1): the
              form's elements, and the members of a group or nested form
              ("children", a nested form inside each entry). A container's
              members render after its own properties because the children
              declaration takes the position of its first member field, and
              every children-scope field is declared after the last
              elements-scope one. --%>
        <:nested
          name="elements"
          group="version"
          title="Elements"
          description="The form's questions and content blocks, in order. An element's name is the key its answer is stored under."
          entry_title="Element {panelIndex}"
          add_text="Add element"
          remove_text="Remove element"
          no_entries_text="No elements yet — add one to start building the form."
          key="name"
          key_error="is already used by another element"
          generate_ids={false}
          visible_if="{definition_editor} = 'form'"
        />
        <:nested
          name="children"
          nested="elements"
          title="Elements inside"
          description="The questions and content this group or nested form holds, in order."
          entry_title="Element {panelIndex}"
          add_text="Add element inside"
          remove_text="Remove element"
          no_entries_text="Nothing inside yet."
          key="name"
          key_error="is already used by another element"
          generate_ids={false}
          visible_if={Builder.visible_if("children")}
        />
        <:group
          :for={scope <- @scopes}
          name={"#{scope}_type_and_name"}
          nested={scope}
          type="horizontal"
        />
        <:group
          :for={{scope, group} <- for(scope <- @scopes, group <- element_groups(), do: {scope, group})}
          name={"#{scope}_#{group.name}"}
          nested={scope}
          type="horizontal"
          visible_if={Builder.visible_if(group.visible_if)}
        />
        <%!-- Up and down: the arrows write "up"/"down" into this hidden field
              and fire the form's change, so the move travels with the rest
              of the form's values (Builder.move/1, move_element/1). The
              library's entries are otherwise positional, with no reorder of
              their own. --%>
        <:field
          :let={field}
          nested="elements"
          group="elements_type_and_name"
          type="text"
          name="move"
          label={false}
        >
          <.move_arrows field={field} />
        </:field>
        <:field
          :for={field <- element_fields("elements")}
          nested="elements"
          group={field[:group] && "elements_#{field.group}"}
          type={field.type}
          input_type={field[:input_type]}
          name={field.name}
          label={field.label}
          options={field[:options]}
          placeholder={field[:placeholder]}
          description={field[:description]}
          pattern={field[:pattern]}
          required={field[:required]}
          visible_if={field[:visible_if]}
          required_if={field[:required_for_type] && field[:visible_if]}
        />
        <:field
          :let={field}
          nested="children"
          group="children_type_and_name"
          type="text"
          name="move"
          label={false}
        >
          <.move_arrows field={field} />
        </:field>
        <:field
          :for={field <- element_fields("children")}
          nested="children"
          group={field[:group] && "children_#{field.group}"}
          type={field.type}
          input_type={field[:input_type]}
          name={field.name}
          label={field.label}
          options={field[:options]}
          placeholder={field[:placeholder]}
          description={field[:description]}
          pattern={field[:pattern]}
          required={field[:required]}
          visible_if={field[:visible_if]}
          required_if={field[:required_for_type] && field[:visible_if]}
        />
          </DynamicForm.form>

        <%!-- Sticky beside a long editor: the preview stays in view while
              the admin scrolls the fields, and scrolls on its own when it is
              the taller of the two. Only once the columns sit side by side —
              stacked, sticky would pin it over the editor. --%>
        <div class="min-w-0 basis-full lg:grow lg:basis-0 lg:sticky lg:top-4 lg:self-start lg:max-h-[calc(100vh-2rem)] lg:overflow-y-auto">
          <div class="mb-1 flex items-center justify-between gap-2">
            <h3 class="text-xs font-medium text-zinc-500">Preview</h3>
            <div class="flex items-center gap-2">
              <button
                type="button"
                phx-click="toggle_auto_update"
                phx-target={@myself}
                role="switch"
                aria-checked={to_string(@auto_update?)}
                aria-label="Toggle auto-update preview"
                class="flex items-center gap-1.5 text-xs"
              >
                <span class={
                  if(@auto_update?, do: "font-semibold text-zinc-900", else: "text-zinc-500")
                }>
                  Auto-refresh
                </span>
                <span class={[
                  "relative inline-flex h-6 w-11 shrink-0 items-center rounded-full transition-colors",
                  if(@auto_update?, do: "bg-cyan-600", else: "bg-zinc-300")
                ]}>
                  <span class={[
                    "inline-block h-5 w-5 rounded-full bg-white shadow transition-transform",
                    if(@auto_update?, do: "translate-x-5", else: "translate-x-0.5")
                  ]} />
                </span>
              </button>
              <Core.button
                :if={!@auto_update?}
                components={@components}
                phx-click="update_preview"
                phx-target={@myself}
                class="btn"
              >
                Refresh
              </Core.button>
            </div>
          </div>
          <div class="rounded-md border border-zinc-200 p-4">
            {live_render(@socket, Preview,
              id: preview_id(assigns),
              session: %{"id" => preview_id(assigns), "definition" => @preview_json, "pubsub_topic" => @preview_topic}
            )}
          </div>
        </div>
      </div>

      <PublishDialog.publish_dialog
        :if={@publishing?}
        id={"#{@id}-publish-form"}
        counts={@counts}
        target={@myself}
        on_success={&publish(&1, @id)}
        components={@components}
        saved_note
      />
    </div>
    """
  end

  defp preview_id(assigns), do: "#{assigns.id}-preview-r#{assigns.preview_rev}"

  # One entry's fields, in render order, for a scope: the form's elements or
  # the members inside a container. Type and Name come first, then each
  # editable property in Builder.properties/0 with its control. A field shows
  # only for the types its property applies to, and `required_for_type`
  # makes it required for those same types. Inside a container no container
  # can be picked, so its fields are left out there.
  defp element_fields(scope) do
    inside? = scope != "elements"

    [
      %{
        name: "type",
        type: "dropdown",
        label: "Type",
        options: Builder.type_options(scope),
        required: true,
        group: "type_and_name"
      },
      %{
        name: "name",
        type: "text",
        label: "Name",
        description: "Letters, numbers, _ and -.",
        pattern: "^[A-Za-z0-9_-]+$",
        required: true,
        group: "type_and_name"
      },
      %{name: "title", type: "text", label: "Label"},
      %{
        name: "groupType",
        type: "dropdown",
        label: "Layout",
        options: [{"Members side by side", "horizontal"}, {"Members stacked", "vertical"}],
        container: true
      },
      %{
        name: "inputType",
        type: "dropdown",
        label: "Input type",
        options: Builder.input_type_options()
      },
      %{
        name: "choices",
        type: "comment",
        label: "Choices",
        description:
          "One per line. Write value | Label to store a value different from the label shown.",
        required_for_type: true
      },
      %{name: "rateMin", type: "text", input_type: "number", label: "Minimum", group: "rating"},
      %{name: "rateMax", type: "text", input_type: "number", label: "Maximum", group: "rating"},
      %{name: "rateStep", type: "text", input_type: "number", label: "Step", group: "rating"},
      %{
        name: "templateTitle",
        type: "text",
        label: "Entry title",
        description: "{panelIndex} stands for the entry's number, counting from 1.",
        container: true
      },
      %{
        name: "minPanelCount",
        type: "text",
        input_type: "number",
        label: "Fewest entries",
        group: "entry_count",
        container: true
      },
      %{
        name: "maxPanelCount",
        type: "text",
        input_type: "number",
        label: "Most entries",
        group: "entry_count",
        container: true
      },
      %{name: "addPanelText", type: "text", label: "Add button text", container: true},
      %{name: "html", type: "comment", label: "HTML", required_for_type: true},
      %{name: "placeholder", type: "text", label: "Placeholder"},
      %{name: "description", type: "text", label: "Help text"},
      %{name: "defaultValue", type: "text", label: "Default value"},
      %{name: "isRequired", type: "boolean", label: "Required"},
      %{
        name: "visibleIf",
        type: "text",
        label: "Visible if",
        placeholder: "{other_element} = 'value'",
        description:
          "A SurveyJS expression over the other elements' names — {subject} = 'support', or {email} notempty. Leave blank to always show it."
      }
    ]
    |> Enum.reject(&(inside? and &1[:container]))
    |> Enum.map(fn field ->
      if Map.has_key?(Builder.properties(), field.name),
        do: Map.put(field, :visible_if, Builder.visible_if(field.name)),
        else: field
    end)
  end

  # The rows of related number fields, shown for the types of their first
  # member. Type and Name share a row too, declared on its own since it has
  # no visible_if.
  defp element_groups do
    [
      %{name: "rating", visible_if: "rateMin"},
      %{name: "entry_count", visible_if: "minPanelCount"}
    ]
  end

  # Set the entry's hidden `move` field, fire the form's change from it, and
  # clear it again — entirely on the client, no event of its own to handle.
  # The form is serialized as the event fires, so the request is in that one
  # change and no other. Clearing it here matters: the server renders the
  # field's value as "" every time, so a value set on the client is never
  # patched away, and a request left in the DOM would ride every later
  # change too — swapping the elements back and forth on each keystroke.
  defp move_element_js(field, direction) do
    JS.set_attribute({"value", direction}, to: "##{field.id}")
    |> JS.dispatch("input", to: "##{field.id}")
    |> JS.set_attribute({"value", ""}, to: "##{field.id}")
  end

  defp move_arrows(assigns) do
    ~H"""
    <input type="hidden" id={@field.id} name={@field.name} value="" />
    <div class="flex flex-col">
      <button
        type="button"
        class="btn btn-xs btn-ghost px-1"
        aria-label="Move up"
        title="Move up"
        disabled={@field.form.index == 0}
        phx-click={move_element_js(@field, "up")}
      >
        ↑
      </button>
      <button
        type="button"
        class="btn btn-xs btn-ghost px-1"
        aria-label="Move down"
        title="Move down"
        disabled={@field.form.index + 1 >= entry_count(@field)}
        phx-click={move_element_js(@field, "down")}
      >
        ↓
      </button>
    </div>
    """
  end

  # How many entries sit beside this one: the form's elements, or the
  # members of the container the entry's form name places it in
  defp entry_count(field) do
    elements = DynamicForm.form_data(field)[:elements] || []

    case Regex.run(~r/\[elements\]\[(\d+)\]\[children\]/, field.form.name) do
      [_match, index] ->
        elements |> Enum.at(String.to_integer(index), %{}) |> Map.get(:children, []) |> length()

      nil ->
        length(elements)
    end
  end

  defp based_on_version(versions, %{based_on_version_id: base_id}) when is_binary(base_id) do
    Enum.find(versions, &(&1.id == base_id))
  end

  defp based_on_version(_versions, _version), do: nil

  defp other_draft_count(versions, version) do
    Enum.count(versions, &(&1.status == "draft" and &1.id != version.id))
  end

  defp form_base_path(%{node: nil} = assigns), do: "#{assigns.base}/forms/#{assigns.form.id}"

  defp form_base_path(assigns) do
    "#{assigns.base}/flows/#{assigns.root_id}/nodes/#{assigns.node_id}/form"
  end

  defp show_path(assigns) do
    preserve_query_params(form_base_path(assigns), assigns.params, ["mode"])
  end

  defp version_show_path(assigns, version) do
    preserve_query_params(
      "#{form_base_path(assigns)}/versions/#{version.id}",
      assigns.params,
      ["mode"]
    )
  end

  # This same edit page, with `start=custom` added — `mode` carries forward
  # if it was already there. Reloading is what makes Custom form's choice
  # stick, since nothing about the form or draft changed to make
  # `show_chooser?/2` false on its own.
  defp select_custom_path(assigns) do
    query = assigns.params |> Map.take(["mode"]) |> Map.put("start", "custom")
    "#{form_base_path(assigns)}/versions/#{assigns.version.id}/edit?#{URI.encode_query(query)}"
  end
end
