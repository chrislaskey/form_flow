defmodule FormFlow.Web.Components.Overview do
  @moduledoc """
  `FormFlow.Web.Components.Overview` function component renders the overview
  canvas: the whole flow, every level at once, read-only.

  The canvas is the same React bundle as `FormFlow.Web.Components.Editor`'s
  (served by `FormFlow.Web.Assets`), mounted through its `mountOverview`
  export instead of `mount`, so a page showing both downloads it once. What
  it draws is a *tree* — `FormFlow.Web.Helpers.ReactFlow.to_tree_data/1` —
  with every subflow node expanded into a group holding its inner flow. The
  bundle lays it out; nothing here has a position.

  The hook is the only channel between Elixir and React, the container being
  `phx-update="ignore"`, and it runs one way. React pushes to Elixir with
  `pushEventTo(this.el, ...)`, landing in the `handle_event/3` of the
  LiveComponent passed as `target`: `"form_flow:overview_mounted"` once the
  bundle has loaded, `"form_flow:open_subflow"` with `%{"node_id" => ...}`
  from a group's Open button, and `"form_flow:open_form"` likewise from a
  form node's. Nothing goes the other way — unlike
  `FormFlow.Web.Components.Editor`, which pushes a saved flow back with
  `form_flow:set_flow` so editor-temporary node ids become real ones, this
  page never saves, so the tree it mounts with is the tree it draws until a
  fresh page arrives.

  Used by `FormFlow.Web.Templates.Flows.Overview`:

      <Overview.overview id={"\#{@id}-overview"} tree={@tree} target={@myself} />
  """

  use Phoenix.Component

  alias FormFlow.Web.Assets
  alias FormFlow.Web.Helpers.ReactFlow

  attr(:id, :string, required: true)

  attr(:tree, :map,
    required: true,
    doc: "nested ReactFlow data, see FormFlow.Web.Helpers.ReactFlow.to_tree_data/1"
  )

  attr(:target, :any, required: true, doc: "the LiveComponent receiving the canvas's events")

  attr(:form_flow_type_options, :list,
    default: [],
    doc:
      "form_flow_type choices as {label, value} tuples, so a form subflow's " <>
        "group header can name its stored type"
  )

  attr(:form_type_options, :list,
    default: [],
    doc: "form_type choices as {label, value} tuples, so a form node can name its stored type"
  )

  attr(:perspective_options, :list,
    default: [],
    doc:
      "perspective names as {label, value} tuples, so a form subflow's group " <>
        "header can name who it is for"
  )

  def overview(assigns) do
    assigns =
      assign(assigns,
        form_flow_type_options_json: options_json(assigns.form_flow_type_options),
        form_type_options_json: options_json(assigns.form_type_options),
        perspective_options_json: options_json(assigns.perspective_options)
      )

    ~H"""
    <%!-- Taller than the editor's canvas: this one holds every level. The
          viewport height keeps it on one screen whatever the flow's size;
          zoom and the minimap do the rest. --%>
    <div
      id={@id}
      phx-hook=".Overview"
      phx-update="ignore"
      phx-target={@target}
      data-src={Assets.editor_path()}
      data-form-flow-type-options={Phoenix.json_library().encode!(@form_flow_type_options_json)}
      data-form-type-options={Phoenix.json_library().encode!(@form_type_options_json)}
      data-perspective-options={Phoenix.json_library().encode!(@perspective_options_json)}
      data-tree={ReactFlow.to_json(@tree)}
      style="height: calc(100vh - 220px); min-height: 480px; border: 1px solid #d4d4d8; border-radius: 8px; overflow: hidden;"
    >
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Overview">
      export default {
        async mounted() {
          try {
            // The same runtime import as the editor's hook, for the same
            // reason: React is fetched by the browser, never inlined into
            // the host's app.js. See FormFlow.Web.Assets.
            const editor = await import(this.el.dataset.src)

            editor.injectStyles()

            this.overview = editor.mountOverview(this.el, {
              tree: JSON.parse(this.el.dataset.tree),
              formFlowTypeOptions: JSON.parse(this.el.dataset.formFlowTypeOptions),
              formTypeOptions: JSON.parse(this.el.dataset.formTypeOptions),
              perspectiveOptions: JSON.parse(this.el.dataset.perspectiveOptions),
              onOpenSubflow: (nodeId) =>
                this.pushEventTo(this.el, "form_flow:open_subflow", {node_id: nodeId}),
              onOpenForm: (nodeId) =>
                this.pushEventTo(this.el, "form_flow:open_form", {node_id: nodeId})
            })

            this.pushEventTo(this.el, "form_flow:overview_mounted", {})
          } catch (error) {
            console.error("[form_flow] could not load the overview", error)

            this.el.textContent =
              "The flow overview failed to load from " + this.el.dataset.src +
              ". Is form_flow_router_asset_routes() declared in the router?"
          }
        },

        destroyed() {
          this.overview?.unmount()
        }
      }
    </script>
    """
  end

  defp options_json(options),
    do: for({label, value} <- options, do: %{label: label, value: value})
end
