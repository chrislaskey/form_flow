defmodule FormFlow.Web.Templates.Forms.Index do
  @moduledoc """
  `FormFlow.Web.Templates.Forms.Index` LiveComponent lists the form catalog.

  A `Slab.table` over `FormFlow.Data.Templates.Forms.catalog_query/0` —
  owned forms live inside their flow trees and are reached by drill-in,
  never listed here. Slab runs in query mode against the host app's repo,
  so sorting and pagination come from the URL: pass the current `uri` and
  `params` from `handle_params/3` (the `FormFlow.Web.Router` component
  forwards both).

      <.live_component
        module={FormFlow.Web.Templates.Forms.Index}
        id="forms-index"
        uri={@uri}
        params={@params}
      />

  Without a `sort` param the table sorts by creation time, matching
  `Forms.list/1` — injected into the params handed to Slab so pagination
  stays deterministic instead of leaning on unspecified database order.

  `base` is the path prefix the forms pages are mounted under, used to build
  the links — with the default `""`, rows link to `/forms/:id`.
  """

  use Phoenix.LiveComponent

  import FormFlow.Web.Helpers.Paths

  alias FormFlow.Data.Repo
  alias FormFlow.Data.Templates.Forms
  alias FormFlow.Web.Components.Core

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:base, fn -> "" end)
      |> assign_new(:tenant_id, fn -> nil end)
      |> assign_new(:components, fn -> nil end)
      |> assign_new(:uri, fn -> nil end)
      |> assign_new(:params, fn -> %{} end)

    query = Forms.catalog_query(tenant_id: socket.assigns.tenant_id)

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
          Forms
        </div>
        <Core.button components={@components} navigate={"#{@base}/forms/new"} variant="primary">
          New form
        </Core.button>
      </div>

      <Core.alert :if={@empty?} components={@components}>
        No forms yet — create the first one.
      </Core.alert>

      <Slab.table
        :if={!@empty?}
        id="forms-table"
        query={@query}
        repo={Repo.repo()}
        uri={@uri}
        params={@table_params}
      >
        <:column :let={form} field={:name} sortable>
          <.link navigate={"#{@base}/forms/#{form.id}"} class="hover:underline">
            {form.name}
          </.link>
          <span class="block font-mono text-[10px] text-zinc-400">{form.id}</span>
        </:column>
        <:column :let={form} field={:description}>
          <span class="text-xs text-zinc-500">{form.description}</span>
        </:column>
        <:column :let={form} field={:inserted_at} label="Created" sortable>
          <span class="text-xs text-zinc-500">
            {Calendar.strftime(form.inserted_at, "%Y-%m-%d %H:%M")}
          </span>
        </:column>
        <:column :let={form} label="Actions">
          <.link navigate={"#{@base}/forms/#{form.id}"} class="text-cyan-600 hover:underline">
            Show
          </.link>
        </:column>
        <:pagination per_page={10} />
      </Slab.table>
    </div>
    """
  end
end
