defmodule FormFlow.Web.Templates.Flows.Index do
  @moduledoc """
  `FormFlow.Web.Templates.Flows.Index` LiveComponent lists flows.

  A `Slab.table` over `FormFlow.Data.Templates.Flows.roots_query/0` — the
  name with its slug beneath it, the id, status
  (`FormFlow.Data.Templates.Flow`'s table, as a badge whose title says what
  it means), summary counts and timestamps, with Overview, Show, and Edit
  actions per row and a link to create a new flow. The editor itself lives
  on those pages, so this one never loads the ReactFlow bundle. Slab runs in
  query mode against the host app's repo, so sorting, filtering, and
  pagination come from the URL: pass the current `uri` and `params` from
  `handle_params/3` (the `FormFlow.Web.Router` component forwards both).

      <.live_component
        module={FormFlow.Web.Templates.Flows.Index}
        id="flows-index"
        uri={@uri}
        params={@params}
        flow_types={@flow_types}
        form_types={@form_types}
      />

  Without a `sort` param the table sorts by creation time, matching
  `Flows.list/0` — injected into the params handed to Slab so pagination
  stays deterministic instead of leaning on unspecified database order.

  The count columns aren't sortable: they are virtual fields populated by
  the query's select, not real columns Slab could compile into `ORDER BY`.

  `base` is the path prefix the flows pages are mounted under, used to build
  the links — with the default `""`, rows link to `/flows/:id`.

  ## Filters

  A Filters tab over status, name, and slug, whitelisted as `<:filter>`
  fields so Slab compiles `filter[...]` URL params into WHERE conditions:
  status is a select of `FormFlow.Web.Templates.Shared.status_options/0`,
  name and slug are case-insensitive contains. Like the sort and the page,
  they live in the URL, so a filtered listing survives a reload and can be
  sent to someone.

  ## Archived flows

  An archived flow is put away, so the listing leaves it out: the rows are
  `roots_query(exclude_status: "archived")`, and a line above the table says
  how many are hidden with a **Show archived** link, which patches
  `?archived=true` onto the page's own URL (sort and page kept) and lists
  them greyed among the rest, with **Hide archived** to go back. The
  parameter lives in the URL like Slab's, so the listing an admin looks at
  survives a reload and can be sent to someone. When every flow is
  archived the table is not drawn at all; the page says so and offers the
  link. The status filter follows: archived is off its list of options while
  archived flows are hidden, since picking it could only empty the table.

  ## Health

  Every row carries the flow's health as a
  `FormFlow.Web.Templates.Components.Health` badge — a green check, the
  count of open entries, or a dash for a flow never checked — linking to
  the flow's health page. The badge reads the status cached on the row's
  own struct (`FormFlow.Data.Templates.Flows.Health.status/1`), so the
  listing runs no check: the health page does, and every save refreshes
  the cache.

  ## The row menu

  Beside Overview, Show, and Edit, every row has a ⋮ menu for the actions
  that do something rather than go somewhere — Duplicate Flow (the label is
  *Duplicate* because the canvas's Copy means "to the clipboard"; the code
  stays `copy`, see `FormFlow.Web.Templates.Flows.Show`) and Change status
  (`FormFlow.Web.Templates.Flows.Components.StatusDialog`, the show page's
  dialog, saving through `Flows.update_status/3` signed by `user_id` and
  reloading the listing) — and one link, History (`FormFlow.Web.Templates.Flows.History`),
  a lesser page than Overview kept out of the row. Duplicate Flow opens
  the same dialog the show page does
  (`FormFlow.Web.Templates.Flows.Components.CopyDialog`),
  prefilled for that row's flow, and lands on the copy's show page — the
  row is loaded whole for it (`FormFlow.Data.Templates.Flows.get/1`), since
  the listing's rows carry counts, not contents. `flow_types` and
  `form_types` are the host's lists, passed so the copy's health is checked
  once and cached, as the show page does.
  """

  use Phoenix.LiveComponent

  alias FormFlow.Data.Repo
  alias FormFlow.Data.Templates.Flow
  alias FormFlow.Data.Templates.Flows
  alias FormFlow.Web.Components.Core
  alias FormFlow.Web.Templates.Components.Header
  alias FormFlow.Web.Templates.Components.Health
  alias FormFlow.Web.Templates.Flows.Components.CopyDialog
  alias FormFlow.Web.Templates.Flows.Components.StatusDialog
  alias FormFlow.Web.Templates.Shared
  alias Phoenix.LiveView.JS

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       error: nil,
       copying: nil,
       copy_name: nil,
       copy_slug: nil,
       copy_error: nil,
       changing_status: nil,
       status_pending: nil,
       status_counts: nil,
       status_pre_release_count: 0,
       status_delete_pre_release?: false,
       status_error: nil
     )}
  end

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
      |> assign_new(:flow_types, fn -> FormFlow.Config.Flows.Type.defaults() end)
      |> assign_new(:form_types, fn -> FormFlow.Config.Forms.Type.defaults() end)
      |> assign_new(:user_id, fn -> nil end)

    tenant_id = socket.assigns.tenant_id
    show_archived? = socket.assigns.params["archived"] == "true"
    roots = Flows.roots_query(tenant_id: tenant_id)

    query =
      if show_archived?,
        do: roots,
        else: Flows.roots_query(tenant_id: tenant_id, exclude_status: "archived")

    empty? = not Repo.exists?(roots)

    {:ok,
     socket
     |> assign(:query, query)
     |> assign(:empty?, empty?)
     |> assign(:all_hidden?, not empty? and not show_archived? and not Repo.exists?(query))
     |> assign(:show_archived?, show_archived?)
     |> assign(:archived_count, archived_count(tenant_id, empty? or show_archived?))
     |> assign(:archived_toggle_path, archived_toggle_path(socket.assigns, not show_archived?))
     |> assign(:table_params, Map.put_new(socket.assigns.params, "sort", "inserted_at"))
     |> assign(
       :host_types,
       flow_types: socket.assigns.flow_types,
       form_types: socket.assigns.form_types
     )}
  end

  # The row's flow, loaded whole, is what the dialog and `copy/2` take; a row
  # that has gone since the listing drew — deleted, or another tenant's id
  # sent by hand — is refused with a message rather than copied.
  @impl true
  def handle_event("request_copy", %{"id" => id}, socket) do
    case listed_flow(id, socket.assigns.tenant_id) do
      %Flow{} = flow ->
        {:noreply,
         assign(socket,
           copying: flow,
           copy_name: Shared.copy_name(flow),
           copy_slug: Flows.copy_slug(flow),
           copy_error: nil,
           error: nil
         )}

      nil ->
        {:noreply, assign(socket, :error, "That flow is no longer listed here.")}
    end
  end

  @impl true
  def handle_event("cancel_copy", _params, socket) do
    {:noreply, assign(socket, copying: nil, copy_error: nil)}
  end

  @impl true
  def handle_event("copy", params, socket) do
    case Shared.copy_flow(
           socket.assigns.copying,
           params,
           socket.assigns.host_types ++ [user_id: socket.assigns.user_id]
         ) do
      {:ok, copy} ->
        {:noreply, push_navigate(socket, to: "#{socket.assigns.base}/flows/#{copy.id}")}

      {:error, message} ->
        # The dialog redraws with what was typed, not the prefill
        {:noreply,
         assign(socket, copy_error: message, copy_name: params["name"], copy_slug: params["slug"])}
    end
  end

  # The status dialog for a row: the same three events as the show page's,
  # and Save reloads the listing so the badge follows
  @impl true
  def handle_event("request_status", %{"id" => id}, socket) do
    case listed_flow(id, socket.assigns.tenant_id) do
      %Flow{} = flow ->
        {:noreply,
         assign(socket,
           changing_status: flow,
           status_pending: flow.status,
           status_counts: Shared.instance_counts(flow),
           status_pre_release_count: Shared.pre_release_count(flow),
           status_delete_pre_release?: false,
           status_error: nil
         )}

      nil ->
        {:noreply, assign(socket, :error, "That flow is no longer listed here.")}
    end
  end

  # The form as it stands: the pick, and whether the delete box is ticked
  @impl true
  def handle_event("status_picked", %{"status" => status} = params, socket) do
    socket = assign(socket, :status_delete_pre_release?, params["delete_pre_release"] == "true")

    if status in Flow.statuses(),
      do: {:noreply, assign(socket, :status_pending, status)},
      else: {:noreply, socket}
  end

  @impl true
  def handle_event("cancel_status", _params, socket) do
    {:noreply, assign(socket, changing_status: nil, status_error: nil)}
  end

  # A save with no dialog open is not a rendered control: ignored
  @impl true
  def handle_event("save_status", _params, %{assigns: %{changing_status: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("save_status", params, socket) do
    case Shared.save_status(socket.assigns.changing_status, params, socket.assigns.user_id) do
      {:ok, _flow} ->
        {:noreply, push_navigate(socket, to: current_path(socket.assigns))}

      {:error, message} ->
        {:noreply, assign(socket, :status_error, message)}
    end
  end

  # This page again, sort and page kept, so a write shows in the listing
  defp current_path(%{uri: uri, base: base}) do
    case uri && URI.parse(uri) do
      %URI{path: path, query: nil} when is_binary(path) -> path
      %URI{path: path, query: query} when is_binary(path) -> path <> "?" <> query
      _none -> "#{base}/flows"
    end
  end

  # How many archived flows the hidden line names; not asked when there is
  # nothing to list or when they are shown, where the line does not say
  defp archived_count(_tenant_id, true), do: 0

  defp archived_count(tenant_id, false),
    do: Repo.aggregate(Flows.roots_query(tenant_id: tenant_id, status: "archived"), :count)

  # This page with `archived` switched — the sort kept, the page number
  # dropped, since the rows it counted have changed
  defp archived_toggle_path(%{uri: uri, base: base}, show?) do
    {path, params} =
      case uri && URI.parse(uri) do
        %URI{path: path, query: query} when is_binary(path) ->
          {path, URI.decode_query(query || "")}

        _none ->
          {"#{base}/flows", %{}}
      end

    params =
      params
      |> Map.delete("page")
      |> then(&if(show?, do: Map.put(&1, "archived", "true"), else: Map.delete(&1, "archived")))

    if params == %{}, do: path, else: path <> "?" <> URI.encode_query(params)
  end

  # The status filter offers the statuses the listing can actually show:
  # archived is off the list while archived flows are hidden, since picking
  # it could only empty the table.
  defp status_filter_options(true), do: Shared.status_options()

  defp status_filter_options(false),
    do: Enum.reject(Shared.status_options(), fn {_label, status} -> status == "archived" end)

  defp listed_flow(id, tenant_id) do
    case Flows.get(id) do
      %Flow{owner_flow_id: nil} = flow when is_nil(tenant_id) or flow.tenant_id == tenant_id ->
        flow

      _ ->
        nil
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <Header.header base={@base} section="flows" components={@components}>
        <:actions>
          <Core.button components={@components} navigate={"#{@base}/flows/new"} variant="primary">
            New flow
          </Core.button>
        </:actions>
      </Header.header>

      <Core.error :if={@error} components={@components}>{@error}</Core.error>

      <Core.alert :if={@empty?} components={@components}>
        No flows yet — create the first one.
      </Core.alert>

      <Core.alert :if={@all_hidden?} components={@components}>
        Every flow here is archived.
        <.link patch={@archived_toggle_path} class="underline">Show archived</.link>
      </Core.alert>

      <CopyDialog.copy_dialog
        :if={@copying}
        flow={@copying}
        name={@copy_name}
        slug={@copy_slug}
        error={@copy_error}
        target={@myself}
        components={@components}
      />

      <StatusDialog.status_dialog
        :if={@changing_status}
        flow={@changing_status}
        status={@status_pending}
        counts={@status_counts}
        pre_release_count={@status_pre_release_count}
        delete_pre_release?={@status_delete_pre_release?}
        error={@status_error}
        target={@myself}
        components={@components}
      />

      <%!-- Archived flows are put away: out of the listing until asked for --%>
      <p
        :if={not @empty? and not @all_hidden? and (@show_archived? or @archived_count > 0)}
        id="flows-archived-toggle"
        class="mb-2 text-xs text-zinc-500"
      >
        <%= if @show_archived? do %>
          Archived flows are listed, greyed.
          <.link patch={@archived_toggle_path} class="underline">Hide archived</.link>
        <% else %>
          {Shared.count(@archived_count, "archived flow")} hidden.
          <.link patch={@archived_toggle_path} class="underline">Show archived</.link>
        <% end %>
      </p>

      <Slab.table
        :if={not @empty? and not @all_hidden?}
        id="flows-table"
        query={@query}
        repo={Repo.repo()}
        uri={@uri}
        params={@table_params}
      >
        <:tab name="filters" />
        <:filter
          field={:status}
          label="Status"
          type="select"
          options={status_filter_options(@show_archived?)}
        />
        <:filter field={:name} label="Name" placeholder="Search names" />
        <:filter field={:slug} label="Slug" placeholder="Search slugs" />
        <:column :let={flow} field={:name} sortable>
          <.link
            navigate={"#{@base}/flows/#{flow.id}"}
            class={["hover:underline", flow.status == "archived" && "text-zinc-400"]}
          >
            {flow.name || "Untitled"}
          </.link>
          <code :if={flow.slug} class="block text-xs text-zinc-600">{flow.slug}</code>
        </:column>
        <:column :let={flow} field={:id} label="ID">
          <span class="font-mono text-[10px] text-zinc-400">{flow.id}</span>
        </:column>
        <:column :let={flow} field={:status} label="Status">
          <Core.badge
            components={@components}
            kind={Shared.status_kind(flow.status)}
            title={Shared.status_summary(flow.status)}
          >
            {Shared.status_label(flow.status)}
          </Core.badge>
        </:column>
        <:column :let={flow} field={:label} label="Kind">
          <span class="text-xs text-zinc-500">
            {if flow.label == "subflows", do: "Complex", else: "Simple"}
          </span>
        </:column>
        <:column field={:nodes_count} label="Steps" />
        <:column field={:relationships_count} label="Connections" />
        <:column :let={flow} label="Health">
          <Health.health base={@base} flow={flow} components={@components} />
        </:column>
        <:column :let={flow} field={:inserted_at} label="Created" sortable>
          <span class="text-xs text-zinc-500">
            {Calendar.strftime(flow.inserted_at, "%Y-%m-%d %H:%M")}
          </span>
        </:column>
        <:column :let={flow} label="Actions">
          <div class="flex items-center gap-3">
            <.link
              navigate={"#{@base}/flows/#{flow.id}/overview"}
              class="text-cyan-600 hover:underline"
            >
              Overview
            </.link>
            <.link navigate={"#{@base}/flows/#{flow.id}"} class="text-cyan-600 hover:underline">
              Show
            </.link>
            <.link navigate={"#{@base}/flows/#{flow.id}/edit"} class="text-cyan-600 hover:underline">
              Edit
            </.link>
            <%!-- A <details> dropdown, as the demo's user switcher: open and
                  close are the browser's, click-away closes it, and choosing
                  an item closes it before the event goes out --%>
            <details
              id={"flow-#{flow.id}-actions"}
              class="dropdown dropdown-end"
              phx-click-away={JS.remove_attribute("open")}
            >
              <summary
                class="btn btn-ghost btn-xs cursor-pointer list-none px-1.5 text-base leading-none text-zinc-500 select-none [&::-webkit-details-marker]:hidden"
                aria-label={"More actions for #{flow.name || "Untitled"}"}
                aria-haspopup="menu"
              >
                ⋮
              </summary>
              <ul
                class="dropdown-content menu menu-sm z-30 mt-1 w-44 rounded-md border border-zinc-300 bg-white p-1 shadow-lg"
                role="menu"
              >
                <li>
                  <button
                    type="button"
                    role="menuitem"
                    phx-click={
                      JS.remove_attribute("open", to: "#flow-#{flow.id}-actions")
                      |> JS.push("request_copy", value: %{id: flow.id})
                    }
                    phx-target={@myself}
                  >
                    Duplicate Flow
                  </button>
                </li>
                <li>
                  <button
                    type="button"
                    role="menuitem"
                    phx-click={
                      JS.remove_attribute("open", to: "#flow-#{flow.id}-actions")
                      |> JS.push("request_status", value: %{id: flow.id})
                    }
                    phx-target={@myself}
                  >
                    Change status
                  </button>
                </li>
                <%!-- The one link in the menu: a lesser page than Overview,
                      there for auditing --%>
                <li>
                  <.link navigate={"#{@base}/flows/#{flow.id}/history"} role="menuitem">
                    History
                  </.link>
                </li>
              </ul>
            </details>
          </div>
        </:column>
        <:pagination per_page={10} />
      </Slab.table>
    </div>
    """
  end
end
