defmodule FormFlow.Web.Templates.Flows.New do
  @moduledoc """
  `FormFlow.Web.Templates.Flows.New` LiveComponent creates a flow.

  A flow's flavor is declared up front and is immutable after, so this page is
  the chooser: a name and the forms-or-subflows decision. Creating seeds the
  flow with `FormFlow.Data.Templates.Flows.starter_nodes/0` (a Start and End that
  cannot be deleted) and lands on the edit page - the canvas lives there, not here.

      <.live_component module={FormFlow.Web.Templates.Flows.New} id="flows-new" />

  The page is three decisions wide rather than a column of them: Name and
  Slug share a row (`DynamicForm`'s horizontal group), and the kind is a row
  of choice cards - the same `FormFlow.Web.Templates.Components.ChoiceCard`
  the form editor picks its editor with, for the same reason: the kind
  decides what the flow can hold ever after, and a card has the second line
  that consequence needs. **Create flow** sits in the header beside Cancel,
  reaching the form below by an HTML `form=` reference, so the primary action
  is where every other page keeps it. Cancel asks first - there is no draft
  here to come back to, so leaving loses whatever was typed.

  DynamicForm's default success message targets a LiveView's `handle_info/2`;
  this is a LiveComponent, so `on_success` routes the payload back here
  through `send_update/2` and the `%{event: "create"}` clause of `update/2`
  does the side effect.

  `base` is the path prefix the flows pages are mounted under, used to build
  navigation targets - with the default `""`, creating navigates to
  `/flows/:id/edit`.
  """

  use Phoenix.LiveComponent

  alias FormFlow.Data.Templates.Flows
  alias FormFlow.Web.Components.Core
  alias FormFlow.Web.CoreComponents
  alias FormFlow.Web.Templates.Components.ChoiceCard
  alias FormFlow.Web.Templates.Components.Header
  alias FormFlow.Web.Templates

  # What a flow can hold, which is fixed the moment it is created: the
  # `label` column's two values, and what each one means for the flow after.
  @kinds [
    %{
      value: "forms",
      label: "Simple flow",
      description: "A single flow with one or more forms"
    },
    %{
      value: "subflows",
      label: "Complex flow",
      description: "A complex flow with one or more subflows"
    }
  ]

  @impl true
  def mount(socket) do
    {:ok, assign(socket, error: nil)}
  end

  @impl true
  def update(%{event: "create", payload: payload}, socket) do
    attrs = %{
      name: payload.data[:name],
      label: payload.data[:label],
      slug: payload.data[:slug],
      tenant_id: socket.assigns.tenant_id,
      nodes: Flows.starter_nodes(),
      relationships: []
    }

    case Flows.create(attrs, user_id: socket.assigns.user_id) do
      {:ok, flow} ->
        # The one save a new flow has had: its badge reads what it is -
        # Start and End, unwired - rather than "not checked"
        FormFlow.Data.Templates.Flows.Health.refresh(flow,
          flow_types: socket.assigns.flow_types,
          form_types: socket.assigns.form_types
        )

        # Redirects are forbidden inside update/2; handle_async is the
        # component-owned callback where they are allowed
        to = "#{socket.assigns.base}/flows/#{flow.id}/edit"
        {:ok, start_async(socket, :navigate, fn -> to end)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:ok,
         assign(
           socket,
           :error,
           Templates.Shared.save_error(changeset, "Could not create the flow. Please try again.")
         )}
    end
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:base, fn -> "" end)
     |> assign_new(:user_id, fn -> nil end)
     |> assign_new(:tenant_id, fn -> nil end)
     |> assign_new(:flow_types, fn -> FormFlow.Config.Flows.Type.defaults() end)
     |> assign_new(:form_types, fn -> FormFlow.Config.Forms.Type.defaults() end)
     |> assign_new(:components, fn -> nil end)}
  end

  @impl true
  def handle_async(:navigate, {:ok, to}, socket) do
    {:noreply, push_navigate(socket, to: to)}
  end

  # The kind, drawn as cards rather than a row of radios - still the form's
  # own radio group, with the `<:field>` body taking over the control while
  # DynamicForm keeps the label, the errors, and the changeset
  attr(:field, :any, required: true)

  defp kind_cards(assigns) do
    ~H"""
    <div class="grid grid-cols-1 gap-2 sm:grid-cols-2">
      <ChoiceCard.choice_card
        :for={kind <- kinds()}
        id={"#{@field.id}-#{kind.value}"}
        name={@field.name}
        value={kind.value}
        checked={to_string(@field.value) == kind.value}
        label={kind.label}
      >
        {kind.description}
      </ChoiceCard.choice_card>
    </div>
    """
  end

  defp kinds, do: @kinds

  defp kind_options, do: Enum.map(@kinds, &{&1.label, &1.value})

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <Header.header base={@base} section="flows" name="New flow" components={@components}>
        <:actions>
          <%!-- Nothing has been written yet, so leaving is not a discard of
                something saved - but it is the loss of what was typed, and
                the page asks the way a delete does --%>
          <Core.button
            components={@components}
            navigate={"#{@base}/flows"}
            class="btn"
            data-confirm="Leave without creating this flow? Nothing here is saved."
          >
            Cancel
          </Core.button>
          <%!-- The remote submit: an HTML form= reference into the
                DynamicForm below, so Create flow sits in the header like
                every other page's primary action --%>
          <Core.button components={@components} form={"#{@id}-form-form"} variant="primary">
            Create flow
          </Core.button>
        </:actions>
      </Header.header>

      <Core.error :if={@error} components={@components}>{@error}</Core.error>

      <div class="max-w-5xl">
        <DynamicForm.form
          id={"#{@id}-form"}
          hide_submit
          on_success={&created(&1, @id)}
          components={@components || CoreComponents}
        >
          <%!-- Neither field carries help text: a horizontal group centers
                its members, so one description under one field would leave
                the other half a line low, and the two labels say enough on
                a page whose whole job is a name and a kind. --%>
          <:group name="name_and_slug" type="horizontal" title={false} />
          <:field
            group="name_and_slug"
            type="text"
            name="name"
            label="Name"
            default="Untitled flow"
            required
          />
          <:field
            group="name_and_slug"
            type="text"
            name="slug"
            label="Slug"
            placeholder="Generated when left blank"
          />
          <:field
            :let={field}
            type="radiogroup"
            name="label"
            label="What kind of flow?"
            options={kind_options()}
            default="forms"
            required
          >
            <.kind_cards field={field} />
          </:field>
        </DynamicForm.form>
      </div>
    </div>
    """
  end

  defp created(payload, component_id) do
    Phoenix.LiveView.send_update(__MODULE__, %{
      id: component_id,
      event: "create",
      payload: payload
    })
  end
end
