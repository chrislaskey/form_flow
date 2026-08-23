defmodule FormFlow.Web.Templates.Flows.New do
  @moduledoc """
  `FormFlow.Web.Templates.Flows.New` LiveComponent creates a flow.

  Renders the editor (see `FormFlow.Web.Components.Editor`) seeded with a
  starter flow, tracks edits as the editor reports them, and on save persists
  the result with `FormFlow.Data.Graphs.create/1` before navigating to the new
  flow's show page.

      <.live_component module={FormFlow.Web.Templates.Flows.New} id="flows-new" />

  `base` is the path prefix the flows pages are mounted under, used to build
  navigation targets — with the default `""`, saving navigates to `/flows/:id`.
  """

  use Phoenix.LiveComponent

  alias FormFlow.Data.Graphs
  alias FormFlow.Web.Components.Editor
  alias FormFlow.Web.Helpers.ReactFlow

  @impl true
  def mount(socket) do
    {:ok, assign(socket, error: nil)}
  end

  @impl true
  def update(assigns, socket) do
    data = Map.get(assigns, :data) || default_data()

    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:base, fn -> "" end)
     |> assign(:data, data)
     |> assign(:current, data)}
  end

  @impl true
  def handle_event("form_flow:editor_mounted", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("form_flow:graph_changed", %{"nodes" => nodes, "edges" => edges}, socket) do
    {:noreply, assign(socket, :current, %{"nodes" => nodes, "edges" => edges})}
  end

  @impl true
  def handle_event("save", _params, socket) do
    case Graphs.create(ReactFlow.to_graph_attrs(socket.assigns.current)) do
      {:ok, graph} ->
        {:noreply, push_navigate(socket, to: "#{socket.assigns.base}/flows/#{graph.id}")}

      {:error, %Ecto.Changeset{}} ->
        {:noreply, assign(socket, :error, "Could not save the flow. Please try again.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="mb-2 flex items-center justify-between gap-4">
        <h2 class="text-sm font-semibold">New flow</h2>
        <div class="flex items-center gap-2">
          <.link
            navigate={"#{@base}/flows"}
            class="rounded-md border border-zinc-300 px-2 py-1 text-xs hover:border-zinc-400"
          >
            Cancel
          </.link>
          <button
            type="button"
            phx-click="save"
            phx-target={@myself}
            class="rounded-md border border-cyan-600 bg-cyan-600 px-2 py-1 text-xs text-white hover:bg-cyan-700"
          >
            Save
          </button>
        </div>
      </div>

      <p :if={@error} class="mb-2 text-xs text-red-600">{@error}</p>

      <Editor.editor id={"#{@id}-editor"} data={@data} target={@myself} />
    </div>
    """
  end

  # The starter flow a new graph begins from, in ReactFlow's own shape — see
  # FormFlow.Web.Helpers.ReactFlow. `deletable: false` pins the start and end
  # steps; every flow needs both, so neither can be removed.
  defp default_data do
    %{
      nodes: [
        %{
          id: "1",
          type: "step",
          position: %{x: 240, y: 0},
          deletable: false,
          data: %{label: "Start", kind: "start", fields: 0}
        },
        %{
          id: "2",
          type: "step",
          position: %{x: 240, y: 140},
          data: %{label: "Form", kind: "form", fields: 4}
        },
        %{
          id: "3",
          type: "step",
          position: %{x: 240, y: 280},
          deletable: false,
          data: %{label: "End", kind: "end", fields: 1}
        }
      ],
      edges: [
        %{id: "e1-2", source: "1", target: "2", markerEnd: %{type: "arrowclosed"}},
        %{id: "e2-3", source: "2", target: "3", markerEnd: %{type: "arrowclosed"}}
      ]
    }
  end
end
