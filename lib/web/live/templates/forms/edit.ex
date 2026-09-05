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

  alias FormFlow.Data.Templates.Flows
  alias FormFlow.Web.Components.Core
  alias FormFlow.Web.Templates.Components.Breadcrumb
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
      slug: to_string(form.slug),
      form_type: to_string(form.properties["form_type"]),
      property_values: FormFlow.Config.Forms.Type.property_values(form),
      definition: to_string(definition_json)
    }
  end

  defp values_from(payload_data, pending_type, properties) do
    %{
      name: to_string(payload_data[:name] || ""),
      description: to_string(payload_data[:description] || ""),
      slug: to_string(payload_data[:slug] || ""),
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
      slug: form.slug,
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
        |> Map.take([:name, :description, :slug, :definition])
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

      <Core.alert :if={Forms.stale_draft?(@version)} kind={:warning} components={@components} class="mb-3">
        This draft was based on a version that is no longer the latest — review before publishing.
      </Core.alert>

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
end
