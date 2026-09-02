defmodule FormFlow.Web.Templates.Forms.Edit do
  @moduledoc """
  `FormFlow.Web.Templates.Forms.Edit` LiveComponent edits one draft.

  Drafts only — published and archived definitions are immutable, and this
  page refuses to render them editable. The definition editor starts minimal
  (the JSON, in a `DynamicForm.form` comment field); the versioning chrome
  around it is the point: the optimistic-lock "changed under you" conflict,
  the stale-draft warning, and the picker between coexisting drafts.

  DynamicForm runs the validation lifecycle: `on_submit` is the JSON-syntax
  gate (parse errors render inline on the field, the parsed map rides the
  payload's `extra`), and `on_success` routes the valid payload back to this
  LiveComponent through `send_update/2` — the `%{event: "save"}` clause of
  `update/2` performs the actual `update_draft/2`.

  Addressed like `FormFlow.Web.Templates.Forms.Show`, standalone
  (`/forms/:id/versions/:version_id/edit`) or by drill-in
  (`/flows/:root/nodes/:node_id/form/versions/:version_id/edit`).
  """

  use Phoenix.LiveComponent

  import FormFlow.Web.Helpers.Paths

  alias FormFlow.Context
  alias FormFlow.Data.Templates.Flows
  alias FormFlow.Web.Templates.Shared
  alias FormFlow.Data.Templates.Forms
  alias FormFlow.Web.Templates.Forms.Preview
  alias FormFlow.Web.Templates.Forms.Components.PublishDialog

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       error: nil,
       notice: nil,
       publishing?: false,
       auto_update?: false,
       preview_rev: 0,
       preview_topic: Ecto.UUID.generate()
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

  def update(%{event: "change", payload: payload}, socket) do
    pending_type = pending_type(payload, socket.assigns.pending_type)
    properties = Shared.properties(socket.assigns.form_types, pending_type)
    dirty? = values_from(payload.data, pending_type, properties) != socket.assigns.saved_values

    socket =
      socket
      |> assign(dirty?: dirty?, notice: nil, pending_type: pending_type)
      |> assign(:latest_json, to_string(payload.data[:definition] || ""))
      |> reset_form_data_on_switch(pending_type, payload)

    {:ok, maybe_refresh_preview(socket)}
  end

  def update(%{event: "save", payload: payload}, socket) do
    type_id = presence(payload.data[:form_type])
    properties = Shared.properties(socket.assigns.form_types, type_id)

    identity = %{
      name: payload.data[:name],
      description: payload.data[:description],
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
         saved_values: values_from(payload.data, type_id, properties),
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

      {:error, %Ecto.Changeset{}} ->
        {:ok,
         assign(socket,
           error: "Could not save. Please try again.",
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
      |> assign_new(:config, fn -> nil end)
      |> assign_new(:config_data, fn -> %{} end)

    {:ok, load(socket)}
  end

  defp load(socket) do
    assigns = socket.assigns
    node = assigns.node_id && Flows.get_node(assigns.node_id)
    form_id = assigns.form_id || (node && node.form_id)
    form = form_id && Forms.get(form_id)
    version = assigns.version_id && Forms.get_version(assigns.version_id)
    versions = if form, do: Forms.list_versions(form.id), else: []

    socket
    |> assign(
      form: form,
      node: node,
      version: version,
      versions: versions,
      based_on: based_on_version(versions, version),
      counts: form && Forms.instance_counts(form.id),
      form_types: form_types(assigns, form, version, node),
      pending_type: saved_type(form)
    )
    |> assign_breadcrumb(node)
    |> assign_new(:definition_json, fn ->
      version && Phoenix.json_library().encode!(version.definition, pretty: true)
    end)
    |> then(fn socket ->
      socket
      |> assign(:saved_values, saved_values(form, socket.assigns.definition_json))
      |> assign(:form_data, form_data(form, socket.assigns))
      |> assign(:dirty?, false)
      # What the preview currently shows, and the editor's latest content —
      # both start at the saved definition; change events move latest_json,
      # and a refresh copies it over and bumps the rev
      |> assign_new(:preview_json, fn %{definition_json: json} -> json end)
      |> assign_new(:latest_json, fn %{definition_json: json} -> json end)
    end)
  end

  defp maybe_refresh_preview(%{assigns: %{auto_update?: true}} = socket) do
    if FormFlow.app_config(:pubsub_server) do
      refresh_preview_by_pubsub(socket)
    else
      refresh_preview_by_re_render(socket)
    end
  end

  defp maybe_refresh_preview(socket), do: socket

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
  # the form differs from what's persisted (matching the flows editor)
  defp saved_values(nil, _definition_json), do: nil

  defp saved_values(form, definition_json) do
    %{
      name: to_string(form.name),
      description: to_string(form.description),
      form_type: to_string(form.properties["form_type"]),
      property_values: FormFlow.Config.Forms.Type.property_values(form),
      definition: to_string(definition_json)
    }
  end

  defp values_from(payload_data, pending_type, properties) do
    %{
      name: to_string(payload_data[:name] || ""),
      description: to_string(payload_data[:description] || ""),
      form_type: to_string(pending_type),
      property_values: Shared.payload_property_values(payload_data, properties),
      definition: to_string(payload_data[:definition] || "")
    }
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
      form_type: type_id,
      definition: assigns.definition_json
    }
    |> Map.merge(Shared.field_data(Shared.properties(assigns.form_types, type_id), values))
  end

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
        |> Map.take([:name, :description, :definition])
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

  # What the config offers for this form — see FormFlow.Config. Empty means
  # no dropdown; the library enables no form types of its own.
  defp form_types(_assigns, nil, _version, _node), do: []

  defp form_types(assigns, form, version, node) do
    config = FormFlow.Config.config_module(assigns.config)
    context = %Context{form: form, form_version: version, subflow_node: node}

    context
    |> config.enabled_form_types(assigns.config_data)
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
    if FormFlow.app_config(:pubsub_server) do
      {:noreply, refresh_preview_by_pubsub(socket)}
    else
      {:noreply, refresh_preview_by_re_render(socket)}
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

  # The JSON-syntax gate, run by DynamicForm on every submit: a parse error
  # renders inline on the field like any built-in validation, and a parsed
  # definition rides the payload's extra into the "save" event above
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
      <p class="text-sm text-zinc-500">
        Form not found.
        <.link navigate={"#{@base}/forms"} class="underline">Back to forms</.link>
      </p>
    </div>
    """
  end

  def render(%{version: version} = assigns) when version == nil or version.status != "draft" do
    ~H"""
    <div>
      <p class="text-sm text-zinc-500">
        Only drafts can be edited.
        <.link navigate={show_path(assigns)} class="underline">Back to the form</.link>
      </p>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div>
      <div class="mb-2 h-14 flex items-center justify-between gap-4">
        <div class="text-sm font-semibold">
          <.link navigate={templates_path(@base)} class="hover:underline">Templates</.link>
          <span class="text-zinc-400">/</span>
          <%= if @node do %>
            <.link navigate={"#{@base}/flows"} class="hover:underline">Flows</.link>
            <span class="text-zinc-400">/</span>
            <.link :if={@root} navigate={"#{@base}/flows/#{@root.id}"} class="hover:underline">
              {@root.name || "Untitled"}
            </.link>
            <span :if={@root} class="text-zinc-400">/</span>
            <.link
              :if={@parent_node}
              navigate={"#{@base}/flows/#{@root.id}/nodes/#{@parent_node.id}"}
              class="hover:underline"
            >
              {get_in(@parent_node.properties, ["data", "label"]) || "Subflow"}
            </.link>
            <span :if={@parent_node} class="text-zinc-400">/</span>
          <% else %>
            <.link navigate={"#{@base}/forms"} class="hover:underline">Forms</.link>
            <span class="text-zinc-400">/</span>
          <% end %>
          <.link navigate={show_path(assigns)} class="hover:underline">{@form.name}</.link>
          <span class="ml-1 text-xs font-normal text-zinc-500">draft</span>
        </div>
        <div class="flex items-center gap-2">
          <button
            type="button"
            phx-click="delete_draft"
            phx-target={@myself}
            data-confirm="Delete this draft? Its unpublished changes are gone for good; published versions are untouched."
            class="rounded-md border border-red-600 px-2 py-1 text-xs text-red-600 hover:bg-red-50"
          >
            Delete draft
          </button>
          <.link
            navigate={version_show_path(assigns, @version)}
            role="switch"
            aria-checked="true"
            aria-label="Switch to Show"
            class="flex items-center gap-1.5 text-xs"
          >
            <span class="text-zinc-500">Show</span>
            <span class="relative inline-flex h-5 w-9 shrink-0 items-center rounded-full bg-cyan-600 transition-colors">
              <span class="inline-block h-4 w-4 translate-x-4 rounded-full bg-white shadow transition-transform" />
            </span>
            <span class="font-semibold text-zinc-900">Edit</span>
          </.link>
          <%!-- The remote submit: an HTML form= reference into the
                DynamicForm below, so Save lives in the header like every
                other page's primary action. Styled like the flows editor's
                Save — quiet until changes exist, primary once they do. --%>
          <button
            type="submit"
            form={"#{@id}-form-form"}
            class={[
              "phx-submit-loading:opacity-75 rounded-md border px-2 py-1 text-xs",
              if(@dirty?,
                do: "border-cyan-600 bg-cyan-600 text-white hover:bg-cyan-700",
                else: "border-zinc-300 text-zinc-700 hover:border-zinc-400"
              )
            ]}
          >
            Save
          </button>
          <button
            type="button"
            phx-click="open_publish"
            phx-target={@myself}
            class="rounded-md border border-zinc-300 px-2 py-1 text-xs hover:border-zinc-400"
          >
            Publish
          </button>
        </div>
      </div>

      <p :if={@error} class="mb-2 text-xs text-red-600">{@error}</p>
      <p :if={@notice} class="mb-2 text-xs text-green-700">{@notice}</p>

      <p
        :if={Forms.stale_draft?(@version)}
        class="mb-2 rounded-md border border-amber-300 bg-amber-50 px-2 py-1 text-xs text-amber-800"
      >
        This draft was based on a version that is no longer the latest — review before publishing.
      </p>

      <div class="flex flex-wrap gap-6">
        <div class="min-w-0 flex-1">
          <%!-- One form, one Save: the lineage's identity (name, description)
            above the version's definition, separated by a read-only strip
            saying which draft is being edited. The save event writes each
            value to its owner — identity to the form row, definition to the
            draft. Picking a different draft belongs on Show, where the
            version history lists them all.

            The 500ms debounce exists for the preview — no point remounting
            it per keystroke — so it only applies while auto-update is on. --%>
          <DynamicForm.form
            id={"#{@id}-form"}
            data={@form_data}
            hide_submit
            on_change={&changed(&1, @id)}
            on_submit={&validate_json/1}
            on_success={&saved(&1, @id)}
            change_debounce_in_ms={if(@auto_update?, do: 500)}
          >
        <:field type="text" name="name" label="Name" required />
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
        <:field type="html" name="draft_info">
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
        <:field type="comment" name="definition" label="Definition (JSON)" required />
          </DynamicForm.form>
        </div>

        <div class="min-w-0 flex-1">
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
                  "relative inline-flex h-5 w-9 shrink-0 items-center rounded-full transition-colors",
                  if(@auto_update?, do: "bg-cyan-600", else: "bg-zinc-300")
                ]}>
                  <span class={[
                    "inline-block h-4 w-4 rounded-full bg-white shadow transition-transform",
                    if(@auto_update?, do: "translate-x-4", else: "translate-x-0.5")
                  ]} />
                </span>
              </button>
              <button
                :if={!@auto_update?}
                type="button"
                phx-click="update_preview"
                phx-target={@myself}
                class="rounded-md border border-zinc-300 px-2 py-1 text-xs hover:border-zinc-400"
              >
                Refresh
              </button>
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
        saved_note
      />
    </div>
    """
  end

  defp preview_id(assigns), do: "#{assigns.id}-preview-r#{assigns.preview_rev}"

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

  defp show_path(assigns), do: form_base_path(assigns)

  defp version_show_path(assigns, version) do
    "#{form_base_path(assigns)}/versions/#{version.id}"
  end
end
