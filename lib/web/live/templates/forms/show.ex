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

  A published or archived version's actions fork it — New draft from this
  version — and, while a draft exists, lead to the newest one: Continue
  editing latest draft. The default view is the latest published version, so
  without that a draft already under way is easy to miss. Only a published
  version can be archived.
  """

  use Phoenix.LiveComponent

  import FormFlow.Web.Helpers.Paths

  alias FormFlow.Data.Templates.Flows
  alias FormFlow.Data.Templates.Flows.Health
  alias FormFlow.Web.Components.Core
  alias FormFlow.Web.Templates.Components.Header
  alias FormFlow.Web.Templates.Shared
  alias FormFlow.Data.Templates.Forms
  alias FormFlow.Web.Templates.Forms.Components.Canvas
  alias FormFlow.Web.Templates.Forms.Components.CatalogBadge
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
        refresh_health(socket)
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
      |> assign_new(:user_id, fn -> nil end)
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
      counts_by_flow: (form && Forms.instance_counts_by_flow(form.id)) || [],
      usages: (form && Flows.form_usages(form.id)) || [],
      form_types: form_types(assigns, form, version, node)
    )
    |> assign_breadcrumb(node)
  end

  # A step whose form is the catalog's: shared, and said so
  defp reusing?(%{node: %{}, form: %{owner_flow_id: nil}}), do: true
  defp reusing?(_assigns), do: false

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
        refresh_health(socket)
        {:noreply, push_navigate(socket, to: version_path(socket.assigns, archived))}

      {:error, _changeset} ->
        {:noreply, assign(socket, :error, "Only published versions can be archived.")}
    end
  end

  @impl true
  def handle_event("create_draft", _params, socket) do
    case Forms.create_draft(socket.assigns.form.id, based_on: socket.assigns.version.id) do
      {:ok, draft} ->
        refresh_health(socket)
        {:noreply, push_navigate(socket, to: edit_path(socket.assigns, draft))}

      {:error, _reason} ->
        {:noreply, assign(socket, :error, "Could not create a draft from this version.")}
    end
  end

  @impl true
  def handle_event("delete_draft", _params, socket) do
    case Forms.delete_draft(socket.assigns.version) do
      {:ok, _draft} ->
        refresh_health(socket)
        # Back to the form's default view: latest published, or the newest
        # remaining draft, or the no-versions state
        to =
          preserve_query_params(form_base_path(socket.assigns), socket.assigns.params, ["mode"])

        {:noreply, push_navigate(socket, to: to)}

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

      {:error, :in_use} ->
        places = Shared.list_names(Shared.usage_labels(socket.assigns.usages))

        {:noreply,
         assign(
           socket,
           :error,
           "This form can't be deleted: #{places} #{use_verb(socket.assigns.usages)} it. " <>
             "Remove those steps first."
         )}

      {:error, _other} ->
        {:noreply, assign(socket, :error, "Could not delete the form. Please try again.")}
    end
  end

  defp use_verb(usages) do
    if length(Shared.usage_labels(usages)) == 1, do: "uses", else: "use"
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

  def render(assigns) do
    ~H"""
    <div>
      <Header.header
        base={@base}
        section="forms"
        root={@root}
        parent_node={@parent_node}
        name={@form.name}
        mode={@params["mode"]}
        components={@components}
      >
        <:metadata :if={@version}>{version_badge(@version)}</:metadata>
        <:metadata :if={form_type_label(assigns)}>{form_type_label(assigns)}</:metadata>
        <:metadata :for={{property, value} <- type_property_values(assigns)}>
          {property.name}: {Shared.display_value(property, value)}
        </:metadata>
        <%!-- Reached through a flow: that flow's health, which a publish
              here is the usual way to mend --%>
        <:actions :if={@root}>
          <FormFlow.Web.Templates.Components.Health.health base={@base} flow={@root} />
        </:actions>
        <:actions :if={@version}>
          <Core.button
            :if={@version.status == "draft" && length(@versions) > 1}
            components={@components}
            phx-click="delete_draft"
            phx-target={@myself}
            data-confirm="Delete this draft? Its unpublished changes are gone for good; published versions are untouched."
            class="btn btn-error btn-ghost"
          >
            Delete draft
          </Core.button>
          <Core.button
            :if={@version.status == "draft"}
            components={@components}
            navigate={edit_path(assigns, @version)}
            class="btn btn-ghost"
          >
            Edit draft
          </Core.button>
          <Core.button
            :if={@version.status == "draft"}
            components={@components}
            phx-click="open_publish"
            phx-target={@myself}
            variant="primary"
          >
            Publish
          </Core.button>
          <Core.button
            :if={@version.status != "draft" && latest_draft(@versions)}
            components={@components}
            navigate={edit_path(assigns, latest_draft(@versions))}
            variant="primary"
          >
            Continue editing latest draft
          </Core.button>
          <Core.button
            :if={@version.status in ["published", "archived"]}
            components={@components}
            phx-click="create_draft"
            phx-target={@myself}
            class="btn"
          >
            New draft from this version
          </Core.button>
          <Core.button
            :if={@version.status == "published"}
            components={@components}
            phx-click="archive"
            phx-target={@myself}
            data-confirm="Archive this version? It stops being the latest; users pinned to it are unaffected."
            class="btn"
          >
            Archive version
          </Core.button>
          <Core.button
            :if={@form.owner_flow_id == nil and @node == nil}
            components={@components}
            phx-click="delete"
            phx-target={@myself}
            data-confirm="Delete this form and all of its versions?"
            class="btn btn-error btn-ghost"
            aria-label="Delete"
            title="Delete"
          >
            <Core.icon components={@components} name="hero-trash" class="size-5" />
          </Core.button>
        </:actions>
      </Header.header>

      <Core.error :if={@error} components={@components}>{@error}</Core.error>

      <%!-- Sharing, made visible: from a step, the badge; on the catalog's
            own page, where the form is used, so the admin knows what an
            edit reaches before making it --%>
      <CatalogBadge.catalog_badge
        :if={reusing?(assigns)}
        form={@form}
        usages={@usages}
        components={@components}
        class="mb-3"
      />
      <p :if={@node == nil and @form.owner_flow_id == nil} class="mb-3 text-xs text-zinc-500">
        <span :if={@usages == []}>Not used in any flow yet.</span>
        <span :if={@usages != []}>
          Used in {Enum.join(Shared.usage_labels(@usages), ", ")} — edits and publishes reach every one of them.
        </span>
      </p>

      <p :if={@form.description} class="mb-3 text-sm text-zinc-600">{@form.description}</p>

      <Core.alert
        :if={@version && @version.status == "draft" && Forms.stale_draft?(@version)}
        kind={:warning}
        components={@components}
        class="mb-3"
      >
        This draft was based on a version that is no longer the latest — review before publishing.
      </Core.alert>

      <div class="flex flex-wrap gap-6">
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

        <div :if={@version} class="min-w-0 flex-1">
          <h3 class="mb-1 text-xs font-medium text-zinc-500">Preview</h3>
          <Canvas.canvas definition={@version.definition}>
            <:empty>This version has no elements.</:empty>
            {live_render(@socket, Preview,
              id: "form-preview-#{@version.id}",
              session: %{"id" => "form-preview-#{@version.id}", "version_id" => @version.id}
            )}
          </Canvas.canvas>
        </div>

        <Core.alert :if={@version == nil} components={@components}>
          This form has no versions.
        </Core.alert>
      </div>

      <PublishDialog.publish_dialog
        :if={@publishing?}
        id={"#{@id}-publish-form"}
        counts={@counts}
        counts_by_flow={@counts_by_flow}
        target={@myself}
        on_success={&publish(&1, @id)}
        components={@components}
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
        refresh_health(socket)
        {:noreply, push_navigate(socket, to: version_path(socket.assigns, published))}

      {:error, :not_draft} ->
        {:noreply, assign(socket, :error, "Only drafts can be published.")}

      {:error, _other} ->
        {:noreply, assign(socket, :error, "Could not publish. Please try again.")}
    end
  end

  # The newest draft, or nil — `versions` is newest first
  defp latest_draft(versions), do: Enum.find(versions, &(&1.status == "draft"))

  # Once, after a version changed: every root with a step on this form — one
  # for an owned form, every user of a catalog form — recomputes its health
  defp refresh_health(socket) do
    Health.refresh_for_form(socket.assigns.form.id,
      flow_types: socket.assigns.flow_types,
      form_types: socket.assigns.form_types
    )
  end

  defp version_badge(%{status: "draft"}), do: "draft"
  defp version_badge(%{status: "published"} = v), do: "v#{v.version} · published"
  defp version_badge(%{status: "archived"} = v), do: "v#{v.version} · archived"

  defp form_base_path(%{node: nil} = assigns), do: "#{assigns.base}/forms/#{assigns.form.id}"

  defp form_base_path(assigns) do
    "#{assigns.base}/flows/#{assigns.root_id}/nodes/#{assigns.node_id}/form"
  end

  defp version_path(assigns, version) do
    preserve_query_params(
      "#{form_base_path(assigns)}/versions/#{version.id}",
      assigns.params,
      ["mode"]
    )
  end

  defp edit_path(assigns, version) do
    preserve_query_params(
      "#{form_base_path(assigns)}/versions/#{version.id}/edit",
      assigns.params,
      ["mode"]
    )
  end
end
