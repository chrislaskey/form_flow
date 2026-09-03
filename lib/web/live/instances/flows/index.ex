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
  its creator. The host's config decides otherwise through
  `FormFlow.Config.flow_instances_query/2` — a reviewer's desk lists
  everyone's — and the router's `tenant_id` is applied on top of whatever it
  answers. This is a listing convenience, not access control: the page asks
  `FormFlow.Config.handle_instance_mount/2` before it draws, like every other
  user-facing page, and auth stays the host's job (see `FormFlow.Web.Router`).

  Starting a new flow stays a plain list rather than a second table: Slab
  reads `sort` and `page` straight from the URL, so two Slab tables on one
  page would share — and fight over — the same params.
  """

  use Phoenix.LiveComponent

  alias FormFlow.Context
  alias FormFlow.Data.Instances
  alias FormFlow.Data.Repo
  alias FormFlow.Data.Templates
  alias FormFlow.Web.Instances.Components
  alias FormFlow.Web.Instances.Forms.Shared
  alias FormFlow.Web.Instances.Paths

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:base, fn -> "" end)
      |> assign_new(:tenant_id, fn -> nil end)
      |> assign_new(:config, fn -> nil end)
      |> assign_new(:config_data, fn -> %{} end)
      |> assign_new(:uri, fn -> nil end)
      |> assign_new(:params, fn -> %{} end)
      |> assign_new(:error, fn -> nil end)

    # The listing's context: the user and tenant, no flow in scope
    context = %Context{user_id: socket.assigns.user_id, tenant_id: socket.assigns.tenant_id}

    {:ok,
     socket
     |> assign(context: context, mount_error: nil, navigate_to: nil)
     |> Shared.handle_instance_mount(&load/1)}
  end

  # The listing itself, built only once the config allowed the page: the
  # host's query narrowed to the router's tenant, and the flows to start
  defp load(socket) do
    %{context: context, config: config, config_data: config_data} = socket.assigns

    query =
      FormFlow.Config.config_module(config).flow_instances_query(context, config_data)
      |> Instances.Flows.narrow_tenant(socket.assigns.tenant_id)

    flows =
      Repo.all(Templates.Flows.roots_query(tenant_id: socket.assigns.tenant_id))
      |> Enum.reject(& &1.made_reusable_at)

    socket
    |> assign(:query, query)
    |> assign(:empty?, not Repo.exists?(query))
    |> assign(:flows, flows)
    |> assign(:table_params, table_params(socket.assigns.params))
  end

  @impl true
  def handle_async(:navigate, {:ok, to}, socket) do
    {:noreply, push_navigate(socket, to: to)}
  end

  @impl true
  def handle_event("start", %{"flow-id" => flow_id}, socket) do
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

  # Newest first by default. Only injected when the URL carries no sort of its
  # own, so clicking any header still starts ascending like every other
  # column — a bare `sort_direction` default would flip that.
  defp table_params(%{"sort" => _chosen} = params), do: params

  defp table_params(params) do
    Map.merge(params, %{"sort" => "inserted_at", "sort_direction" => "desc"})
  end

  # The host's config is sending the user elsewhere: nothing to draw meanwhile
  @impl true
  def render(%{navigate_to: to} = assigns) when is_binary(to) do
    ~H"""
    <div></div>
    """
  end

  # The host's config refused the page; its message is all there is to draw
  def render(%{mount_error: message} = assigns) when is_binary(message) do
    ~H"""
    <div>
      <div class="mb-2 text-sm font-semibold">
        Flows
      </div>

      <Components.FormPage.notice message={@mount_error} />
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div>
      <div class="mb-2 text-sm font-semibold">
        Flows
      </div>

      <p :if={@error} class="mb-2 text-xs text-red-600">{@error}</p>

      <p :if={@empty?} class="mb-4 text-sm text-zinc-500">
        Nothing started yet — start a flow below.
      </p>

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
          <span class="text-xs text-zinc-500">{flow_instance.status}</span>
        </:column>
        <:column :let={flow_instance} field={:inserted_at} label="Started" sortable>
          <span class="text-xs text-zinc-500">
            {Calendar.strftime(flow_instance.inserted_at, "%Y-%m-%d %H:%M")}
          </span>
        </:column>
        <:column :let={flow_instance} label="Actions">
          <.link
            navigate={Paths.flow_path(@base, flow_instance.id)}
            class="text-cyan-600 hover:underline"
          >
            {if flow_instance.status == "completed", do: "View →", else: "Continue →"}
          </.link>
        </:column>
        <:pagination per_page={10} />
      </Slab.table>

      <h3 class="mb-1 mt-6 text-sm font-semibold">Start a new flow</h3>
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
