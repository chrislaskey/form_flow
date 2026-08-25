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

  alias FormFlow.Data.Graphs
  alias FormFlow.Data.Templates.Forms
  alias FormFlow.Web.Templates.Forms.PublishDialog

  @impl true
  def mount(socket) do
    {:ok, assign(socket, error: nil, notice: nil, publishing?: false)}
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
    dirty? = values_from(payload.data) != socket.assigns.saved_values

    {:ok, assign(socket, dirty?: dirty?, notice: nil)}
  end

  def update(%{event: "save", payload: payload}, socket) do
    identity = %{name: payload.data[:name], description: payload.data[:description]}

    with {:ok, form} <- Forms.update(socket.assigns.form, identity),
         {:ok, version} <-
           Forms.update_draft(socket.assigns.version, %{definition: payload.extra[:definition]}) do
      {:ok,
       assign(socket,
         form: form,
         version: version,
         versions: Forms.list_versions(form.id),
         saved_values: values_from(payload.data),
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
      |> assign_new(:app, fn -> "default" end)
      |> assign_new(:form_id, fn -> nil end)
      |> assign_new(:version_id, fn -> nil end)
      |> assign_new(:root_id, fn -> nil end)
      |> assign_new(:node_id, fn -> nil end)

    {:ok, load(socket)}
  end

  defp load(socket) do
    assigns = socket.assigns
    node = assigns.node_id && Graphs.get_node(assigns.node_id)
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
      counts: form && Forms.instance_counts(form.id)
    )
    |> assign_breadcrumb(node)
    |> assign_new(:definition_json, fn ->
      version && Phoenix.json_library().encode!(version.definition, pretty: true)
    end)
    |> then(fn socket ->
      socket
      |> assign(:saved_values, saved_values(form, socket.assigns.definition_json))
      |> assign(:dirty?, false)
    end)
  end

  # What the last save wrote, in the shape DynamicForm reports — the baseline
  # `dirty?` compares against, so the Save button can go primary exactly when
  # the form differs from what's persisted (matching the flows editor)
  defp saved_values(nil, _definition_json), do: nil

  defp saved_values(form, definition_json) do
    %{
      name: to_string(form.name),
      description: to_string(form.description),
      definition: to_string(definition_json)
    }
  end

  defp values_from(payload_data) do
    %{
      name: to_string(payload_data[:name] || ""),
      description: to_string(payload_data[:description] || ""),
      definition: to_string(payload_data[:definition] || "")
    }
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
    root = Graphs.get(socket.assigns.root_id)

    parent_node =
      if root && node.graph_id != root.id,
        do: Graphs.embedding_node(node.graph_id, root.id)

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

      <%!-- One form, one Save: the lineage's identity (name, description)
            above the version's definition, separated by a read-only strip
            saying which draft is being edited. The save event writes each
            value to its owner — identity to the form row, definition to the
            draft. Picking a different draft belongs on Show, where the
            version history lists them all. --%>
      <DynamicForm.form
        id={"#{@id}-form"}
        data={%{name: @form.name, description: @form.description, definition: @definition_json}}
        hide_submit
        on_change={&changed(&1, @id)}
        on_submit={&validate_json/1}
        on_success={&saved(&1, @id)}
      >
        <:field type="text" name="name" label="Name" required />
        <:field type="comment" name="description" label="Description" />
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
