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
  version can be archived. With no draft under way, New draft from this
  version is the next thing to do, and is primary.

  The form's details — name, slug, description, type — are listed as a fact
  sheet under the header, and **Edit form details** leads to
  `FormFlow.Web.Templates.Forms.Details`, where they change for every
  version at once.

  ## Prefills

  The preview has the form's prefills over it, as the draft editor's does
  (`FormFlow.Web.Templates.Forms.Edit`, "Prefills"): the picker fills the
  version being looked at with a saved set of answers, and the **⋮** menu
  writes them — including **Capture prefill**, which reads the preview as it
  has been filled in by hand. They are here and not only there because a
  prefill belongs to the form rather than to a version — a form with
  everything published has no draft to edit, and so no edit page, and this is
  where it keeps them.

  The selection is the `prefill` param, the same one the editor uses, so a
  link carries it; nothing on this page is unsaved, so choosing one goes
  straight there.
  """

  use Phoenix.LiveComponent

  import FormFlow.Web.Helpers.Paths

  alias FormFlow.Data.Templates.Flows
  alias FormFlow.Data.Templates.Flows.Health
  alias FormFlow.Web.Components.Core
  alias FormFlow.Web.Templates
  alias FormFlow.Web.Templates.Components.Header
  alias FormFlow.Web.Templates.Forms.Shared
  alias FormFlow.Data.Templates.Forms
  alias FormFlow.Web.Components.Forms.PrefillDialog
  alias FormFlow.Web.Components.Forms.PrefillMenu
  alias FormFlow.Web.Components.Forms.PrefillPicker
  alias FormFlow.Web.Components.Forms.Prefills
  alias FormFlow.Web.Templates.Forms.Components.Canvas
  alias FormFlow.Web.Templates.Forms.Components.CatalogBadge
  alias FormFlow.Web.Templates.Forms.Components.PublishDialog
  alias FormFlow.Web.Templates.Forms.Preview

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       error: nil,
       publishing?: false,
       prefill_dialog: nil,
       prefill_error: nil,
       preview_rev: 0
     )}
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
    |> Shared.assign_prefills(form, assigns.params["prefill"])
    |> assign_breadcrumb(node)
  end

  # The page's form types, with each related-form property's choices filled
  # in for this form's place in its flow. Read-only pages still need
  # them, to render a stored value as its name.
  defp form_types(_assigns, nil, _version, _node), do: []

  defp form_types(assigns, form, _version, _node) do
    assigns.form_types
    |> Templates.Shared.fill_related_forms(
      assigns.root_id,
      assigns.node_id,
      FormFlow.Config.Forms.Type.property_values(form)
    )
  end

  # The stored form_type rendered as its human name — nil when unset (the
  # default applies)
  defp form_type_label(assigns) do
    with type when is_binary(type) <- assigns.form.properties["form_type"] do
      case Templates.Shared.type(assigns.form_types, type) do
        %{name: name} -> name
        nil -> type
      end
    end
  end

  # The stored type's property values, paired with the properties that
  # declare them, for the header — only those with a value
  defp type_property_values(assigns) do
    values = FormFlow.Config.Forms.Type.property_values(assigns.form)

    for property <-
          Templates.Shared.properties(assigns.form_types, assigns.form.properties["form_type"]),
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

  # Nothing on this page is unsaved, so a prefill is chosen and the page
  # reloads with it named — no asking first, which is the one thing the
  # editor's copy of this does differently (`FormFlow.Web.Templates.Forms.Edit`)
  @impl true
  def handle_event("pick_prefill", %{"prefill" => name}, socket) do
    {:noreply, push_navigate(socket, to: prefill_path(socket.assigns, presence(name)))}
  end

  @impl true
  def handle_event("open_prefill", %{"action" => "create"}, socket) do
    {:noreply, open_prefill_dialog(socket, Prefills.dialog(:create))}
  end

  # The menu item is not drawn with nothing selected; this is the guard behind it
  def handle_event("open_prefill", %{"action" => "update"}, socket) do
    case socket.assigns.prefill do
      nil -> {:noreply, socket}
      prefill -> {:noreply, open_prefill_dialog(socket, Prefills.dialog(:update, prefill))}
    end
  end

  @impl true
  def handle_event("cancel_prefill", _params, socket) do
    {:noreply, assign(socket, prefill_dialog: nil, prefill_error: nil)}
  end

  # Capture: the answers came off the rendered preview and ride in with the
  # click (`FormFlow.Web.Components.Forms.PrefillMenu`), so the
  # dialog is the same one the other two open, over what is on screen
  @impl true
  def handle_event("capture_prefill", %{"params" => params}, socket) do
    dialog = Prefills.captured_dialog(socket.assigns.prefill, params)

    {:noreply, open_prefill_dialog(socket, dialog)}
  end

  @impl true
  def handle_event("save_prefill", %{"name" => name, "data" => json}, socket) do
    %{form: form, prefill_dialog: %{action: action}, prefill: prefill} = socket.assigns
    attrs = %{name: name, answers: json, user_id: socket.assigns.user_id}

    case Prefills.save(form, action, prefill, attrs) do
      {:ok, form} ->
        socket =
          socket
          |> assign(form: form, prefill_dialog: nil, prefill_error: nil)
          |> Shared.assign_prefills(form, socket.assigns.params["prefill"])

        if Prefills.selects_another?(action, prefill, name) do
          {:noreply, push_navigate(socket, to: prefill_path(socket.assigns, name))}
        else
          {:noreply, remount_preview(socket)}
        end

      # Refused — the dialog stays open over what was typed, which is the
      # only copy of it: the fields are the assign, not the browser's DOM
      {:error, message} ->
        {:noreply,
         assign(socket,
           prefill_dialog: %{socket.assigns.prefill_dialog | name: name, data: json},
           prefill_error: message
         )}
    end
  end

  @impl true
  def handle_event("delete_prefill", _params, socket) do
    %{form: form, prefill: prefill} = socket.assigns

    case prefill && Forms.delete_prefill(form, prefill.name) do
      {:ok, form} ->
        # The URL still names it, and now names nothing that is there — the
        # same state a link to a prefill someone else deleted arrives in
        {:noreply,
         socket
         |> assign(form: form)
         |> Shared.assign_prefills(form, socket.assigns.params["prefill"])
         |> remount_preview()}

      _none ->
        {:noreply, socket}
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
        places = Templates.Shared.list_names(Templates.Shared.usage_labels(socket.assigns.usages))

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
    if length(Templates.Shared.usage_labels(usages)) == 1, do: "uses", else: "use"
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
          {property.name}: {Templates.Shared.display_value(property, value)}
        </:metadata>
        <%!-- Reached through a flow: that flow's health, which a publish
              here is the usual way to mend --%>
        <:actions :if={@root}>
          <FormFlow.Web.Templates.Components.Health.health base={@base} flow={@root} components={@components} />
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
          <%!-- The next thing to do, when there is no draft to continue:
                primary then, and plain beside Continue editing latest draft --%>
          <Core.button
            :if={@version.status in ["published", "archived"]}
            components={@components}
            phx-click="create_draft"
            phx-target={@myself}
            class={["btn", if(latest_draft(@versions), do: "", else: "btn-primary")]}
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
          <Core.button components={@components} navigate={details_path(assigns)} class="btn">
            Edit form details
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
        :if={Shared.reusing?(@node, @form)}
        form={@form}
        usages={@usages}
        components={@components}
        class="mb-3"
      />
      <p :if={@node == nil and @form.owner_flow_id == nil} class="mb-3 text-xs text-zinc-500">
        <span :if={@usages == []}>Not used in any flow yet.</span>
        <span :if={@usages != []}>
          Used in {Enum.join(Templates.Shared.usage_labels(@usages), ", ")} — edits and publishes reach every one of them.
        </span>
      </p>

      <%!-- The details every version shares, as a fact sheet; the header's
            Edit form details is where they change. Through a step the name
            and slug are the step's, the way the fields that edit them are. --%>
      <div class="mb-6">
        <h3 class="mb-1 text-sm font-medium text-zinc-500">Form details</h3>
        <dl class="grid grid-cols-1 gap-4 text-sm md:grid-cols-4 [&_dt]:text-sm [&_dt]:font-medium [&_dt]:text-zinc-500 [&_dd]:mt-0.5">
          <div class="min-w-0">
            <dt>{Shared.name_label(@node)}</dt>
            <dd>{Shared.step_name(@form, @node)}</dd>
          </div>
          <div class="min-w-0">
            <dt>{Shared.slug_label(@node)}</dt>
            <dd><.detail_value value={Shared.step_slug(@form, @node)} code /></dd>
          </div>
          <div class="min-w-0">
            <dt>Description</dt>
            <dd><.detail_value value={@form.description} /></dd>
          </div>
          <div :if={@form_types != []} class="min-w-0">
            <dt>Form type</dt>
            <dd><.detail_value value={form_type_label(assigns)} /></dd>
          </div>
          <div :for={{property, value} <- type_property_values(assigns)} class="min-w-0">
            <dt>{property.name}</dt>
            <dd>{Templates.Shared.display_value(property, value)}</dd>
          </div>
        </dl>
      </div>

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
          <h3 class="mb-1 text-sm font-medium text-zinc-500">Versions</h3>
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
          <h3 class="mb-1 text-sm font-medium text-zinc-500">Preview</h3>
          <PrefillPicker.prefill_picker
            id={"#{@id}-prefill-select"}
            prefills={@prefills}
            selected={@prefill && @prefill.name}
            missing={@missing_prefill_name}
            target={@myself}
            components={@components}
            class="mb-3"
          >
            <:actions>
              <PrefillMenu.prefill_menu
                id={"#{@id}-prefill-actions"}
                selected={@prefill}
                form_id={Preview.form_id(preview_id(assigns))}
                target={@myself}
              />
            </:actions>
          </PrefillPicker.prefill_picker>
          <Canvas.canvas definition={@version.definition} components={@components}>
            <:empty>This version has no elements.</:empty>
            {live_render(@socket, Preview,
              id: preview_id(assigns),
              session: %{
                "id" => preview_id(assigns),
                "version_id" => @version.id,
                "data" => (@prefill && @prefill.data) || %{}
              }
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

      <PrefillDialog.prefill_dialog
        :if={@prefill_dialog}
        action={@prefill_dialog.action}
        name={@prefill_dialog.name}
        data={@prefill_dialog.data}
        captured={@prefill_dialog.captured}
        target={@myself}
        error={@prefill_error}
        components={@components}
      />
    </div>
    """
  end

  # One value of the fact sheet: a dash for none, monospace for a slug
  attr(:value, :any, default: nil)
  attr(:code, :boolean, default: false)

  defp detail_value(%{value: empty} = assigns) when empty in [nil, ""] do
    ~H"""
    <span class="text-zinc-400">—</span>
    """
  end

  defp detail_value(%{code: true} = assigns) do
    ~H"""
    <code class="text-xs">{@value}</code>
    """
  end

  defp detail_value(assigns) do
    ~H"""
    {@value}
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

  defp open_prefill_dialog(socket, dialog),
    do: assign(socket, prefill_dialog: dialog, prefill_error: nil)

  # A prefill's answers ride in the preview's session, and a child LiveView
  # never re-reads one — so answers that changed mean a fresh child
  defp remount_preview(socket),
    do: assign(socket, :preview_rev, socket.assigns.preview_rev + 1)

  defp preview_id(assigns),
    do: "form-preview-#{assigns.version.id}-r#{assigns.preview_rev}"

  defp presence(empty) when empty in [nil, ""], do: nil
  defp presence(value), do: value

  defp details_path(assigns) do
    preserve_query_params("#{form_base_path(assigns)}/edit", assigns.params, ["mode"])
  end

  # This same page, with the prefill named — or without it, which is what
  # selecting nothing means
  defp prefill_path(assigns, name) do
    Shared.prefill_path(
      "#{form_base_path(assigns)}/versions/#{assigns.version.id}",
      assigns.params,
      name
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
