defmodule FormFlow.Web.Templates.Forms.New do
  @moduledoc """
  `FormFlow.Web.Templates.Forms.New` LiveComponent creates a catalog form.

  A name and an optional description, rendered and validated by
  `DynamicForm.form` with declarative `<:field>` slots. Creating makes the
  lineage plus its initial blank draft and lands on the form's page. Owned
  forms are never created here — they are auto-created when a flow with form
  steps is saved.

  DynamicForm's default success message targets a LiveView's `handle_info/2`;
  this is a LiveComponent, so `on_success` routes the payload back here
  through `send_update/2` and the `%{event: "create"}` clause of `update/2`
  does the side effect.

      <.live_component module={FormFlow.Web.Templates.Forms.New} id="forms-new" />
  """

  use Phoenix.LiveComponent

  import FormFlow.Web.Helpers.Paths

  alias FormFlow.Data.Templates.Forms

  @impl true
  def mount(socket) do
    {:ok, assign(socket, error: nil)}
  end

  @impl true
  def update(%{event: "create", payload: payload}, socket) do
    attrs = %{
      name: payload.data[:name],
      description: payload.data[:description],
      tenant_id: socket.assigns.tenant_id
    }

    case Forms.create(attrs) do
      {:ok, form} ->
        # Redirects are forbidden inside update/2; handle_async is the
        # component-owned callback where they are allowed
        to = "#{socket.assigns.base}/forms/#{form.id}"
        {:ok, start_async(socket, :navigate, fn -> to end)}

      {:error, %Ecto.Changeset{errors: errors}} ->
        message =
          if Keyword.has_key?(errors, :name),
            do: "A form with that name already exists.",
            else: "Could not create the form. Please try again."

        {:ok, assign(socket, :error, message)}
    end
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:base, fn -> "" end)
     |> assign_new(:tenant_id, fn -> nil end)}
  end

  @impl true
  def handle_async(:navigate, {:ok, to}, socket) do
    {:noreply, push_navigate(socket, to: to)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="mb-2 flex items-center justify-between gap-4">
        <div class="text-sm font-semibold">
          <.link navigate={templates_path(@base)} class="hover:underline">Templates</.link>
          <span class="text-zinc-400">/</span>
          <.link navigate={"#{@base}/forms"} class="hover:underline">Forms</.link>
          <span class="text-zinc-400">/</span>
          New form
        </div>
        <.link
          navigate={"#{@base}/forms"}
          class="rounded-md border border-zinc-300 px-2 py-1 text-xs hover:border-zinc-400"
        >
          Cancel
        </.link>
      </div>

      <p :if={@error} class="mb-2 text-xs text-red-600">{@error}</p>

      <div class="max-w-md">
        <DynamicForm.form
          id={"#{@id}-form"}
          submit_text="Create form"
          on_success={&created(&1, @id)}
        >
          <:field type="text" name="name" label="Name" default="Untitled form" required />
          <:field type="comment" name="description" label="Description" />
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
