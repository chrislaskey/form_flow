defmodule FormFlow.Web.Templates.Flows.Index do
  @moduledoc """
  `FormFlow.Web.Templates.Flows.Index` LiveComponent lists flows.

  A `Slab.table` over `FormFlow.Data.Templates.Flows.roots_query/0` — summary
  counts and timestamps, with show and edit actions per row and a link to create a
  new flow. The editor itself lives on those pages, so this one never loads
  the ReactFlow bundle. Slab runs in query mode against the host app's repo,
  so sorting and pagination come from the URL: pass the current `uri` and
  `params` from `handle_params/3` (the `FormFlow.Web.Router` component
  forwards both).

      <.live_component
        module={FormFlow.Web.Templates.Flows.Index}
        id="flows-index"
        uri={@uri}
        params={@params}
      />

  Without a `sort` param the table sorts by creation time, matching
  `Flows.list/0` — injected into the params handed to Slab so pagination
  stays deterministic instead of leaning on unspecified database order.

  The count columns aren't sortable: they are virtual fields populated by
  the query's select, not real columns Slab could compile into `ORDER BY`.

  `base` is the path prefix the flows pages are mounted under, used to build
  the links — with the default `""`, rows link to `/flows/:id`.
  """

  use Phoenix.LiveComponent

  import FormFlow.Web.Helpers.Paths

  alias FormFlow.Data.Repo
  alias FormFlow.Data.Templates.Flows

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:base, fn -> "" end)
      |> assign_new(:uri, fn -> nil end)
      |> assign_new(:params, fn -> %{} end)

    query = Flows.roots_query()

    {:ok,
     socket
     |> assign(:query, query)
     |> assign(:empty?, not Repo.exists?(query))
     |> assign(:table_params, Map.put_new(socket.assigns.params, "sort", "inserted_at"))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="mb-2 flex items-center justify-between gap-4">
        <div class="text-sm font-semibold">
          <.link navigate={templates_path(@base)} class="hover:underline">Templates</.link>
          <span class="text-zinc-400">/</span>
          Flows
        </div>
        <.link
          navigate={"#{@base}/flows/new"}
          class="rounded-md border border-cyan-600 bg-cyan-600 px-2 py-1 text-xs text-white hover:bg-cyan-700"
        >
          New flow
        </.link>
      </div>

      <p :if={@empty?} class="text-sm text-zinc-500">
        No flows yet — create the first one.
      </p>

      <Slab.table
        :if={!@empty?}
        id="flows-table"
        query={@query}
        repo={Repo.repo()}
        uri={@uri}
        params={@table_params}
      >
        <:column :let={flow} field={:name} sortable>
          <.link navigate={"#{@base}/flows/#{flow.id}"} class="hover:underline">
            {flow.name || "Untitled"}
          </.link>
          <span class="block font-mono text-[10px] text-zinc-400">{flow.id}</span>
        </:column>
        <:column :let={flow} field={:label} label="Kind">
          <span class="text-xs text-zinc-500">
            {if flow.label == "subflows", do: "Complex", else: "Simple"}
          </span>
        </:column>
        <:column field={:nodes_count} label="Steps" />
        <:column field={:relationships_count} label="Connections" />
        <:column :let={flow} field={:inserted_at} label="Created" sortable>
          <span class="text-xs text-zinc-500">
            {Calendar.strftime(flow.inserted_at, "%Y-%m-%d %H:%M")}
          </span>
        </:column>
        <:column :let={flow} label="Actions">
          <.link navigate={"#{@base}/flows/#{flow.id}"} class="text-cyan-600 hover:underline">
            Show
          </.link>
          <.link
            navigate={"#{@base}/flows/#{flow.id}/edit"}
            class="ml-3 text-cyan-600 hover:underline"
          >
            Edit
          </.link>
        </:column>
        <:pagination per_page={10} />
      </Slab.table>
    </div>
    """
  end
end
