defmodule FormFlow.Web.Templates.Flows.New do
  @moduledoc """
  `FormFlow.Web.Templates.Flows.New` LiveComponent creates a flow.

  A flow's flavor is declared up front and is immutable after, so this page is
  the chooser: a name and the forms-or-subflows decision. Creating seeds the
  flow with `FormFlow.Data.Templates.Flows.starter_nodes/0` (a pinned Start and End)
  and lands on the edit page — the canvas lives there, not here.

      <.live_component module={FormFlow.Web.Templates.Flows.New} id="flows-new" />

  `base` is the path prefix the flows pages are mounted under, used to build
  navigation targets — with the default `""`, creating navigates to
  `/flows/:id/edit`.
  """

  use Phoenix.LiveComponent

  import FormFlow.Web.Helpers.Paths

  alias FormFlow.Data.Templates.Flows

  @impl true
  def mount(socket) do
    {:ok, assign(socket, error: nil)}
  end

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:base, fn -> "" end)}
  end

  @impl true
  def handle_event("create", %{"name" => name, "label" => label}, socket) do
    attrs = %{name: name, label: label, nodes: Flows.starter_nodes(), relationships: []}

    case Flows.create(attrs) do
      {:ok, flow} ->
        {:noreply, push_navigate(socket, to: "#{socket.assigns.base}/flows/#{flow.id}/edit")}

      {:error, %Ecto.Changeset{}} ->
        {:noreply, assign(socket, :error, "Could not create the flow. Please try again.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="mb-2 flex items-center justify-between gap-4">
        <div class="text-sm font-semibold">
          <.link navigate={templates_path(@base)} class="hover:underline">Templates</.link>
          <span class="text-zinc-400">/</span>
          <.link navigate={"#{@base}/flows"} class="hover:underline">Flows</.link>
          <span class="text-zinc-400">/</span>
          New flow
        </div>
        <.link
          navigate={"#{@base}/flows"}
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
            value="Untitled flow"
            required
            class="mt-1 w-full rounded-md border border-zinc-300 px-2 py-1 text-sm"
          />
        </label>

        <fieldset class="space-y-2">
          <legend class="text-xs font-medium text-zinc-600">What kind of flow?</legend>

          <label class="flex items-start gap-2 rounded-md border border-zinc-300 p-3 text-sm">
            <input type="radio" name="label" value="forms" checked class="mt-0.5" />
            <span>
              <span class="font-medium">Simple flow</span>
              <span class="block text-xs text-zinc-500">
                A single flow with one or more forms
              </span>
            </span>
          </label>

          <label class="flex items-start gap-2 rounded-md border border-zinc-300 p-3 text-sm">
            <input type="radio" name="label" value="subflows" class="mt-0.5" />
            <span>
              <span class="font-medium">Complex flow</span>
              <span class="block text-xs text-zinc-500">
                A complex flow with one or more subflows
              </span>
            </span>
          </label>
        </fieldset>

        <button
          type="submit"
          class="rounded-md border border-cyan-600 bg-cyan-600 px-3 py-1.5 text-xs text-white hover:bg-cyan-700"
        >
          Create flow
        </button>
      </form>
    </div>
    """
  end
end
