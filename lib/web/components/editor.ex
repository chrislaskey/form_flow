defmodule FormFlow.Web.Components.Editor do
  @moduledoc """
  `FormFlow.Web.Components.Editor` function component renders the ReactFlow
  editor canvas.

  The editor itself is React and ReactFlow, served by `FormFlow.Web.Assets` and
  fetched at runtime by the colocated hook below. Only pages that render this
  component download it — nothing is added to the host application's `app.js`
  beyond the hook itself.

  The hook is the only channel between Elixir and React, because the container
  is `phx-update="ignore"` and LiveView never diffs what React renders:

    * React to Elixir — `pushEventTo(this.el, ...)`, which lands in the
      `handle_event/3` of the LiveComponent passed as `target`:
      `"form_flow:editor_mounted"` once the bundle has loaded, and
      `"form_flow:graph_changed"` with `%{"nodes" => ..., "edges" => ...}` on
      every meaningful edit
    * Elixir to React — `push_event/3` with the `form_flow:set_graph` event,
      picked up by `handleEvent` in the hook

  Used by the Flows LiveComponents:

      <Editor.editor id={"\#{@id}-editor"} data={@data} target={@myself} />
  """

  use Phoenix.Component

  alias FormFlow.Web.Assets
  alias FormFlow.Web.Helpers.ReactFlow

  attr(:id, :string, required: true)
  attr(:data, :map, required: true, doc: "ReactFlow data, see FormFlow.Web.Helpers.ReactFlow")
  attr(:target, :any, required: true, doc: "the LiveComponent receiving the editor's events")

  attr(:editable, :boolean,
    default: true,
    doc: "false renders a read-only canvas: pan and zoom, but no changes"
  )

  def editor(assigns) do
    ~H"""
    <%!-- ReactFlow needs explicit dimensions, and the canvas should not depend
          on the host application's CSS to be visible at all --%>
    <div
      id={@id}
      phx-hook=".Editor"
      phx-update="ignore"
      phx-target={@target}
      data-src={Assets.editor_path()}
      data-editable={to_string(@editable)}
      data-graph={ReactFlow.to_json(@data)}
      style="height: 480px; border: 1px solid #d4d4d8; border-radius: 8px; overflow: hidden;"
    >
    </div>
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
              graph: JSON.parse(this.el.dataset.graph),
              editable: this.el.dataset.editable !== "false",
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
    """
  end
end
