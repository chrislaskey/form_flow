defmodule FormFlow.Web.Templates.Flows.Index do
  @moduledoc """
  `FormFlow.Web.Templates.Flows.Index` LiveComponent renders the flow editor.

  The editor itself is React and ReactFlow, served by `FormFlow.Web.Assets` and
  fetched at runtime by the colocated hook below. Only pages that render this
  component download it — nothing is added to the host application's `app.js`
  beyond the hook itself.

  The hook is the only channel between Elixir and React, because the container is
  `phx-update="ignore"` and LiveView never diffs what React renders:

    * React to Elixir — `pushEventTo(this.el, ...)`, which lands in this
      component's `handle_event/3` rather than the host's LiveView. The container
      also carries `phx-target={@myself}`, which is what routes events to the
      component in `Phoenix.LiveViewTest.render_hook/3`
    * Elixir to React — `push_event/3` with the `form_flow:set_graph` event,
      picked up by `handleEvent` in the hook

  Callers pass what they want drawn as `data`, in ReactFlow's own shape — see
  `FormFlow.Web.Helpers.ReactFlow`:

      <.live_component module={FormFlow.Web.Templates.Flows.Index} id="flows" data={@data} />

  Past the `data-graph` attribute it becomes a graph of nodes and edges, which is
  ReactFlow's own vocabulary — hence the naming shift at that boundary.
  """

  use Phoenix.LiveComponent

  alias FormFlow.Web.Assets
  alias FormFlow.Web.Helpers.ReactFlow

  @impl true
  def mount(socket) do
    {:ok, assign(socket, editor_loaded?: false, nodes: [], edges: [])}
  end

  @impl true
  def update(assigns, socket) do
    # The parent may pass its own data; otherwise show this flow's default.
    # Either way the definition is Elixir, not JS.
    data = Map.get(assigns, :data) || default_data()

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:data, data)}
  end

  @impl true
  def handle_event("form_flow:reset_data", _params, socket) do
    # Elixir to React: the same data, pushed at runtime instead of on first paint.
    # The event name and payload key stay ReactFlow's vocabulary, since the hook
    # hands them straight to the editor.
    {:noreply, push_event(socket, "form_flow:set_graph", %{graph: socket.assigns.data})}
  end

  @impl true
  def handle_event("form_flow:editor_mounted", _params, socket) do
    {:noreply, assign(socket, :editor_loaded?, true)}
  end

  @impl true
  def handle_event("form_flow:graph_changed", %{"nodes" => nodes, "edges" => edges}, socket) do
    {:noreply, assign(socket, nodes: nodes, edges: edges)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="mb-2 flex items-center justify-between gap-4">
        <h2 class="text-sm font-semibold">Flow editor</h2>
        <button
          :if={@editor_loaded?}
          type="button"
          phx-click="form_flow:reset_data"
          phx-target={@myself}
          class="rounded-md border border-zinc-300 px-2 py-1 text-xs hover:border-cyan-600 hover:text-cyan-600"
        >
          Reset to the Elixir definition
        </button>
        <p class="text-xs text-zinc-500">
          <%= if @editor_loaded? do %>
            {length(@nodes)} steps, {length(@edges)} connections
          <% else %>
            Loading the editor…
          <% end %>
        </p>
      </div>

      <%!-- ReactFlow needs explicit dimensions, and the canvas should not depend
            on the host application's CSS to be visible at all --%>
      <div
        id={"#{@id}-editor"}
        phx-hook=".Editor"
        phx-update="ignore"
        phx-target={@myself}
        data-src={Assets.editor_path()}
        data-graph={ReactFlow.to_json(@data)}
        style="height: 480px; border: 1px solid #d4d4d8; border-radius: 8px; overflow: hidden;"
      >
      </div>

      <p :if={@editor_loaded? and @nodes != []} class="mt-2 text-xs text-zinc-500">
        Steps: {@nodes |> Enum.map(&step_label/1) |> Enum.join(", ")}
      </p>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".Editor">
        export default {
          async mounted() {
            try {
              // A runtime specifier on purpose: the host's bundler cannot resolve
              // it, so React is fetched by the browser instead of being inlined
              // into their app.js. See FormFlow.Web.Assets.
              const editor = await import(this.el.dataset.src)

              editor.injectStyles()

              this.editor = editor.mount(this.el, {
                // Defined in Elixir, serialized by ReactFlow.to_json/1, rendered here
                graph: JSON.parse(this.el.dataset.graph),
                onChange: (graph) => this.pushEventTo(this.el, "form_flow:graph_changed", graph)
              })

              this.handleEvent("form_flow:set_graph", ({graph}) => this.editor.setGraph(graph))

              this.pushEventTo(this.el, "form_flow:editor_mounted", {})
            } catch (error) {
              console.error("[form_flow] could not load the editor", error)

              this.el.textContent =
                "The flow editor failed to load from " + this.el.dataset.src +
                ". Is form_flow_assets() declared in the router?"
            }
          },

          destroyed() {
            this.editor?.unmount()
          }
        }
      </script>
    </div>
    """
  end

  # The flow shown when the parent passes no data of its own. Written in
  # ReactFlow's own shape — positions and edges included, because ReactFlow
  # requires the first and never infers the second. `deletable: false` pins the
  # start and end steps; every flow needs both, so neither can be removed.
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

  defp step_label(%{"data" => %{"label" => label}}), do: label
  defp step_label(%{"id" => id}), do: id
  defp step_label(_node), do: "step"
end
