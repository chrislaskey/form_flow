defmodule FormFlow.Web.Instances.Flows.Index do
  @moduledoc """
  `FormFlow.Web.Instances.Flows.Index` LiveComponent lists the current user's
  flow instances and starts new ones.

  A `Slab.table` over `FormFlow.Data.Instances.Flows.list_query/1`, the same
  way the template indexes are built: Slab runs in query mode against the host
  app's repo, so sorting and pagination come from the URL - pass the current
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
  `FormFlow.Data.Instances.Flows.list/1` - injected into the params handed to
  Slab so pagination stays deterministic instead of leaning on unspecified
  database order.

  The flow's name comes from the `:template_flow` association, which Slab
  preloads *after* filtering, sorting, and counting, so it is deliberately not
  sortable - it is a joined value, not a column Slab could compile into
  `ORDER BY`.

  **User ID** is the opposite case and is drawn conditionally. It is the
  journey's own `user_id` column, so Slab sorts it, and it holds the host's
  own id for the user who started the journey - set at creation and
  immutable (`FormFlow.Data.Instances.Flow`). It is drawn only when the host
  passed an `instances` query, because the default listing is the viewer's
  own journeys and the column would repeat the viewer's id on every row. The
  rule is the attr, not the rows: a host query that happens to return one
  user's journeys still gets the column, because the next one it returns may
  be somebody else's.

  The header says "User ID" because that is what the cell holds. The library
  has no users and no names - `user_id` is any principal string the host
  chose, system identities included - so a header promising a person would
  be promising something the library cannot deliver. A host that wants "Sam
  Torres" renders its own column.

  "The current user" means the router's `user_id` attr: by default the list
  is narrowed to instances that user created, and starting one records that user as
  its creator. The host decides otherwise through the `instances` attr - a
  reviewer's page passes `Instances.Flows.list_query()` bare to list
  everyone's. Which flow templates the page is about is the `flows` attr - a
  list of `FormFlow.Config.Flows.Allowed`: the flows it offers to start,
  refusing to start any other, and - when the host names some in particular
  and leaves `instances` to its default - the flows whose instances the
  default listing shows, so a page for Dog License lists the user's Dog
  License instances and not their renewals. An entry saying `start: false`
  is listed and never offered, and a page saying it about every entry has no
  Start section at all - which is what makes a reviews page the applications
  page with one field changed. `nil` is every root flow of the tenant,
  offered and listed alike; a host that wants to list one thing and start
  another passes `instances` itself. The router's `tenant_id` is applied on
  top of both. This is a listing
  convenience, not access control: the page asks the host's `on_mount`
  before it draws, like every other user-facing page, and auth stays the
  host's job (see `FormFlow.Web.Router`).

  Starting a new flow stays a plain list rather than a second table: Slab
  reads `sort` and `page` straight from the URL, so two Slab tables on one
  page would share - and fight over - the same params.

  ## Where each journey stands

  Three columns read the cache of where a journey's flow is open
  (`FormFlow.Data.Instances.Flows.update_next_positions/2`: `next_path`
  and the counts on the row, one `FormFlow.Data.Instances.Flow.NextPosition`
  per open position), never the derivation - a page of ten rows costs no
  tree per row:

    * **Status** - the perspective status, not sortable since no column
      holds it
      (`FormFlow.Web.Instances.Components.Flows.Status`): Completed when
      the journey is; Your turn when one of its open positions is a form
      the viewer's perspectives are for; Waiting on others otherwise. The
      flow instance's page says the finer things - a reopened form, or
      "Nothing is for you" - because it derives live; this page says
      Waiting. A journey no refresh has reached yet shows its own status
      word, In progress, since nothing finer is known of it.
    * **Next** - the first open position, named as the flow instance's
      page names it ("Documents / Proof of address"), and nothing once the
      journey is done or blocked. Continue links straight to that
      position's Edit page when it is the viewer's - the page that starts
      the form, since the next position is often one nobody has begun -
      and to the journey's page otherwise.
    * **Flow progress** - how many of the flow's forms are done, every
      perspective's included, so a reviewer sees how far the whole
      application is.

  Which forms are the viewer's comes from the flow type's `visible?/2`,
  asked once per form node of each of the page's flows on every load
  (`FormFlow.Web.Instances.Flows.Shared.visible_node_ids/2`) - in memory,
  never stored, so an admin adding a perspective is right on the next
  load. `actionable_only` turns that set into the listing's filter: only
  journeys open at one of the viewer's nodes are listed, which is what a
  reviews page is (`FormFlow.Data.Instances.Flows.narrow_next_position/2`).

  ## The states it draws

  No instance is in scope here, so the page asks the narrower
  `FormFlow.Web.Instances.Shared.page_state/1` and draws three states, each
  in its own `render/1` clause and with no catch-all:

    * `:redirecting` - nothing, while the host's `on_mount` navigates away
    * `:refused` - the host's message alone
    * `:ready` - the listing, and the flows it offers to start

  Start needs both rules: the state, and then that the flow is one the page
  offered. The state is not redundant. A refused viewer has no
  `:page_flows` at all - the listing is built inside the gate's `on_ok`, so
  it is never assigned - and the second rule alone would crash on the
  missing assign. It also covers the case where assigns outlive their
  decision: they persist across `update/2`, so a gate that allows on mount
  and refuses later would otherwise leave the earlier listing standing.
  """

  use Phoenix.LiveComponent

  alias FormFlow.Config.Flows.Perspective
  alias FormFlow.Context
  alias FormFlow.Data.Instances
  alias FormFlow.Data.Repo
  alias FormFlow.Data.Templates
  alias FormFlow.Data.Instances.FlowProgress
  alias FormFlow.Web.Components.Core
  alias FormFlow.Web.Components.SectionHeading
  alias FormFlow.Web.Instances.Components.Flows.Progress
  alias FormFlow.Web.Instances.Components.Flows.Status
  alias FormFlow.Web.Instances.Components.Header
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
      |> assign_new(:actionable_only, fn -> false end)
      |> assign_new(:pre_release_user_ids, fn -> [] end)
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
  # at all. Making this page "look like the others" would undo that -
  # `:page_flows` would be assigned before the refusal, and Start's second
  # rule would be checking a list the viewer was refused.
  defp assign_page_state(socket) do
    assign(socket, :page_state, FormFlow.Web.Instances.Shared.page_state(socket.assigns))
  end

  # The listing itself, built only once the host allowed the page: the
  # host's query and the host's flows to start - or the defaults, the user's
  # own and every root of the tenant - each narrowed to the router's tenant.
  # The resolved flows live under `:page_flows` so the host's `flows` stays
  # what it said, render after render.
  defp load(socket) do
    %{user_id: user_id, tenant_id: tenant_id} = socket.assigns

    allowed = Shared.resolve_flows(socket.assigns.flows, tenant_id)
    page_flows = Enum.map(allowed, & &1.flow)

    # The page's trees, once per load: three queries each. They name the
    # viewer's form nodes and the labels of the Next column. A journey of
    # a flow the page is not about - a host's `instances` query reaching
    # past its `flows` - draws neither, and with `actionable_only` is not
    # listed at all: the filter knows only the named flows' nodes.
    trees = Map.new(page_flows, &{&1.id, Templates.Flows.resolve_tree(&1.id)})

    viewer_node_ids =
      Enum.reduce(trees, MapSet.new(), fn {_flow_id, tree}, ids ->
        MapSet.union(
          ids,
          FormFlow.Web.Instances.Flows.Shared.visible_node_ids(tree, socket.assigns)
        )
      end)

    # The viewer's filter first, then the flow's status and the tenant on
    # top of everything, like today: instances of a flow nobody may see (a
    # draft) are listed for nobody, and only a flow taking starts is
    # offered (`FormFlow.Data.Templates.Flow.allows?/2`)
    query =
      (socket.assigns.instances || own_query(user_id, socket.assigns.flows, page_flows))
      |> narrow_actionable(socket.assigns.actionable_only, viewer_node_ids, tenant_id)
      |> Instances.Flows.narrow_tenant(tenant_id)
      |> Instances.Flows.narrow_allowed(:see)
      |> hide_pre_release(socket.assigns)

    socket
    |> assign(:query, query)
    |> assign(:empty?, not Repo.exists?(query))
    |> assign(:page_flows, page_flows)
    |> assign(:viewer_node_ids, viewer_node_ids)
    |> assign(:next_labels, next_labels(trees))
    |> assign(
      :trees_updated_at,
      Map.new(trees, fn {id, tree} -> {id, Templates.Flows.tree_updated_at(tree)} end)
    )
    # Both answers, as everywhere: this page has to offer the flow
    # (`FormFlow.Config.Flows.Allowed`'s `start`) and the flow's status has
    # to take a start
    |> assign(
      :offered_flows,
      for(
        %{flow: flow} = entry <- allowed,
        entry.start,
        FormFlow.Web.Instances.Shared.status_allows?(flow, :start, socket.assigns),
        do: flow
      )
    )
    # A flow the host named and offers to start that stopped taking starts is
    # worth a line; one the page merely lists among every root of the tenant
    # is not, and neither is one this page never offered
    |> assign(
      :winding_down_flows,
      if(is_list(socket.assigns.flows),
        do:
          for(
            %{flow: flow} = entry <- allowed,
            entry.start,
            flow.status == "winding_down",
            do: flow
          ),
        else: []
      )
    )
    # Whether this page offers to start anything at all. A page that says
    # `start: false` about every flow it names has no Start section, heading
    # and empty-state alert included: there is nothing there to explain.
    |> assign(:offers_starts?, Enum.any?(allowed, & &1.start))
    # Whether to draw the User ID column. The default listing is the
    # viewer's own journeys, where every row would repeat the viewer's own
    # id; a host that passed its own `instances` query may be listing
    # anyone's, and then whose journey a row is becomes the first thing a
    # reader needs. The rule is the attr, not the rows: a host query that
    # happens to return one user's journeys still gets the column, because
    # the next journey it returns may be somebody else's.
    |> assign(:user_id_column?, not is_nil(socket.assigns.instances))
    |> assign(:table_params, table_params(socket.assigns.params))
  end

  # Only the journeys open at one of the viewer's nodes, when the page says
  # so; an empty set then lists nothing, which is the truth for a viewer
  # none of the page's forms are for
  defp narrow_actionable(query, false, _node_ids, _tenant_id), do: query

  defp narrow_actionable(query, true, node_ids, tenant_id),
    do: Instances.Flows.narrow_next_position(query, MapSet.to_list(node_ids), tenant_id)

  # Every form position of the page's flows, labelled as the flow
  # instance's page labels it, keyed by flow then path - what the Next
  # column draws for a journey's `next_path`
  defp next_labels(trees) do
    Map.new(trees, fn {flow_id, tree} ->
      {flow_id,
       Map.new(FlowProgress.forms(tree, []), &{&1.path, FlowProgress.qualified_label(&1)})}
    end)
  end

  # The name of a journey's next position, or nil when it has none or the
  # page has no tree for its flow
  defp next_label(%Instances.Flow{next_path: nil}, _labels), do: nil

  defp next_label(%Instances.Flow{} = flow_instance, labels) do
    get_in(labels, [flow_instance.template_flow_id, flow_instance.next_path])
  end

  # Whether the row's cached position may be out of date: a flow of its
  # tree was saved after the last refresh, and no sweep has reached it
  # (`FormFlow.Data.Instances.Flows.next_positions_stale?/2`). Drawn as a
  # quiet mark beside the value; the journey's page repairs it on open.
  #
  # A completed journey is never stale and so is never marked - that rule
  # lives in `next_positions_stale?/2`, where the journey's page reads it
  # too.
  defp stale?(%Instances.Flow{} = flow_instance, trees_updated_at) do
    Instances.Flows.next_positions_stale?(
      flow_instance,
      Map.get(trees_updated_at, flow_instance.template_flow_id)
    )
  end

  # Whether a journey's flow is open at a form of the viewer's - one of its
  # cached open positions is among the viewer's nodes
  defp viewers_turn?(%Instances.Flow{next_positions: positions}, node_ids)
       when is_list(positions),
       do: Enum.any?(positions, &MapSet.member?(node_ids, &1.node_id))

  defp viewers_turn?(_flow_instance, _node_ids), do: false

  # The perspective status a listing can say from the cache: Completed,
  # Your turn, or Waiting on others - never Needs your attention, which
  # wants the trail (`FormFlow.Web.Instances.Components.Flows.Status`).
  # `nil` for a journey no refresh has reached, so the row falls back to
  # the journey's own status word.
  defp perspective_status(%Instances.Flow{status: "completed"}, _node_ids), do: :completed
  defp perspective_status(%Instances.Flow{next_computed_at: nil}, _node_ids), do: nil

  defp perspective_status(flow_instance, node_ids) do
    if viewers_turn?(flow_instance, node_ids), do: :your_turn, else: :waiting
  end

  # Where Continue goes: straight to the next position when it is the
  # viewer's, else the journey's page. The position's Edit page, the same
  # one the journey page's Start and Continue buttons go to, because it is
  # the page that starts the form - the next position is often one nobody
  # has begun, and View there would only say so.
  defp continue_path(base, %Instances.Flow{} = flow_instance, node_ids) do
    if flow_instance.next_path && MapSet.member?(node_ids, flow_instance.next_node_id) do
      Paths.form_edit_path(base, flow_instance.id, flow_instance.next_path)
    else
      Paths.flow_path(base, flow_instance.id)
    end
  end

  # The ring's numbers from the cached counts: done in the brand colour,
  # nothing tinted - the cache does not say what is under way
  defp ring_assigns(%Instances.Flow{completed_forms: done, forms_total: total})
       when is_integer(done) and is_integer(total) and total > 0 do
    percent = round(done / total * 100)
    %{percent: percent, behind: percent, each: 0}
  end

  defp ring_assigns(_flow_instance), do: nil

  # A pre-release flow's instances are listed for its pre-release users alone
  defp hide_pre_release(query, %{user_id: user_id, pre_release_user_ids: ids}) do
    if user_id in ids, do: query, else: Instances.Flows.exclude_status(query, "pre_release")
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

  # Both rules. The state says whether the page may act at all - and a
  # refused viewer has no `:page_flows` to check, since the listing is built
  # inside the gate's `on_ok` - and then only a flow the page offered can be
  # started from it.
  @impl true
  def handle_event("start", %{"flow-id" => flow_id}, socket)
      when socket.assigns.page_state == :ready do
    if Enum.any?(socket.assigns.offered_flows, &(&1.id == flow_id)) do
      start(socket, flow_id)
    else
      {:noreply, assign(socket, :error, "That flow is not available here.")}
    end
  end

  # A refused event is silent: the client was not driving a rendered
  # control, and a message would describe the gate to whoever was probing
  # it. Only a well-formed one, though - the params are matched here too, so
  # a "start" carrying no flow is as much a `FunctionClauseError` as an
  # event name nothing answers to. Silence is for a refusal, not for a
  # message this page does not understand.
  def handle_event("start", %{"flow-id" => _flow_id}, socket), do: {:noreply, socket}

  # The page's answer and the status are asked again here, at the click,
  # from the row as it now is - the page offered the flow when it drew, and
  # it may have stopped taking starts since. The data layer does what it is
  # asked (`FormFlow.Data.Instances.Flows.create/2`).
  defp start(socket, flow_id) do
    flow = Templates.Flows.get_row(flow_id)

    if flow && Shared.allows?(flow, :start, socket.assigns) do
      attrs = %{
        template_flow_id: flow_id,
        user_id: socket.assigns.user_id,
        tenant_id: socket.assigns.tenant_id
      }

      # The types along, so the journey's first open position is written
      # as it is created and it is in every queue from its first moment
      # (`FormFlow.Data.Instances.Flows.update_next_positions/2`)
      case Instances.Flows.create(attrs,
             flow_types: socket.assigns.flow_types,
             callback_data: socket.assigns.callback_data
           ) do
        {:ok, flow_instance} ->
          to = Paths.flow_path(socket.assigns.base, flow_instance.id)
          {:noreply, push_navigate(socket, to: to)}

        {:error, _changeset} ->
          {:noreply, assign(socket, :error, "Could not start the flow. Please try again.")}
      end
    else
      {:noreply, assign(socket, :error, "That flow is no longer taking new starts.")}
    end
  end

  # The listing's status column, as `{text, kind}` - the wording the flow
  # instance pages use for the same two states, in the same palette as a
  # form's own badge (`FormFlow.Web.Instances.Components.Flows.Progress.badge/1`).
  defp status_badge("completed"), do: {"Completed", :success}
  defp status_badge(_in_progress), do: {"In progress", :warning}

  # Newest first by default. Only injected when the URL carries no sort of its
  # own, so clicking any header still starts ascending like every other
  # column - a bare `sort_direction` default would flip that.
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
      <Header.header base={@base} />

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
      <Header.header base={@base} />

      <Core.error :if={@error} components={@components}>{@error}</Core.error>

      <%!-- "below" is only true where there is a Start section to point at:
            a page that offers no starts says the half of the sentence that
            is still true. A page listing only what the viewer can act on
            says that nothing is, which is not the same as nothing started --%>
      <Core.alert :if={@empty?} components={@components}>
        {cond do
          @actionable_only -> "Nothing is waiting for you."
          @offers_starts? -> "Nothing started yet - start a flow below."
          true -> "Nothing started yet."
        end}
      </Core.alert>

      <%!-- Slab tints its tab labels and tab contents gray, with no attr
            to say otherwise; the wrapper's variant repaints every such
            element white so the table sits on the page like the rest of it --%>
      <div :if={!@empty?} class="[&_.bg-gray-50]:bg-white">
        <Slab.table
          id="flow-instances-table"
          query={@query}
          repo={Repo.repo()}
          preload={[:template_flow, :next_positions]}
          uri={@uri}
          params={@table_params}
        >
          <:column :let={flow_instance} label="Flow">
            <.link
              navigate={Paths.flow_path(@base, flow_instance.id)}
              class="hover:underline"
            >
              {flow_instance.template_flow.name || "Untitled flow"}
            </.link>
          </:column>
          <%!-- The host's own id for whoever started the journey, as it was
                set at creation (`FormFlow.Data.Instances.Flow`). The
                library has no users and no names: it shows the string it
                was given, and the header says which string that is, so a
                reader knows what they are looking at. A host that wants a
                name renders its own column instead --%>
          <:column
            :let={flow_instance}
            :if={@user_id_column?}
            field={:user_id}
            label="User ID"
            sortable
          >
            <span class="text-sm">{flow_instance.user_id}</span>
          </:column>
          <%!-- The perspective status, from the cache; the journey's own
                word for a journey the cache has not reached. Not sortable:
                it is the viewer's reading of two columns and a set, not a
                column of its own --%>
          <:column :let={flow_instance} label="Status">
            <%= case perspective_status(flow_instance, @viewer_node_ids) do %>
              <% nil -> %>
                <% {text, kind} = status_badge(flow_instance.status) %>
                <Core.badge components={@components} kind={kind}>{text}</Core.badge>
              <% status -> %>
                <Status.badge status={status} components={@components} />
            <% end %>
          </:column>
          <%!-- The first position the flow is open at, as the journey's
                page names it; nothing once the journey is done or blocked --%>
          <:column :let={flow_instance} label="Next">
            <span class="text-sm">{next_label(flow_instance, @next_labels)}</span>
            <span
              :if={flow_instance.next_computed_at && stale?(flow_instance, @trees_updated_at)}
              class="text-xs text-zinc-400"
              title="The flow was edited after this was last computed; opening the flow instance brings it up to date."
            >
              (may have changed)
            </span>
          </:column>
          <%!-- The whole flow's forms, every perspective's: how far the
                application is, not how far the viewer is --%>
          <:column :let={flow_instance} field={:completed_forms} label="Flow progress" sortable>
            <%= if ring = ring_assigns(flow_instance) do %>
              <span class="inline-flex items-center gap-2">
                <Progress.ring percent={ring.percent} behind={ring.behind} each={ring.each} size={:sm} />
                <span class="text-xs text-zinc-500 tabular-nums">
                  {flow_instance.completed_forms} of {flow_instance.forms_total}
                </span>
              </span>
            <% end %>
          </:column>
          <:column :let={flow_instance} field={:inserted_at} label="Started" sortable>
            <span class="text-xs text-zinc-500">
              {Calendar.strftime(flow_instance.inserted_at, "%Y-%m-%d %H:%M")}
            </span>
          </:column>
          <:column :let={flow_instance} field={:updated_at} label="Updated" sortable>
            <span class="text-xs text-zinc-500">
              {Calendar.strftime(flow_instance.updated_at, "%Y-%m-%d %H:%M")}
            </span>
          </:column>
          <%!-- View goes to the journey's page; Continue straight to the
                next position's Edit page when it is the viewer's --%>
          <:column :let={flow_instance} label="Actions">
            <%= if flow_instance.status == "completed" or
                     not Templates.Flow.allows?(flow_instance.template_flow, :continue) do %>
              <.link
                navigate={Paths.flow_path(@base, flow_instance.id)}
                class="text-cyan-600 hover:underline"
              >
                View
              </.link>
            <% else %>
              <.link
                navigate={continue_path(@base, flow_instance, @viewer_node_ids)}
                class="text-cyan-600 hover:underline"
              >
                Continue
              </.link>
            <% end %>
          </:column>
          <:pagination per_page={10} />
        </Slab.table>
      </div>

      <%!-- A page that offers no starts drops the section whole: no heading,
            and no sentence about flows it was never going to offer --%>
      <SectionHeading.section_heading
        :if={@offers_starts?}
        title="Start a new flow"
        description="The flows open to start here. Starting one adds it to the list above."
        class="mt-8 mb-3"
      />
      <Core.alert
        :if={@offers_starts? and @offered_flows == [] and @winding_down_flows == []}
        components={@components}
      >
        No flows are open.
      </Core.alert>
      <div
        :if={@offered_flows != [] or @winding_down_flows != []}
        id="flow-instances-start"
        class="border border-zinc-300 rounded-lg divide-y divide-zinc-200"
      >
        <div
          :for={flow <- @offered_flows}
          class="flex flex-wrap items-center justify-between gap-3 px-6 py-4"
        >
          <span class="font-medium">{flow.name || "Untitled flow"}</span>
          <Core.button
            components={@components}
            phx-click="start"
            phx-value-flow-id={flow.id}
            phx-target={@myself}
            variant="primary"
          >
            Start
          </Core.button>
        </div>
        <%!-- A flow the page is about that stopped taking starts: named, so
              a user looking for it learns why there is no Start --%>
        <div
          :for={flow <- @winding_down_flows}
          class="flex flex-wrap items-center justify-between gap-3 px-6 py-4 text-zinc-500"
        >
          <span class="font-medium">{flow.name || "Untitled flow"}</span>
          <span class="text-sm">No longer taking new starts.</span>
        </div>
      </div>
    </div>
    """
  end
end
