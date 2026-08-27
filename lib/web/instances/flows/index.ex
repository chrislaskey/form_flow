defmodule FormFlow.Web.Instances.Flows.Index do
  @moduledoc """
  `FormFlow.Web.Instances.Flows.Index` LiveComponent lists the current user's
  flow instances and starts new ones.

  "The current user" means the router's `user_id` attr: the list is narrowed
  to instances that user created, and starting one stamps them as its
  creator. This is a listing convenience, not access control — auth stays the
  host's job (see `FormFlow.Web.Router`).
  """

  use Phoenix.LiveComponent

  alias FormFlow.Data.Instances
  alias FormFlow.Data.Repo
  alias FormFlow.Data.Templates
  alias FormFlow.Web.Instances.Paths

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:base, fn -> "" end)

    flows =
      Repo.all(Templates.Flows.roots_query())
      |> Enum.reject(& &1.made_reusable_at)

    {:ok,
     socket
     |> assign(:flow_instances, Instances.Flows.list(user_id: socket.assigns.user_id))
     |> assign(:flows, flows)
     |> assign_new(:error, fn -> nil end)}
  end

  @impl true
  def handle_event("start", %{"flow-id" => flow_id}, socket) do
    attrs = %{flow_id: flow_id, user_id: socket.assigns.user_id}

    case Instances.Flows.create(attrs) do
      {:ok, flow_instance} ->
        to = Paths.flow_path(socket.assigns.base, flow_instance.id)
        {:noreply, push_navigate(socket, to: to)}

      {:error, _changeset} ->
        {:noreply, assign(socket, :error, "Could not start the flow. Please try again.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="mb-2 text-sm font-semibold">
        Flows
      </div>

      <p :if={@error} class="mb-2 text-xs text-red-600">{@error}</p>

      <div :if={@flow_instances == []} class="mb-4 text-sm text-zinc-500">
        Nothing started yet — start a flow below.
      </div>

      <table :if={@flow_instances != []} class="mb-6 w-full text-left text-sm">
        <thead>
          <tr class="border-b border-zinc-200 text-xs uppercase text-zinc-500">
            <th class="py-1 pr-4">Flow</th>
            <th class="py-1 pr-4">Status</th>
            <th class="py-1 pr-4">Started</th>
            <th class="py-1"></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={flow_instance <- @flow_instances} class="border-b border-zinc-100">
            <td class="py-1.5 pr-4">{flow_instance.flow.name || "Untitled flow"}</td>
            <td class="py-1.5 pr-4">{flow_instance.status}</td>
            <td class="py-1.5 pr-4 text-zinc-500">
              {Calendar.strftime(flow_instance.inserted_at, "%Y-%m-%d")}
            </td>
            <td class="py-1.5 text-right">
              <.link
                navigate={Paths.flow_path(@base, flow_instance.id)}
                class="text-cyan-600 hover:underline"
              >
                Open →
              </.link>
            </td>
          </tr>
        </tbody>
      </table>

      <h3 class="mb-1 text-sm font-semibold">Start a new flow</h3>
      <p :if={@flows == []} class="text-sm text-zinc-500">
        No flows have been published yet.
      </p>
      <ul class="space-y-1 text-sm">
        <li :for={flow <- @flows} class="flex items-center gap-3">
          <span>{flow.name || "Untitled flow"}</span>
          <button
            phx-click="start"
            phx-value-flow-id={flow.id}
            phx-target={@myself}
            class="rounded-md border border-zinc-300 px-2 py-0.5 text-xs hover:border-zinc-400"
          >
            Start
          </button>
        </li>
      </ul>
    </div>
    """
  end
end
