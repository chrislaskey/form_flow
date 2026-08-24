defmodule FormFlow.Web.Templates.Flows.Index do
  @moduledoc """
  `FormFlow.Web.Templates.Flows.Index` LiveComponent lists flows.

  A plain table of the graphs `FormFlow.Data.Graphs.list/0` returns — summary
  counts and timestamps, with show and edit actions per row and a link to
  create a new flow. The editor itself lives on those pages, so this one never
  loads the ReactFlow bundle.

      <.live_component module={FormFlow.Web.Templates.Flows.Index} id="flows-index" />

  `base` is the path prefix the flows pages are mounted under, used to build
  the links — with the default `""`, rows link to `/flows/:id`.
  """

  use Phoenix.LiveComponent

  alias FormFlow.Data.Graphs

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:base, fn -> "" end)
     |> assign(:graphs, Graphs.list())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="mb-2 flex items-center justify-between gap-4">
        <h2 class="text-sm font-semibold">Flows</h2>
        <.link
          navigate={"#{@base}/flows/new"}
          class="rounded-md border border-cyan-600 bg-cyan-600 px-2 py-1 text-xs text-white hover:bg-cyan-700"
        >
          New flow
        </.link>
      </div>

      <p :if={@graphs == []} class="text-sm text-zinc-500">
        No flows yet — create the first one.
      </p>

      <table :if={@graphs != []} class="w-full text-left text-sm">
        <thead>
          <tr class="border-b border-zinc-300 text-xs text-zinc-500">
            <th class="py-2 pr-4 font-medium">Name</th>
            <th class="py-2 pr-4 font-medium">Kind</th>
            <th class="py-2 pr-4 font-medium">Steps</th>
            <th class="py-2 pr-4 font-medium">Connections</th>
            <th class="py-2 pr-4 font-medium">Created</th>
            <th class="py-2 font-medium"><span class="sr-only">Actions</span></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={graph <- @graphs} class="border-b border-zinc-200">
            <td class="py-2 pr-4">
              <.link navigate={"#{@base}/flows/#{graph.id}"} class="hover:underline">
                {graph.name || "Untitled"}
              </.link>
              <span class="block font-mono text-[10px] text-zinc-400">{graph.id}</span>
            </td>
            <td class="py-2 pr-4 text-xs text-zinc-500">
              {if graph.label == "subflows", do: "Complex", else: "Simple"}
            </td>
            <td class="py-2 pr-4">{graph.nodes_count}</td>
            <td class="py-2 pr-4">{graph.relationships_count}</td>
            <td class="py-2 pr-4 text-xs text-zinc-500">
              {Calendar.strftime(graph.inserted_at, "%Y-%m-%d %H:%M")}
            </td>
            <td class="py-2 text-right whitespace-nowrap">
              <.link
                navigate={"#{@base}/flows/#{graph.id}"}
                class="text-cyan-600 hover:underline"
              >
                Show
              </.link>
              <.link
                navigate={"#{@base}/flows/#{graph.id}/edit"}
                class="ml-3 text-cyan-600 hover:underline"
              >
                Edit
              </.link>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end
end
