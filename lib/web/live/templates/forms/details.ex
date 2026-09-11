defmodule FormFlow.Web.Templates.Forms.Details do
  @moduledoc """
  `FormFlow.Web.Templates.Forms.Details` LiveComponent edits a form's
  details — name, slug, description, and type — on their own page.

  The details belong to the lineage, not to a version: a save here shows on
  every version at once, published ones included, and no draft or publish
  is involved. The page says so above the fields, and points back at the
  form's page — where drafts are — for anything about the form's content.
  Until a form has been published there is nothing that could be disturbed,
  and `FormFlow.Web.Templates.Forms.Edit` edits the details beside the
  draft's definition; this page is where they are edited once it has, and
  the show page's Edit form details leads here at any time.

  Addressed like `FormFlow.Web.Templates.Forms.Show`, standalone
  (`/forms/:id/edit`) or by drill-in (`/flows/:root/nodes/:node_id/form/edit`).
  Through a step the Name and Slug fields are the step's, the way the
  version editor's are (`FormFlow.Web.Templates.Forms.Shared`).

  `DynamicForm` runs the validation lifecycle, and `on_success` routes the
  valid payload back here through `send_update/2` — the `%{event: "save"}`
  clause of `update/2` performs the save.
  """

  use Phoenix.LiveComponent

  import FormFlow.Web.Helpers.Paths

  alias FormFlow.Data.Templates.Flows
  alias FormFlow.Data.Templates.Flows.Health
  alias FormFlow.Data.Templates.Forms
  alias FormFlow.Web.Components.Core
  alias FormFlow.Web.CoreComponents
  alias FormFlow.Web.Templates
  alias FormFlow.Web.Templates.Components.Header
  alias FormFlow.Web.Templates.Components.Note
  alias FormFlow.Web.Templates.Forms.Components.CatalogBadge
  alias FormFlow.Web.Templates.Forms.Shared

  @impl true
  def mount(socket) do
    {:ok, assign(socket, error: nil, notice: nil)}
  end

  @impl true
  def update(%{event: "change", payload: payload}, socket) do
    pending_type = pending_type(payload, socket.assigns.pending_type)
    properties = Templates.Shared.properties(socket.assigns.form_types, pending_type)

    dirty? =
      Shared.details_from(payload.data, pending_type, properties) != socket.assigns.saved_values

    socket =
      socket
      |> assign(dirty?: dirty?, notice: nil, pending_type: pending_type)
      |> reset_form_data_on_switch(pending_type, payload)

    {:ok, socket}
  end

  def update(%{event: "save", payload: payload}, socket) do
    %{form: form, node: node, form_types: form_types} = socket.assigns

    case Shared.save_details(form, node, payload.data, form_types) do
      {:ok, form, node} ->
        # A type or property value can change what a flow's health reports
        Health.refresh_for_form(form.id,
          flow_types: socket.assigns.flow_types,
          form_types: form_types
        )

        {:ok,
         socket
         |> assign(
           form: form,
           node: node,
           saved_values: Shared.saved_details(form, node),
           dirty?: false,
           error: nil,
           notice: "Saved."
         )
         |> assign_breadcrumb(node)}

      {:error, reason} ->
        {:ok, assign(socket, error: Shared.save_details_error(form, reason), notice: nil)}
    end
  end

  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:base, fn -> "" end)
      |> assign_new(:user_id, fn -> nil end)
      |> assign_new(:form_id, fn -> nil end)
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
    form = load_form(assigns, node)

    socket
    |> assign(form: form, node: node, dirty?: false)
    |> assign(details(assigns, form, node))
    |> assign_breadcrumb(node)
  end

  # The form the page edits: the one it was addressed with, or the one the
  # step holds. A step whose form has gone, like a page addressed with no
  # form at all, draws nothing.
  defp load_form(%{form_id: form_id}, _node) when not is_nil(form_id), do: Forms.get(form_id)
  defp load_form(_assigns, %{form_id: form_id}) when not is_nil(form_id), do: Forms.get(form_id)
  defp load_form(_assigns, _node), do: nil

  # What the page draws about that form — nothing at all when there is none
  defp details(_assigns, nil, _node),
    do: [form_types: [], pending_type: nil, usages: [], saved_values: nil, form_data: nil]

  defp details(assigns, form, node) do
    form_types = form_types(assigns, form)

    [
      form_types: form_types,
      pending_type: Shared.type_id(form, assigns.form_types),
      usages: Flows.form_usages(form.id),
      saved_values: Shared.saved_details(form, node),
      form_data: Shared.details(form, node, form_types)
    ]
  end

  # The page's form types, with each related-form property's choices filled
  # in for this form's place in its flow. Empty means no dropdown.
  defp form_types(assigns, form) do
    Templates.Shared.fill_related_forms(
      assigns.form_types,
      assigns.root_id,
      assigns.node_id,
      FormFlow.Config.Forms.Type.property_values(form)
    )
  end

  defp assign_breadcrumb(socket, nil), do: assign(socket, root: nil, parent_node: nil)

  defp assign_breadcrumb(socket, node) do
    root = Flows.get(socket.assigns.root_id)

    parent_node =
      if root && node.flow_id != root.id,
        do: Flows.embedding_node(node.flow_id, root.id)

    assign(socket, root: root, parent_node: parent_node)
  end

  # The raw param, not the applied changeset data: a type the admin just
  # picked is a change to act on before the changeset has cast it. A blank
  # keeps the current type, so the "can't be blank" error stays on screen.
  defp pending_type(%{changeset: %{params: %{"form_type" => value}}}, _current)
       when value not in [nil, ""],
       do: value

  defp pending_type(_payload, current), do: current

  # Switching the type dropdown re-renders the property fields, and
  # DynamicForm rebuilds a form whose fields changed from its data — so at
  # that moment the data becomes the pending values, and what the admin was
  # typing survives
  defp reset_form_data_on_switch(socket, pending_type, payload) do
    if pending_type == socket.assigns.form_data[:form_type] do
      socket
    else
      form_data =
        Shared.switch_type(
          payload.data,
          socket.assigns.form,
          pending_type,
          socket.assigns.form_types
        )

      assign(socket, :form_data, form_data)
    end
  end

  defp saved(payload, component_id) do
    Phoenix.LiveView.send_update(__MODULE__, %{
      id: component_id,
      event: "save",
      payload: payload
    })
  end

  # DynamicForm's on_change hook: a report of the current values so
  # dirtiness can drive the Save button
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
        <:metadata>Form details</:metadata>
        <:crumb>
          <.link navigate={show_path(assigns)} class="hover:underline">{@form.name}</.link>
        </:crumb>
        <:actions :if={@root}>
          <FormFlow.Web.Templates.Components.Health.health base={@base} flow={@root} components={@components} />
        </:actions>
        <:actions>
          <%!-- The remote submit: an HTML form= reference into the
                DynamicForm below, so Save lives in the header like every
                other page's primary action, and goes primary with unsaved
                edits --%>
          <Core.button
            components={@components}
            form={"#{@id}-form-form"}
            class={["btn phx-submit-loading:opacity-75", if(@dirty?, do: "btn-primary", else: "")]}
          >
            Save
          </Core.button>
        </:actions>
      </Header.header>

      <Core.error :if={@error} components={@components}>{@error}</Core.error>
      <Core.alert :if={@notice} kind={:success} components={@components} class="my-3">
        {@notice}
      </Core.alert>

      <%!-- A step editing a catalog form is editing it for every flow that
            uses it — said before the first keystroke --%>
      <CatalogBadge.catalog_badge
        :if={Shared.reusing?(@node, @form)}
        form={@form}
        usages={@usages}
        components={@components}
        class="mb-3"
      />

      <%!-- What a save here reaches, before the fields: every version, at
            once. The form's content goes the other way, through drafts, and
            the form's page is where those are. --%>
      <Note.note class="mb-6">
        These details are shared by every version of this form, published ones included, and
        change the moment they are saved. The form's questions and content are edited in a
        draft, from
        <.link navigate={show_path(assigns)} class="link link-primary font-medium">
          the form's page
        </.link>.
      </Note.note>

      <div class={[
        "max-w-3xl",
        # The Name and Slug row, whose members share the width instead of
        # sizing to their content as a horizontal group's members do
        ~S"[&_[data-dynamic-form-group=name\_and\_slug]>div>*]:grow",
        ~S"[&_[data-dynamic-form-group=name\_and\_slug]>div>*]:min-w-0"
      ]}>
        <DynamicForm.form
          id={"#{@id}-form"}
          data={@form_data}
          hide_submit
          on_change={&changed(&1, @id)}
          on_success={&saved(&1, @id)}
          components={@components || CoreComponents}
        >
          <:field type="html" name="form_details_heading">
            <Shared.section_heading title="Form details">
              What every version of this form shares: its name, slug, description, and type.
            </Shared.section_heading>
          </:field>
          <:group name="name_and_slug" type="horizontal" title={false} />
          <:field
            group="name_and_slug"
            type="text"
            name="name"
            label={Shared.name_label(@node)}
            description={Shared.name_description(@form, @node)}
            required
          />
          <:field
            group="name_and_slug"
            type="text"
            name="slug"
            label={Shared.slug_label(@node)}
            placeholder={Shared.slug_placeholder(@node)}
            description={Shared.slug_description(@form, @node)}
          />
          <:field type="comment" name="description" label="Description" />
          <:field
            :if={@form_types != []}
            type="dropdown"
            name="form_type"
            label="Form type"
            options={Enum.map(@form_types, &{&1.name, &1.id})}
            required
          />
          <%!-- What the picked type does, under its dropdown, so the choice
                explains itself before its properties ask for anything --%>
          <:field :if={@form_types != []} type="html" name="form_type_description">
            <Shared.type_callout type={Templates.Shared.type(@form_types, @pending_type)} />
          </:field>
          <%!-- The pending type's properties (FormFlow.Config.Property), one
                field each; picking another type swaps them --%>
          <:field
            :for={property <- Templates.Shared.properties(@form_types, @pending_type)}
            type={Templates.Shared.field_type(property)}
            input_type={Templates.Shared.input_type(property)}
            name={Templates.Shared.field_name(property)}
            label={property.name}
            description={property.description}
            options={Templates.Shared.field_options(property)}
            required={property.required}
            read_only={Templates.Shared.read_only?(property)}
            default={property.default_value}
          />
        </DynamicForm.form>
      </div>
    </div>
    """
  end

  defp form_base_path(%{node: nil} = assigns), do: "#{assigns.base}/forms/#{assigns.form.id}"

  defp form_base_path(assigns) do
    "#{assigns.base}/flows/#{assigns.root_id}/nodes/#{assigns.node_id}/form"
  end

  defp show_path(assigns) do
    preserve_query_params(form_base_path(assigns), assigns.params, ["mode"])
  end
end
