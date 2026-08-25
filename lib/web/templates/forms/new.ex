defmodule FormFlow.Web.Templates.Forms.New do
  @moduledoc """
  `FormFlow.Web.Templates.Forms.New` LiveComponent creates a catalog form.

  A name and an optional description; creating makes the lineage plus its
  initial blank draft and lands on the form's page. Owned forms are never
  created here — they are auto-created when a flow with form steps is saved.

      <.live_component module={FormFlow.Web.Templates.Forms.New} id="forms-new" />
  """

  use Phoenix.LiveComponent

  alias FormFlow.Data.Templates.Forms

  @impl true
  def mount(socket) do
    {:ok, assign(socket, error: nil)}
  end

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:base, fn -> "" end)
     |> assign_new(:app, fn -> "default" end)}
  end

  @impl true
  def handle_event("create", %{"name" => name} = params, socket) do
    attrs = %{name: name, description: params["description"], app: socket.assigns.app}

    case Forms.create(attrs) do
      {:ok, form} ->
        {:noreply, push_navigate(socket, to: "#{socket.assigns.base}/forms/#{form.id}")}

      {:error, %Ecto.Changeset{errors: errors}} ->
        message =
          if Keyword.has_key?(errors, :app),
            do: "A form with that name already exists.",
            else: "Could not create the form. Please try again."

        {:noreply, assign(socket, :error, message)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="mb-2 flex items-center justify-between gap-4">
        <h2 class="text-sm font-semibold">New form</h2>
        <.link
          navigate={"#{@base}/forms"}
          class="rounded-md border border-zinc-300 px-2 py-1 text-xs hover:border-zinc-400"
        >
          Cancel
        </.link>
      </div>

      <p :if={@error} class="mb-2 text-xs text-red-600">{@error}</p>

      <form phx-submit="create" phx-target={@myself} class="max-w-md space-y-4">
        <label class="block">
          <span class="text-xs font-medium text-zinc-600">Name</span>
          <input
            type="text"
            name="name"
            value="Untitled form"
            required
            class="mt-1 w-full rounded-md border border-zinc-300 px-2 py-1 text-sm"
          />
        </label>

        <label class="block">
          <span class="text-xs font-medium text-zinc-600">Description</span>
          <textarea
            name="description"
            rows="3"
            class="mt-1 w-full rounded-md border border-zinc-300 px-2 py-1 text-sm"
          ></textarea>
        </label>

        <button
          type="submit"
          class="rounded-md border border-cyan-600 bg-cyan-600 px-3 py-1.5 text-xs text-white hover:bg-cyan-700"
        >
          Create form
        </button>
      </form>
    </div>
    """
  end
end
