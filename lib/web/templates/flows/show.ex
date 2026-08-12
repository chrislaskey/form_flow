defmodule FormFlow.Web.Templates.Flows.Show do
  @moduledoc """
  `FormFlow.Web.Templates.Flows.Show` LiveComponent renders the flow editor.

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
  """

  use Phoenix.LiveComponent

  alias FormFlow.Web.Assets

  @impl true
  def mount(socket) do
    {:ok, assign(socket, editor_loaded?: false, nodes: [], edges: [])}
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

  defp step_label(%{"data" => %{"label" => label}}), do: label
  defp step_label(%{"id" => id}), do: id
  defp step_label(_node), do: "step"
end
