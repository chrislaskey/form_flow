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
  alias DemoWeb.DataModelingLive.GraphSchema
  alias DemoWeb.DataModelingLive.SqlExamples
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
     |> assign(:graph, GraphSchema.data())
     |> assign(:structural_types, GraphSchema.structural_types())
     |> assign(:sql_examples, SqlExamples.all())
     |> assign(:foreign_keys, Diagram.foreign_keys())
     |> assign(:on_delete_legend, Diagram.on_delete_legend())
     |> assign(:source_urls, @source_urls)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_nav={@current_nav} current_user={@current_user}>
      <div class="space-y-10">
        <header class="space-y-2">
          <h1 class="text-2xl font-semibold">Data modeling</h1>
        </header>

        <section class="space-y-3">
          <div class="flex flex-wrap items-baseline justify-between gap-x-6 gap-y-1">
            <h2 class="text-lg font-semibold">
              SQL Schema <span class="font-light">PostgreSQL and SQLite supported</span>
            </h2>
          </div>

          <p class="mb-6 max-w-3xl">
            To read the data model, recommend starting in the top right corner with `Templates.Flow`, then move left across `Templates.Flow.Node` and `Templates.Form`. Those are the key models on the admin template side. The user side starts with `Instances.Flow` and moves left to `Instances.Form`.
          </p>

          <div id="group-legend" class="flex flex-wrap gap-x-6 gap-y-2">
            <div class="flex gap-2">
              <div class="schema-legend-swatch schema-legend-swatch--templates"></div>
              <div>
                <code>FormFlow.Data.Templates</code>
                <div class="text-sm text-base-content/70">What an admin builds</div>
              </div>
            </div>
            <div class="flex gap-2">
              <div class="schema-legend-swatch schema-legend-swatch--instances"></div>
              <div>
                <code>FormFlow.Data.Instances</code>
                <div class="text-sm text-base-content/70">What a user fills out</div>
              </div>
            </div>
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
        </section>

        <section class="space-y-3">
          <div class="flex flex-wrap items-baseline justify-between gap-x-6 gap-y-1">
            <h2 class="text-lg font-semibold">
              Neo4J Graph Schema <span class="font-light">Optional but recommended</span>
            </h2>
          </div>

          <p class="mb-6 max-w-3xl">
            Modeling a flow is best done as a graph. While these can be modeled in a traditional SQL database, it's very inefficient. Even simple flows (from a human perspective) can take a lot of system resources to pull out of a relational database.
          </p>

          <p class="mb-6 max-w-3xl">
            To help FormFlow scale, it supports dual-writing graph data into a graph database (Neo4J). This makes it much easier to realize a graph at scale. When enabled, Neo4J is queried first, then a targeted SQL query is used to pull just the data from specific IDs.
          </p>

          <div
            id="graph-diagram"
            class="schema-diagram schema-diagram--graph"
            phx-hook=".SchemaDiagram"
            phx-update="ignore"
            data-diagram={ReactFlow.to_json(@graph)}
            data-react={@source_urls.react}
            data-react-dom={@source_urls.react_dom}
            data-react-flow={@source_urls.react_flow}
            data-react-flow-css={@source_urls.react_flow_css}
          >
          </div>

          <p class="max-w-3xl">
            Three of the ten tables above cross over, and only those three: a
            node (a <em>step</em>, in the product's words), a relationship
            between two nodes, and the flow they belong to. Form templates,
            form versions, and every instance table stay in SQL — a <code>form_id</code>
            in a Neo4j property map is a key into Postgres, not a pointer into
            the graph. Flows are drawn here as nodes rather than left out
            because anything a reference targets has to be a node, or the
            reference cannot be traversed, and both subflow and ownership
            references point at flows.
          </p>

          <p class="max-w-3xl">
            A node carries <code>labels</code>, plural — a set — while a
            relationship carries exactly one <code>type</code>. FormFlow's SQL
            already mirrors that: <code>labels text[]</code>
            on the nodes table, a single <code>label varchar</code>
            on the relationships table. Each entity's <code>properties</code>
            column is its Neo4j property map byte for byte, which is why the
            infrastructure columns are dual-written into it — in the graph there
            are no columns to index.
          </p>

          <p class="max-w-3xl">
            The lines are not foreign keys. A solid one is the relationship row
            itself, joining the two nodes it names. A dashed one is <em>structural</em>: a relationship Neo4j would hold that no row
            does, because a property already says it.
          </p>

          <div class="overflow-x-auto">
            <table id="structural-types" class="table table-sm">
              <thead>
                <tr>
                  <th>Reserved type</th>
                  <th>Derived from</th>
                  <th>Means</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={type <- @structural_types}>
                  <td class="font-mono text-xs whitespace-nowrap">{type.type}</td>
                  <td class="font-mono text-xs whitespace-nowrap">{type.derived_from}</td>
                  <td class="text-sm">{type.meaning}</td>
                </tr>
              </tbody>
            </table>
          </div>

          <p class="max-w-3xl">
            Those three types are FormFlow's structural vocabulary, so user data
            must not collide with them: <code>FormFlow.Data.Templates.Flow.Relationship</code>
            rejects them as relationship labels today — a changeset error, not a
            convention — which means no stored data will need cleaning up when
            the dual-write arrives.
          </p>
        </section>

        <section class="space-y-3">
          <div class="flex flex-wrap items-baseline justify-between gap-x-6 gap-y-1">
            <h2 class="text-lg font-semibold">
              Example SQL queries
              <span class="font-light">what the graph looks like from the database's side</span>
            </h2>
          </div>

          <p class="mb-6 max-w-3xl">
            A property graph in a relational database is not exotic — it is two
            tables and a foreign key. What changes is the reading: once a query
            has to *follow* the graph rather than filter it, the shape of the
            statement starts to matter.
          </p>

          <div :for={example <- @sql_examples} id={"sql-#{example.id}"} class="mb-8 max-w-3xl">
            <h3 class="font-semibold">{example.title}</h3>
            <p class="my-2">{example.blurb}</p>
            <pre class="schema-sql"><code>{example.sql}</code></pre>
            <p class="mt-2 whitespace-pre-line text-base-content/70">{example.note}</p>
          </div>
        </section>

        <section class="space-y-3">
          <h2 class="text-lg font-semibold">SQL data relationships</h2>
          <div>Delete types</div>
          <ul id="on-delete-legend" class="my-3 ml-3 space-y-1 text-sm">
            <li :for={rule <- @on_delete_legend} class="flex flex-wrap items-baseline gap-x-3">
              <span class="font-mono text-xs whitespace-nowrap">
                ON DELETE {rule.label}
              </span>
              <span class="text-base-content/70">{rule.meaning}</span>
            </li>
          </ul>
          <div>Foreign keys</div>
          <div class="overflow-x-auto ml-3 ">
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
                  <td class="font-mono text-xs whitespace-nowrap">{key.on_delete}</td>
                </tr>
              </tbody>
            </table>
          </div>
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

      /* The five starred tables, drawn a shade heavier than the ones that
         support them */
      .schema-node--primary {
        border-color: #71717a;
        box-shadow: 0 1px 4px rgb(0 0 0 / 0.14);
      }

      .schema-node__schema {
        display: block;
        font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
        font-weight: 600;
        color: #111827;
      }

      .schema-node__table {
        display: block;
        margin-top: 3px;
        font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
        font-size: 10px;
        color: #6b7280;
      }

      .schema-node__star {
        margin-left: 5px;
        font-family: system-ui, sans-serif;
        font-size: 11px;
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

      .schema-node__key { background: #e0e7ff; color: #3730a3; }

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
        width: 24px;
        height: 24px;
        border: 1px solid #d4d4d8;
        border-radius: 3px;
      }

      .schema-legend-swatch--templates { background: #eef2ff; }
      .schema-legend-swatch--instances { background: #ecfdf5; }

      /* The graph canvas is a four-node illustration, not a ten-table
         schema, so it needs nothing like the height */
      .schema-diagram--graph {
        height: 42vh;
        min-height: 340px;
      }

      /* Wide statements scroll inside their own box rather than stretching
         the page */
      .schema-sql {
        overflow-x: auto;
        padding: 10px 12px;
        border: 1px solid #e5e7eb;
        border-radius: 8px;
        background: #fafafa;
        font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
        font-size: 11px;
        line-height: 1.5;
        color: #111827;
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

      // The table node: a header naming the Ecto schema and the table behind
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
          const classes = ["schema-node", `schema-node--${data.group}`]
          if (data.primary) classes.push("schema-node--primary")

          return h("div", {className: classes.join(" ")},
            h("div", {className: "schema-node__header"},
              h("span", {className: "schema-node__schema"},
                data.schema,
                data.primary && h("span", {className: "schema-node__star"}, "\u2605")
              ),
              h("span", {className: "schema-node__table"}, data.table)
            ),
            data.columns.map((column) =>
              h("div", {className: "schema-node__row", key: column.name},
                column.handle &&
                  h(Handle, {...handles[column.handle], id: column.name, isConnectable: false}),
                h("span", {className: "schema-node__name"}, column.name),
                column.key && h("span", {className: "schema-node__key"}, column.key),
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
