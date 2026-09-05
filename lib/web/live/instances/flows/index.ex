defmodule FormFlow.Web.Instances.Flows.Index do
  @moduledoc """
  `FormFlow.Web.Instances.Flows.Index` LiveComponent lists the current user's
  flow instances and starts new ones.

  A `Slab.table` over `FormFlow.Data.Instances.Flows.list_query/1`, the same
  way the template indexes are built: Slab runs in query mode against the host
  app's repo, so sorting and pagination come from the URL — pass the current
  `uri` and `params` from `handle_params/3` (the `FormFlow.Web.Router`
  component forwards both).

      <.live_component
        module={FormFlow.Web.Instances.Flows.Index}
        id="instance-flows-index"
        user_id="the-current-user"
        uri={@uri}
        params={@params}
      />

  Without a `sort` param the table sorts newest first, matching
  `FormFlow.Data.Instances.Flows.list/1` — injected into the params handed to
  Slab so pagination stays deterministic instead of leaning on unspecified
  database order.

  The flow's name comes from the `:flow` association, which Slab preloads
  *after* filtering, sorting, and counting, so it is deliberately not sortable
  — it is a joined value, not a column Slab could compile into `ORDER BY`.

  "The current user" means the router's `user_id` attr: by default the list
  is narrowed to instances that user created, and starting one stamps them as
  its creator. The host decides otherwise through the `instances` attr — a
  reviewer's page passes `Instances.Flows.list_query()` bare to list
  everyone's. Which flow templates the page is about is the `flows` attr:
  the flows it offers to start, refusing to start any other, and — when the
  host names some in particular and leaves `instances` to its default — the
  flows whose instances the default listing shows, so a page for Dog License
  lists the user's Dog License instances and not their renewals. `nil` is
  every root flow of the tenant, offered and listed alike; a host that wants
  to list one thing and start another passes `instances` itself. The
  router's `tenant_id` is applied on top of both. This is a listing
  convenience, not access control: the page asks the host's `on_mount`
  before it draws, like every other user-facing page, and auth stays the
  host's job (see `FormFlow.Web.Router`).

  Starting a new flow stays a plain list rather than a second table: Slab
  reads `sort` and `page` straight from the URL, so two Slab tables on one
  page would share — and fight over — the same params.

  ## The states it draws

  No instance is in scope here, so the page asks the narrower
  `FormFlow.Web.Instances.Shared.page_state/1` and draws three states, each
  in its own `render/1` clause and with no catch-all:

    * `:redirecting` — nothing, while the host's `on_mount` navigates away
    * `:refused` — the host's message alone
    * `:ready` — the listing, and the flows it offers to start

  Start needs both rules: the state, and then that the flow is one the page
  offered. The state is not redundant. A refused viewer has no
  `:page_flows` at all — the listing is built inside the gate's `on_ok`, so
  it is never assigned — and the second rule alone would crash on the
  missing assign. It also covers the case where assigns outlive their
  decision: they persist across `update/2`, so a gate that allows on mount
  and refuses later would otherwise leave the earlier listing standing.
  """

  use Phoenix.LiveComponent

  alias FormFlow.Config.Flows.Perspective
  alias FormFlow.Context
  alias FormFlow.Data.Instances
  alias FormFlow.Data.Repo
  alias FormFlow.Web.Components.Core
  alias FormFlow.Web.Instances.Forms.Shared
  alias FormFlow.Web.Instances.Paths

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:base, fn -> "" end)
      |> assign_new(:tenant_id, fn -> nil end)
      |> assign_new(:perspectives, fn -> [] end)
      |> assign_new(:flow_types, fn -> FormFlow.Config.Flows.Type.defaults() end)
      |> assign_new(:form_types, fn -> FormFlow.Config.Forms.Type.defaults() end)
      |> assign_new(:callback_data, fn -> %{} end)
      |> assign_new(:components, fn -> nil end)
      |> assign_new(:on_mount, fn -> nil end)
      |> assign_new(:instances, fn -> nil end)
      |> assign_new(:flows, fn -> nil end)
      |> assign_new(:download_path, fn -> nil end)
      |> assign_new(:uri, fn -> nil end)
      |> assign_new(:params, fn -> %{} end)
      |> assign_new(:error, fn -> nil end)

    # The listing's context: the user and tenant, no flow in scope
    context = %Context{
      user_id: socket.assigns.user_id,
      tenant_id: socket.assigns.tenant_id,
      perspectives: Perspective.normalize(socket.assigns.perspectives)
    }

    {:ok,
     socket
     |> assign(context: context, mount_error: nil, navigate_to: nil)
     |> Shared.on_mount(&load/1)
     |> assign_page_state()}
  end

  # The state the page is in, computed once the gate has answered. Unlike
  # the other three pages this one does not load *then* ask: its load is the
  # gate's `on_ok`, so a refused viewer never has a listing built for them
  # at all. Making this page "look like the others" would undo that —
  # `:page_flows` would be assigned before the refusal, and Start's second
  # rule would be checking a list the viewer was refused.
  defp assign_page_state(socket) do
    assign(socket, :page_state, FormFlow.Web.Instances.Shared.page_state(socket.assigns))
  end

  # The listing itself, built only once the host allowed the page: the
  # host's query and the host's flows to start — or the defaults, the user's
  # own and every root of the tenant — each narrowed to the router's tenant.
  # The resolved flows live under `:page_flows` so the host's `flows` stays
  # what it said, render after render.
  defp load(socket) do
    %{user_id: user_id, tenant_id: tenant_id} = socket.assigns

    page_flows = Shared.resolve_flows(socket.assigns.flows, tenant_id)

    query =
      (socket.assigns.instances || own_query(user_id, socket.assigns.flows, page_flows))
      |> Instances.Flows.narrow_tenant(tenant_id)

    socket
    |> assign(:query, query)
    |> assign(:empty?, not Repo.exists?(query))
    |> assign(:page_flows, page_flows)
    |> assign(:table_params, table_params(socket.assigns.params))
  end

  # The default listing is the user's own: of every flow when the host named
  # none in particular, of the page's flows when it did
  defp own_query(user_id, nil, _page_flows), do: Instances.Flows.list_query(user_id: user_id)

  defp own_query(user_id, _named, page_flows),
    do: Instances.Flows.list_query(user_id: user_id, flow: page_flows)

  @impl true
  def handle_async(:navigate, {:ok, to}, socket) do
    {:noreply, push_navigate(socket, to: to)}
  end

  # Both rules. The state says whether the page may act at all — and a
  # refused viewer has no `:page_flows` to check, since the listing is built
  # inside the gate's `on_ok` — and then only a flow the page offered can be
  # started from it.
  @impl true
  def handle_event("start", %{"flow-id" => flow_id}, socket)
      when socket.assigns.page_state == :ready do
    if Enum.any?(socket.assigns.page_flows, &(&1.id == flow_id)) do
      start(socket, flow_id)
    else
      {:noreply, assign(socket, :error, "That flow is not available here.")}
    end
  end

  # A refused event is silent: the client was not driving a rendered
  # control, and a message would describe the gate to whoever was probing
  # it. Only a well-formed one, though — the params are matched here too, so
  # a "start" carrying no flow is as much a `FunctionClauseError` as an
  # event name nothing answers to. Silence is for a refusal, not for a
  # message this page does not understand.
  def handle_event("start", %{"flow-id" => _flow_id}, socket), do: {:noreply, socket}

  defp start(socket, flow_id) do
    attrs = %{
      flow_id: flow_id,
      user_id: socket.assigns.user_id,
      tenant_id: socket.assigns.tenant_id
    }

    case Instances.Flows.create(attrs) do
      {:ok, flow_instance} ->
        to = Paths.flow_path(socket.assigns.base, flow_instance.id)
        {:noreply, push_navigate(socket, to: to)}

      {:error, _changeset} ->
        {:noreply, assign(socket, :error, "Could not start the flow. Please try again.")}
    end
  end

  # The listing's status column, as `{text, kind}` — the wording the flow
  # instance pages use for the same two states, in the same palette as a
  # form's own badge (`FormFlow.Web.Instances.Components.Flows.Progress.badge/1`).
  defp status_badge("completed"), do: {"Completed", :success}
  defp status_badge(_in_progress), do: {"In progress", :warning}

  # Newest first by default. Only injected when the URL carries no sort of its
  # own, so clicking any header still starts ascending like every other
  # column — a bare `sort_direction` default would flip that.
  defp table_params(%{"sort" => _chosen} = params), do: params

  defp table_params(params) do
    Map.merge(params, %{"sort" => "inserted_at", "sort_direction" => "desc"})
  end

  # The host's on_mount is sending the user elsewhere: nothing to draw meanwhile
  @impl true
  def render(%{page_state: :redirecting} = assigns) do
    ~H"""
    <div></div>
    """
  end

  # The host's on_mount refused the page; its message is all there is to draw
  def render(%{page_state: :refused} = assigns) do
    ~H"""
    <div>
      <div class="mb-4 flex min-h-12 items-center text-base font-semibold">
        Flows
      </div>

      <Core.alert components={@components}>{@mount_error}</Core.alert>
    </div>
    """
  end

  # The listing, and the flows it offers to start. There is no catch-all
  # clause: a state nobody accounted for raises here rather than drawing the
  # page to whoever reached it.
  def render(%{page_state: :ready} = assigns) do
    ~H"""
    <div>
      <div class="mb-4 flex min-h-12 items-center text-base font-semibold">
        Flows
      </div>

      <Core.error :if={@error} components={@components}>{@error}</Core.error>

      <Core.alert :if={@empty?} components={@components} class="mb-4">
        Nothing started yet — start a flow below.
      </Core.alert>

      <Slab.table
        :if={!@empty?}
        id="flow-instances-table"
        query={@query}
        repo={Repo.repo()}
        preload={[:flow]}
        uri={@uri}
        params={@table_params}
      >
        <:column :let={flow_instance} label="Flow">
          <.link
            navigate={Paths.flow_path(@base, flow_instance.id)}
            class="hover:underline"
          >
            {flow_instance.flow.name || "Untitled flow"}
          </.link>
        </:column>
        <:column :let={flow_instance} field={:status} sortable>
          <% {text, kind} = status_badge(flow_instance.status) %>
          <Core.badge components={@components} kind={kind}>{text}</Core.badge>
        </:column>
        <:column :let={flow_instance} field={:inserted_at} label="Started" sortable>
          <span class="text-base-content/60">
            {Calendar.strftime(flow_instance.inserted_at, "%Y-%m-%d %H:%M")}
          </span>
        </:column>
        <:column :let={flow_instance} label="Actions">
          <Core.button
            components={@components}
            navigate={Paths.flow_path(@base, flow_instance.id)}
            variant="primary"
          >
            {if flow_instance.status == "completed", do: "View →", else: "Continue →"}
          </Core.button>
        </:column>
        <:pagination per_page={10} />
      </Slab.table>

      <h3 class="mb-2 mt-8 text-base font-semibold">Start a new flow</h3>
      <Core.alert :if={@page_flows == []} components={@components}>
        No flows have been published yet.
      </Core.alert>
      <ul class="divide-y divide-base-300 text-base">
        <li :for={flow <- @page_flows} class="flex flex-wrap items-center gap-3 py-3">
          <span>{flow.name || "Untitled flow"}</span>
          <Core.button
            components={@components}
            phx-click="start"
            phx-value-flow-id={flow.id}
            phx-target={@myself}
            variant="primary"
            class="ml-auto"
          >
            Start
          </Core.button>
        </li>
      </ul>
    </div>
    """
  end
end
