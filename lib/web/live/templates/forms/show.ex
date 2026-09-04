defmodule FormFlow.Web.Templates.Forms.Show do
  @moduledoc """
  `FormFlow.Web.Templates.Forms.Show` LiveComponent shows one form — a
  specific version, or the resolved default.

  Two addressing modes, mirroring the flows pages:

    * `form_id` (+ optional `version_id`) — standalone, from the catalog:
      `/forms/:id` and `/forms/:id/versions/:version_id`
    * `root_id` + `node_id` (+ optional `version_id`) — drill-in from a flow,
      `/flows/:root/nodes/:node_id/form...`, with a breadcrumb back through
      the embedding subflow to the root

  Without a `version_id` the page resolves the latest *published* version;
  when nothing has been published yet it falls back to the newest draft (with
  its draft badge — viewing a draft read-only is the pre-publish preview).
  Instances never resolve this way: they render only through their own pins.

  Publishing happens here: the dialog offers the three presets (bug / small /
  big fix) with plain-language descriptions and restates the blast radius
  before anything moves.
  """

  use Phoenix.LiveComponent

  import FormFlow.Web.Helpers.Paths

  alias FormFlow.Data.Templates.Flows
  alias FormFlow.Web.Templates.Shared
  alias FormFlow.Data.Templates.Forms
  alias FormFlow.Web.Templates.Forms.Components.PublishDialog
  alias FormFlow.Web.Templates.Forms.Preview

  @impl true
  def mount(socket) do
    {:ok, assign(socket, error: nil, publishing?: false)}
  end

  @impl true
  def update(%{event: "publish", payload: payload}, socket) do
    preset = String.to_existing_atom(payload.data[:preset])

    case Forms.update_status(socket.assigns.version, :published, preset: preset) do
      {:ok, published} ->
        # Redirects are forbidden inside update/2; handle_async is the
        # component-owned callback where they are allowed
        to = version_path(socket.assigns, published)
        {:ok, start_async(socket, :navigate, fn -> to end)}

      {:error, :not_draft} ->
        {:ok, assign(socket, error: "Only drafts can be published.", publishing?: false)}

      {:error, _other} ->
        {:ok, assign(socket, error: "Could not publish. Please try again.", publishing?: false)}
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

    {:ok, load(socket)}
  end

  @impl true
  def handle_async(:navigate, {:ok, to}, socket) do
    {:noreply, push_navigate(socket, to: to)}
  end

  defp load(socket) do
    assigns = socket.assigns
    node = assigns.node_id && Flows.get_node(assigns.node_id)
    form = resolve_form(assigns.form_id, node)
    versions = if form, do: Forms.list_versions(form.id), else: []

    version = resolve_version(form, versions, assigns.version_id)

    socket
    |> assign(
      form: form,
      node: node,
      versions: versions,
      version: version,
      counts: form && Forms.instance_counts(form.id),
      form_types: form_types(assigns, form, version, node)
    )
    |> assign_breadcrumb(node)
  end

  # The page's form types, with each related-form property's choices filled
  # in for this form's place in its flow. Read-only pages still need
  # them, to render a stored value as its name.
  defp form_types(_assigns, nil, _version, _node), do: []

  defp form_types(assigns, form, _version, _node) do
    assigns.form_types
    |> Shared.fill_related_forms(
      assigns.root_id,
      assigns.node_id,
      FormFlow.Config.Forms.Type.property_values(form)
    )
  end

  # The stored form_type rendered as its human name — nil when unset (the
  # default applies)
  defp form_type_label(assigns) do
    with type when is_binary(type) <- assigns.form.properties["form_type"] do
      case Shared.type(assigns.form_types, type) do
        %{name: name} -> name
        nil -> type
      end
    end
  end

  # The stored type's property values, paired with the properties that
  # declare them, for the header — only those with a value
  defp type_property_values(assigns) do
    values = FormFlow.Config.Forms.Type.property_values(assigns.form)

    for property <- Shared.properties(assigns.form_types, assigns.form.properties["form_type"]),
        value = values[property.id],
        do: {property, value}
  end

  defp resolve_form(form_id, node) do
    id = form_id || (node && node.form_id)
    id && Forms.get(id)
  end

  defp assign_breadcrumb(socket, nil), do: assign(socket, root: nil, parent_node: nil)

  defp assign_breadcrumb(socket, node) do
    root = Flows.get(socket.assigns.root_id)

    parent_node =
      if root && node.flow_id != root.id,
        do: Flows.embedding_node(node.flow_id, root.id)

    assign(socket, root: root, parent_node: parent_node)
  end

  # An explicit version id wins; otherwise latest published, falling back to
  # the newest draft so an unpublished form still has a page
  defp resolve_version(nil, _versions, _version_id), do: nil

  defp resolve_version(_form, versions, version_id) when is_binary(version_id) do
    Enum.find(versions, &(&1.id == version_id))
  end

  defp resolve_version(form, versions, nil) do
    Forms.get_latest_version(form.id) || List.first(versions)
  end

  @impl true
  def handle_event("open_publish", _params, socket) do
    if Forms.ever_published?(socket.assigns.form.id) do
      {:noreply, assign(socket, :publishing?, true)}
    else
      # Nothing has ever been published, so no instance can exist and no
      # migration policy is meaningful — the dialog would prompt about
      # nobody. Publish directly; every later publish prompts.
      publish_directly(socket)
    end
  end

  @impl true
  def handle_event("cancel_publish", _params, socket) do
    {:noreply, assign(socket, :publishing?, false)}
  end

  @impl true
  def handle_event("archive", _params, socket) do
    case Forms.update_status(socket.assigns.version, :archived) do
      {:ok, archived} ->
        {:noreply, push_navigate(socket, to: version_path(socket.assigns, archived))}

      {:error, _changeset} ->
        {:noreply, assign(socket, :error, "Only published versions can be archived.")}
    end
  end

  @impl true
  def handle_event("create_draft", _params, socket) do
    case Forms.create_draft(socket.assigns.form.id, based_on: socket.assigns.version.id) do
      {:ok, draft} ->
        {:noreply, push_navigate(socket, to: edit_path(socket.assigns, draft))}

      {:error, _reason} ->
        {:noreply, assign(socket, :error, "Could not create a draft from this version.")}
    end
  end

  @impl true
  def handle_event("delete_draft", _params, socket) do
    case Forms.delete_draft(socket.assigns.version) do
      {:ok, _draft} ->
        # Back to the form's default view: latest published, or the newest
        # remaining draft, or the no-versions state
        {:noreply, push_navigate(socket, to: form_base_path(socket.assigns))}

      {:error, :has_instances} ->
        {:noreply, assign(socket, :error, "This draft can't be deleted: it has instances.")}

      {:error, _other} ->
        {:noreply, assign(socket, :error, "Only drafts can be deleted.")}
    end
  end

  @impl true
  def handle_event("delete", _params, socket) do
    case Forms.delete(socket.assigns.form) do
      {:ok, _form} ->
        {:noreply, push_navigate(socket, to: "#{socket.assigns.base}/forms")}

      {:error, :has_instances} ->
        {:noreply,
         assign(
           socket,
           :error,
           "This form can't be deleted: it has submitted data. Delete its instances first."
         )}

      {:error, _other} ->
        {:noreply, assign(socket, :error, "Could not delete the form. Please try again.")}
    end
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
          {@form.name}
          <span :if={@version} class="ml-1 text-xs font-normal text-zinc-500">
            {version_badge(@version)}
          </span>
          <span :if={form_type_label(assigns)} class="text-xs font-normal text-zinc-500">
            · {form_type_label(assigns)}
          </span>
          <span
            :for={{property, value} <- type_property_values(assigns)}
            class="text-xs font-normal text-zinc-500"
          >
            · {property.name}: {Shared.display_value(property, value)}
          </span>
        </div>
        <div :if={@version} class="flex items-center gap-2">
          <button
            :if={@version.status == "draft"}
            type="button"
            phx-click="delete_draft"
            phx-target={@myself}
            data-confirm="Delete this draft? Its unpublished changes are gone for good; published versions are untouched."
            class="rounded-md border border-red-600 px-2 py-1 text-xs text-red-600 hover:bg-red-50"
          >
            Delete draft
          </button>
          <.link
            :if={@version.status == "draft"}
            navigate={edit_path(assigns, @version)}
            role="switch"
            aria-checked="false"
            aria-label="Switch to Edit"
            class="flex items-center gap-1.5 text-xs"
          >
            <span class="font-semibold text-zinc-900">Show</span>
            <span class="relative inline-flex h-5 w-9 shrink-0 items-center rounded-full bg-zinc-300 transition-colors">
              <span class="inline-block h-4 w-4 translate-x-0.5 rounded-full bg-white shadow transition-transform" />
            </span>
            <span class="text-zinc-500">Edit</span>
          </.link>
          <button
            :if={@version.status == "draft"}
            type="button"
            phx-click="open_publish"
            phx-target={@myself}
            class="rounded-md border border-cyan-600 bg-cyan-600 px-2 py-1 text-xs text-white hover:bg-cyan-700"
          >
            Publish
          </button>
          <button
            :if={@version.status == "published"}
            type="button"
            phx-click="create_draft"
            phx-target={@myself}
            class="rounded-md border border-zinc-300 px-2 py-1 text-xs hover:border-zinc-400"
          >
            New draft from this version
          </button>
          <button
            :if={@version.status == "published"}
            type="button"
            phx-click="archive"
            phx-target={@myself}
            data-confirm="Archive this version? It stops being the latest; users pinned to it are unaffected."
            class="rounded-md border border-zinc-300 px-2 py-1 text-xs hover:border-zinc-400"
          >
            Archive
          </button>
          <button
            :if={@form.owner_flow_id == nil and @node == nil}
            type="button"
            phx-click="delete"
            phx-target={@myself}
            data-confirm="Delete this form and all of its versions?"
            class="rounded-md border border-red-600 px-2 py-1 text-xs text-red-600 hover:bg-red-50"
          >
            Delete
          </button>
        </div>
      </div>

      <p :if={@error} class="mb-2 text-xs text-red-600">{@error}</p>
      <p :if={@form.description} class="mb-3 text-sm text-zinc-600">{@form.description}</p>

      <p
        :if={@version && @version.status == "draft" && Forms.stale_draft?(@version)}
        class="mb-2 rounded-md border border-amber-300 bg-amber-50 px-2 py-1 text-xs text-amber-800"
      >
        This draft was based on a version that is no longer the latest — review before publishing.
      </p>

      <div class="flex flex-wrap gap-6">
        <div :if={@version} class="min-w-0 flex-1">
          <h3 class="mb-1 text-xs font-medium text-zinc-500">Preview</h3>
          <div class="rounded-md border border-zinc-200 p-4">
            {live_render(@socket, Preview,
              id: "form-preview-#{@version.id}",
              session: %{"id" => "form-preview-#{@version.id}", "version_id" => @version.id}
            )}
          </div>
        </div>

        <div class="min-w-0 flex-1">
          <h3 class="mb-1 text-xs font-medium text-zinc-500">Definition</h3>
          <pre
            :if={@version}
            class="overflow-x-auto rounded-md border border-zinc-200 bg-zinc-50 p-3 text-xs"
          >{definition_json(@version)}</pre>
          <p :if={@version == nil} class="text-sm text-zinc-500">This form has no versions.</p>
        </div>

        <div class="w-64 shrink-0">
          <h3 class="mb-1 text-xs font-medium text-zinc-500">Versions</h3>
          <ul class="space-y-1 text-sm">
            <li :for={version <- @versions}>
              <.link
                navigate={version_path(assigns, version)}
                class={[
                  "hover:underline",
                  @version && @version.id == version.id && "font-semibold"
                ]}
              >
                {version_badge(version)}
              </.link>
              <span class="block text-[10px] text-zinc-400">
                {Calendar.strftime(version.updated_at, "%Y-%m-%d %H:%M")}
              </span>
            </li>
          </ul>
        </div>
      </div>

      <PublishDialog.publish_dialog
        :if={@publishing?}
        id={"#{@id}-publish-form"}
        counts={@counts}
        target={@myself}
        on_success={&publish(&1, @id)}
      />
    </div>
    """
  end

  defp publish(payload, component_id) do
    Phoenix.LiveView.send_update(__MODULE__, %{
      id: component_id,
      event: "publish",
      payload: payload
    })
  end

  defp publish_directly(socket) do
    case Forms.update_status(socket.assigns.version, :published) do
      {:ok, published} ->
        {:noreply, push_navigate(socket, to: version_path(socket.assigns, published))}

      {:error, :not_draft} ->
        {:noreply, assign(socket, :error, "Only drafts can be published.")}

      {:error, _other} ->
        {:noreply, assign(socket, :error, "Could not publish. Please try again.")}
    end
  end

  defp version_badge(%{status: "draft"}), do: "draft"
  defp version_badge(%{status: "published"} = v), do: "v#{v.version} · published"
  defp version_badge(%{status: "archived"} = v), do: "v#{v.version} · archived"

  defp definition_json(version) do
    Phoenix.json_library().encode!(version.definition, pretty: true)
  end

  defp form_base_path(%{node: nil} = assigns), do: "#{assigns.base}/forms/#{assigns.form.id}"

  defp form_base_path(assigns) do
    "#{assigns.base}/flows/#{assigns.root_id}/nodes/#{assigns.node_id}/form"
  end

  defp version_path(assigns, version), do: "#{form_base_path(assigns)}/versions/#{version.id}"

  defp edit_path(assigns, version), do: "#{version_path(assigns, version)}/edit"
end
