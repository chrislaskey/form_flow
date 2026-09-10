defmodule DemoWeb.DataModelingLive do
  @moduledoc """
  `/docs/data-modeling` — the tables `mix form_flow.gen.migration` creates,
  drawn as a schema diagram with a column-level ReactFlow node modelled on
  [ReactFlow's database schema node](https://reactflow.dev/ui/components/database-schema-node).

  The tables, columns, and foreign keys come from
  `DemoWeb.DataModelingLive.Diagram`, which reads them off FormFlow's Ecto
  schemas, so the page describes the library it is compiled against rather
  than a drawing of it.

  The canvas is deliberately *not* FormFlow's editor bundle. That bundle
  exports `mount`/`mountOverview` and keeps React to itself, so a page
  wanting a node type of its own cannot reach in. This one loads React and
  ReactFlow from jsDelivr instead and registers its own `table` node, which
  makes it a second standalone demonstration of the same idea — a ReactFlow
  canvas whose data is defined in Elixir — with no bundler, no npm install,
  and nothing added to `app.js` but the hook below.

  It also means the page needs network access to jsDelivr; offline, it says
  so where the canvas would be.
  """

  use DemoWeb, :live_view

  alias DemoWeb.DataModelingLive.Diagram
  alias FormFlow.Web.Helpers.ReactFlow

  # Pinned, immutable CDN files. ReactFlow 11 rather than 12
  # (@xyflow/react) because 11 is the last version whose UMD build runs on the
  # React and ReactDOM globals alone — 12's also wants `react/jsx-runtime` as
  # a global, which React ships no UMD for. React 18 for the same reason: 19
  # dropped UMD builds. FormFlow's own editor bundle is @xyflow/react 12 on
  # React 19; it goes through esbuild, so none of this applies to it.
  #
  # The list is what the page's table draws, and the map is what the hook
  # fetches — derived from it, so a version can only be bumped in one place.
  @sources [
    {:react, "react", "18.3.1",
     "https://cdn.jsdelivr.net/npm/react@18.3.1/umd/react.production.min.js"},
    {:react_dom, "react-dom", "18.3.1",
     "https://cdn.jsdelivr.net/npm/react-dom@18.3.1/umd/react-dom.production.min.js"},
    {:react_flow, "reactflow", "11.11.4",
     "https://cdn.jsdelivr.net/npm/reactflow@11.11.4/dist/umd/index.js"},
    {:react_flow_css, "reactflow/dist/style.css", "11.11.4",
     "https://cdn.jsdelivr.net/npm/reactflow@11.11.4/dist/style.css"}
  ]

  @source_urls Map.new(@sources, fn {key, _package, _version, url} -> {key, url} end)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Data modeling")
     |> assign(:current_nav, :data_modeling)
     |> assign(:diagram, Diagram.data())
     |> assign(:foreign_keys, Diagram.foreign_keys())
     |> assign(:on_delete_legend, Diagram.on_delete_legend())
     |> assign(:table_count, Diagram.table_count())
     |> assign(:sources, @sources)
     |> assign(:source_urls, @source_urls)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_nav={@current_nav} current_user={@current_user}>
      <div class="space-y-10">
        <header class="space-y-2">
          <h1 class="text-2xl font-semibold">Data modeling</h1>
          <p class="text-base-content/70">
            The {@table_count} tables <code>mix form_flow.gen.migration</code>
            creates, and the {length(@foreign_keys)} foreign keys between them. Every table,
            column, and key below is read off FormFlow's Ecto schemas when this
            page renders — nothing here is a drawing kept in step by hand.
          </p>
          <p class="text-sm text-base-content/70">
            Column types are the Postgres types the migration produces. This demo
            runs SQLite, whose migration is a near-copy; the two diverge only in
            the DDL, not in the tables or the keys.
          </p>
        </header>

        <section class="space-y-3">
          <div class="flex flex-wrap items-baseline justify-between gap-x-6 gap-y-1">
            <h2 class="text-lg font-semibold">Schema</h2>
            <p class="text-sm text-base-content/70">
              Drag to pan, scroll to zoom, drag a table to move it.
            </p>
          </div>

          <div
            id="schema-diagram"
            class="schema-diagram"
            phx-hook=".SchemaDiagram"
            phx-update="ignore"
            data-diagram={ReactFlow.to_json(@diagram)}
            data-react={@source_urls.react}
            data-react-dom={@source_urls.react_dom}
            data-react-flow={@source_urls.react_flow}
            data-react-flow-css={@source_urls.react_flow_css}
          >
          </div>

          <div id="group-legend" class="flex flex-wrap items-center gap-x-6 gap-y-2 text-sm">
            <span class="flex items-center gap-2">
              <span class="schema-legend-swatch schema-legend-swatch--templates"></span>
              <code>FormFlow.Data.Templates</code>
              <span class="text-base-content/70">— what an admin builds</span>
            </span>
            <span class="flex items-center gap-2">
              <span class="schema-legend-swatch schema-legend-swatch--instances"></span>
              <code>FormFlow.Data.Instances</code>
              <span class="text-base-content/70">— what a user fills out</span>
            </span>
          </div>

          <ul id="on-delete-legend" class="space-y-1 text-sm">
            <li :for={rule <- @on_delete_legend} class="flex flex-wrap items-baseline gap-x-3">
              <span class="flex items-center gap-2 font-mono text-xs whitespace-nowrap">
                <span class="schema-legend-line" style={"background: #{rule.color}"}></span>
                ON DELETE {rule.label}
              </span>
              <span class="text-base-content/70">{rule.meaning}</span>
            </li>
          </ul>
        </section>

        <section class="space-y-3">
          <h2 class="text-lg font-semibold">Reading the model</h2>
          <ul class="space-y-2 text-sm text-base-content/70">
            <li>
              <strong class="text-gray-900">A flow is a property graph.</strong>
              <code>form_flow_flows</code>
              holds one. Its steps are rows in <code>form_flow_nodes</code>.
              The connections between them are rows in <code>form_flow_relationships</code>. Both carry a
              <code>properties</code>
              jsonb column and a real <code>flow_id</code>, so the database
              enforces membership while the shape stays portable to Neo4j.
            </li>
            <li>
              <strong class="text-gray-900">A form template is a lineage plus its versions.</strong>
              <code>form_flow_template_forms</code>
              is the identity; <code>form_flow_template_form_versions</code>
              holds every definition, draft and published. Published versions never
              change.
            </li>
            <li>
              <strong class="text-gray-900">An instance pins the version it was filled against.</strong>
              <code>form_flow_instance_forms.template_form_version_id</code>
              is the load-bearing column of the whole schema, and the only path from
              a set of answers to its lineage — there is deliberately no second
              column beside it to fall out of step.
            </li>
            <li>
              <strong class="text-gray-900">A journey is addressed by path, not by node.</strong>
              <code>form_flow_instance_forms.instance_flow_id</code>
              and <code>path</code>
              — the chain of node ids from the root flow down
              to the form — identify a visit. Editor saves replace all of a flow's
              nodes, so a foreign key to a node would fire on every routine save.
            </li>
            <li>
              <strong class="text-gray-900">Nothing is deleted quietly.</strong>
              The three event tables are append-only audit logs, and every key into
              them is <code>RESTRICT</code>: removing a flow, a form, or a journey
              goes through explicit context code that deletes its events on purpose.
            </li>
          </ul>
        </section>

        <section class="space-y-3">
          <h2 class="text-lg font-semibold">Foreign keys</h2>
          <div class="overflow-x-auto">
            <table id="foreign-keys" class="table table-sm">
              <thead>
                <tr>
                  <th>Column</th>
                  <th>References</th>
                  <th>On delete</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={key <- @foreign_keys}>
                  <td class="font-mono text-xs whitespace-nowrap">
                    {key.table}.<span class="font-semibold">{key.column}</span>
                  </td>
                  <td class="font-mono text-xs whitespace-nowrap">{key.references}</td>
                  <td class="font-mono text-xs whitespace-nowrap" style={"color: #{key.color}"}>
                    {key.on_delete}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

        <section class="space-y-3">
          <h2 class="text-lg font-semibold">How this page is built</h2>
          <p class="text-sm text-base-content/70">
            React and ReactFlow are fetched from jsDelivr by the page's colocated
            hook, which then registers one node type of its own — <code>table</code>
            — and hands it the nodes and edges <code>DemoWeb.DataModelingLive.Diagram</code>
            derived in Elixir. There is no npm install, no bundler config, and
            nothing in <code>app.js</code>
            but the hook, so the page loads nothing until you open it.
          </p>
          <div class="overflow-x-auto">
            <table id="cdn-sources" class="table table-sm">
              <thead>
                <tr>
                  <th>Package</th>
                  <th>Version</th>
                  <th>Fetched from</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={{_key, package, version, url} <- @sources}>
                  <td class="font-mono text-xs whitespace-nowrap">{package}</td>
                  <td class="font-mono text-xs">{version}</td>
                  <td class="font-mono text-xs break-all">{url}</td>
                </tr>
              </tbody>
            </table>
          </div>
          <p class="text-sm text-base-content/70">
            FormFlow's flow editor takes the other road: its React and
            @xyflow/react are prebuilt into <code>priv/static/form_flow_editor.mjs</code>
            and served by the <code>form_flow_router_asset_routes()</code>
            route, so an app installing the library needs no CDN and no network at
            runtime. Compare <.link navigate={~p"/admin/flows"} class="link">/admin/flows</.link>
            with this page: same idea, two ways of getting React to the browser.
          </p>
        </section>
      </div>
    </Layouts.app>

    <style>
      .schema-diagram {
        height: 76vh;
        min-height: 600px;
        border: 1px solid #e5e7eb;
        border-radius: 12px;
        overflow: hidden;
        background: #fafafa;
      }

      .schema-node {
        width: 300px;
        border: 1px solid #d4d4d8;
        border-radius: 8px;
        background: #fff;
        box-shadow: 0 1px 2px rgb(0 0 0 / 0.06);
        font-size: 12px;
        line-height: 1.2;
        overflow: hidden;
      }

      .schema-node__header {
        padding: 6px 10px;
        border-bottom: 1px solid #d4d4d8;
      }

      .schema-node--templates .schema-node__header { background: #eef2ff; }
      .schema-node--instances .schema-node__header { background: #ecfdf5; }

      .schema-node__table {
        display: block;
        font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
        font-weight: 600;
        color: #111827;
      }

      .schema-node__schema {
        display: block;
        margin-top: 3px;
        font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
        font-size: 10px;
        color: #6b7280;
      }

      .schema-node__row {
        position: relative;
        display: flex;
        align-items: center;
        gap: 6px;
        height: 22px;
        padding: 0 10px;
        border-top: 1px solid #f4f4f5;
      }

      .schema-node__name {
        font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
        color: #111827;
      }

      .schema-node__key {
        padding: 1px 3px;
        border-radius: 3px;
        font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
        font-size: 9px;
        font-weight: 700;
        letter-spacing: 0.04em;
      }

      .schema-node__key--pk { background: #fef3c7; color: #92400e; }
      .schema-node__key--fk { background: #e0e7ff; color: #3730a3; }

      .schema-node__type {
        margin-left: auto;
        font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
        font-size: 10px;
        color: #71717a;
      }

      /* Handles are anchors, not controls: only the primary key and the
         foreign keys get one, and they draw as a small dot on the node's edge. */
      .schema-diagram .react-flow__handle {
        width: 7px;
        height: 7px;
        min-width: 0;
        min-height: 0;
        border: 1px solid #a1a1aa;
        background: #fff;
      }

      .schema-diagram .react-flow__handle-left { left: -4px; }
      .schema-diagram .react-flow__handle-right { right: -4px; }

      .schema-legend-swatch {
        display: block;
        flex: none;
        width: 14px;
        height: 14px;
        border: 1px solid #d4d4d8;
        border-radius: 3px;
      }

      .schema-legend-swatch--templates { background: #eef2ff; }
      .schema-legend-swatch--instances { background: #ecfdf5; }

      .schema-legend-line {
        display: block;
        flex: none;
        width: 18px;
        height: 2px;
        border-radius: 1px;
      }
    </style>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".SchemaDiagram">
      // Every <script> and <link> is fetched once per page load, however many
      // canvases ask for it.
      const loading = new Map()

      function loadScript(src) {
        if (!loading.has(src)) {
          loading.set(src, new Promise((resolve, reject) => {
            const script = document.createElement("script")

            script.src = src
            script.crossOrigin = "anonymous"
            script.onload = resolve
            script.onerror = () => reject(new Error(`could not load ${src}`))

            document.head.appendChild(script)
          }))
        }

        return loading.get(src)
      }

      function loadStylesheet(href) {
        if (document.querySelector(`link[href="${href}"]`)) return

        const link = document.createElement("link")

        link.rel = "stylesheet"
        link.href = href

        document.head.appendChild(link)
      }

      async function loadReactFlow(dataset) {
        loadStylesheet(dataset.reactFlowCss)

        // ReactFlow's UMD build reads window.React and window.ReactDOM as it
        // runs, so both have to be there first
        await Promise.all([loadScript(dataset.react), loadScript(dataset.reactDom)])
        await loadScript(dataset.reactFlow)

        return {React: window.React, ReactDOM: window.ReactDOM, ReactFlow: window.ReactFlow}
      }

      // The table node: a header naming the table and the Ecto schema behind
      // it, then one row per column. A row's handle is what an edge attaches
      // to, which is why the primary key gets a target and each foreign key a
      // source — the same arrangement as ReactFlow's own database schema node,
      // written with createElement because there is no JSX without a bundler.
      function tableNode({React, ReactFlow}) {
        const h = React.createElement
        const {Handle, Position} = ReactFlow

        const handles = {
          target: {type: "target", position: Position.Left},
          source: {type: "source", position: Position.Right}
        }

        return function TableNode({data}) {
          return h("div", {className: `schema-node schema-node--${data.group}`},
            h("div", {className: "schema-node__header"},
              h("span", {className: "schema-node__table"}, data.table),
              h("span", {className: "schema-node__schema"}, data.schema)
            ),
            data.columns.map((column) =>
              h("div", {className: "schema-node__row", key: column.name},
                column.handle &&
                  h(Handle, {...handles[column.handle], id: column.name, isConnectable: false}),
                h("span", {className: "schema-node__name"}, column.name),
                column.key &&
                  h("span", {
                    className: `schema-node__key schema-node__key--${column.key.toLowerCase()}`
                  }, column.key),
                h("span", {className: "schema-node__type"}, column.type)
              )
            )
          )
        }
      }

      export default {
        async mounted() {
          try {
            const {React, ReactDOM, ReactFlow} = await loadReactFlow(this.el.dataset)
            const h = React.createElement
            const {Background, Controls, MiniMap} = ReactFlow
            const {nodes, edges} = JSON.parse(this.el.dataset.diagram)

            this.nodeTypes = {table: tableNode({React, ReactFlow})}
            this.root = ReactDOM.createRoot(this.el)

            this.root.render(
              h(ReactFlow.ReactFlow, {
                defaultNodes: nodes,
                defaultEdges: edges,
                nodeTypes: this.nodeTypes,
                fitView: true,
                fitViewOptions: {padding: 0.08},
                minZoom: 0.2,
                maxZoom: 2,
                nodesConnectable: false,
                deleteKeyCode: null,
                proOptions: {hideAttribution: false}
              },
                h(Background, {gap: 24, size: 1, color: "#d4d4d8"}),
                h(Controls, {showInteractive: false}),
                h(MiniMap, {pannable: true, zoomable: true, ariaLabel: "Schema minimap"})
              )
            )
          } catch (error) {
            console.error("[demo] could not load the schema diagram", error)

            this.el.textContent =
              "The schema diagram loads React and ReactFlow from cdn.jsdelivr.net, " +
              "which this browser could not reach."
            this.el.style.display = "grid"
            this.el.style.placeItems = "center"
            this.el.style.padding = "2rem"
            this.el.style.textAlign = "center"
          }
        },

        destroyed() {
          this.root?.unmount()
        }
      }
    </script>
    """
  end
end
