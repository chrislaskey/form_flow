defmodule FormFlow.Web.Templates.Components.Breadcrumb do
  @moduledoc """
  `FormFlow.Web.Templates.Components.Breadcrumb` function component renders
  the Templates / Flows|Forms / Root / Parent trail every templates page
  puts above its own content: `FormFlow.Web.Templates.Flows.Show`, `.Edit`,
  and `FormFlow.Web.Templates.Forms.Show`, `.Edit`. Each page supplies only
  its own trailing crumb — its own name, plus whatever subtitle spans ride
  beside it — through `inner_block`.

  A drill-in (`root` given) always walks through "Flows", whichever kind of
  page sits at the end of it — reaching a form or a subflow both mean
  walking the flows tree to get there. Without a root, the page names its
  own top-level section instead (`section`): `"flows"` for a flow shown or
  edited directly, `"forms"` for a form from the catalog.

  `root` and `parent_node` are the structs the four pages already load
  (`FormFlow.Data.Templates.Flow` and `.Flow.Node`) — `nil` for either skips
  its crumb. `parent_node` is the *immediate* embedding node
  (`FormFlow.Data.Templates.Flows.embedding_node/2`), which is as far back
  as a breadcrumb goes regardless of how many levels a form is actually
  nested.

  `mode` decides whether the Root and Parent crumbs target their flow's
  edit page or its show page — `"edit"` for the one, anything else (`nil`
  included) for the other. It answers "was the visitor editing this flow
  before they got here", not "is this page itself in edit mode":
  `FormFlow.Web.Templates.Flows.Edit`'s own breadcrumb is sticky by
  construction — Root always targets `.../edit` — so it passes the literal
  `"edit"`, while the form pages pass whatever query string got them here
  (see `FormFlow.Web.Helpers.Paths.preserve_query_params/3`'s `mode`),
  since crossing into a form is ordinarily where stickiness ends (see that
  module's own moduledoc).

  Two navigation styles, matched to what the rest of the page already does:

    * `target` set (only `Flows.Edit` passes one, its own `@myself`) — every
      crumb pushes `"navigate"` with `phx-value-to` instead of linking
      directly, the same event the canvas's own Show button and Open use,
      so an unsaved edit still prompts before the crumb discards it.
    * `target` unset (every other page) — a plain `<.link navigate>`.
  """

  use Phoenix.Component

  import FormFlow.Web.Helpers.Paths

  alias FormFlow.Web.Components.Core

  attr(:base, :string, required: true)
  attr(:section, :string, required: true, values: ~w(flows forms))

  attr(:root, :map,
    default: nil,
    doc: "the root `FormFlow.Data.Templates.Flow` — nil outside a drill-in"
  )

  attr(:parent_node, :map,
    default: nil,
    doc: "the immediate embedding `FormFlow.Data.Templates.Flow.Node` — form pages only"
  )

  attr(:mode, :string, default: nil, doc: ~s(\"edit\" routes Root/Parent to their edit pages))

  attr(:target, :any,
    default: nil,
    doc: "set to guard every crumb through the \"navigate\" event instead of linking directly"
  )

  attr(:components, :atom, default: nil)
  slot(:inner_block, required: true, doc: "the page's own trailing crumb and subtitle spans")

  def breadcrumb(assigns) do
    ~H"""
    <div class={[
      "text-sm font-semibold",
      @target && "flex items-center gap-2"
    ]}>
      <.crumb to={templates_path(@base)} target={@target} components={@components}>
        Templates
      </.crumb>
      <span class="text-zinc-400">/</span>
      <%= if @root do %>
        <.crumb to={"#{@base}/flows"} target={@target} components={@components}>Flows</.crumb>
        <span class="text-zinc-400">/</span>
        <.crumb to={flow_path(@base, @root.id, @mode)} target={@target} components={@components}>
          {@root.name || "Untitled"}
        </.crumb>
        <span class="text-zinc-400">/</span>
        <.crumb
          :if={@parent_node}
          to={node_path(@base, @root.id, @parent_node.id, @mode)}
          target={@target}
          components={@components}
        >
          {parent_node_label(@parent_node)}
        </.crumb>
        <span :if={@parent_node} class="text-zinc-400">/</span>
      <% else %>
        <.crumb to={"#{@base}/#{@section}"} target={@target} components={@components}>
          {String.capitalize(@section)}
        </.crumb>
        <span class="text-zinc-400">/</span>
      <% end %>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr(:to, :string, required: true)
  attr(:target, :any, default: nil)
  attr(:components, :atom, default: nil)
  slot(:inner_block, required: true)

  defp crumb(%{target: nil} = assigns) do
    ~H"""
    <.link navigate={@to} class="hover:underline">{render_slot(@inner_block)}</.link>
    """
  end

  defp crumb(assigns) do
    ~H"""
    <Core.button
      components={@components}
      phx-click="navigate"
      phx-value-to={@to}
      phx-target={@target}
      class="hover:underline"
    >
      {render_slot(@inner_block)}
    </Core.button>
    """
  end

  defp parent_node_label(node), do: get_in(node.properties, ["data", "label"]) || "Subflow"

  defp flow_path(base, flow_id, "edit"), do: "#{base}/flows/#{flow_id}/edit"
  defp flow_path(base, flow_id, _mode), do: "#{base}/flows/#{flow_id}"

  defp node_path(base, root_id, node_id, "edit"),
    do: "#{base}/flows/#{root_id}/nodes/#{node_id}/edit"

  defp node_path(base, root_id, node_id, _mode), do: "#{base}/flows/#{root_id}/nodes/#{node_id}"
end
