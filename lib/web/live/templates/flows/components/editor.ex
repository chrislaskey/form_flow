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
      `"form_flow:editor_mounted"` once the bundle has loaded,
      `"form_flow:flow_changed"` with `%{"nodes" => ..., "edges" => ...}` on
      every meaningful edit, `"form_flow:open_subflow"` with
      `%{"node_id" => ...}` when a subflow node's Open button is clicked, and
      `"form_flow:open_form"` likewise for a form step's Open button
    * Elixir to React — `push_event/3` with the `form_flow:set_flow` event,
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

  attr(:flow_label, :string,
    default: "forms",
    doc: "the flow's declared flavor; picks the editor's add actions"
  )

  attr(:form_flow_type_options, :list,
    default: [],
    doc:
      "form_flow_type choices as {label, value} tuples — the configured " <>
        "`enabled_flow_types` as `FormFlow.Config.Flows.Type.select_options/1` " <>
        "gives them; form-subflow nodes render them as a dropdown when " <>
        "editable and as the value's label when not"
  )

  def editor(assigns) do
    assigns =
      assign(
        assigns,
        :form_flow_type_options_json,
        for({label, value} <- assigns.form_flow_type_options, do: %{label: label, value: value})
      )

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
      data-flow-label={@flow_label}
      data-form-flow-type-options={Phoenix.json_library().encode!(@form_flow_type_options_json)}
      data-flow={ReactFlow.to_json(@data)}
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
              flow: JSON.parse(this.el.dataset.flow),
              editable: this.el.dataset.editable !== "false",
              flowLabel: this.el.dataset.flowLabel,
              formFlowTypeOptions: JSON.parse(this.el.dataset.formFlowTypeOptions),
              onChange: (flow) => this.pushEventTo(this.el, "form_flow:flow_changed", flow),
              onOpenSubflow: (nodeId) =>
                this.pushEventTo(this.el, "form_flow:open_subflow", {node_id: nodeId}),
              onOpenForm: (nodeId) =>
                this.pushEventTo(this.el, "form_flow:open_form", {node_id: nodeId})
            })

            this.handleEvent("form_flow:set_flow", ({flow}) => this.editor.setFlow(flow))

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
