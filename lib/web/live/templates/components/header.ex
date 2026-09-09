defmodule FormFlow.Web.Templates.Components.Header do
  @moduledoc """
  `FormFlow.Web.Templates.Components.Header` function component renders the
  header every templates page puts above its own content: what the page is
  about on the left, its actions on the right.

  The left side is two lines. The **title** names the thing on the page —
  the root flow, then, lighter, the subflow or form reached inside it, then
  whatever the page has to say about it as `metadata` (its kind, its type,
  its version), each after a middle dot. Under it, smaller, the
  **breadcrumb**: Form Flow / Flows|Forms / Root / Parent / this page, the
  trail back out. The right side is the page's `actions` — buttons, in the
  order the page lists them.

      <Header.header base={@base} section="flows" root={@root} name={@flow.name}>
        <:metadata>Simple flow</:metadata>
        <:metadata :if={@type}>{@type.name}</:metadata>
        <:actions>
          <Core.button navigate={...}>Overview</Core.button>
        </:actions>
      </Header.header>

  `name` is what this page is about — the flow's or form's name. Without
  one the page is a section's index, whose section is its name: the title
  reads "Flows" and the trail ends there. Without a section either, the
  page is the templates landing — the root the first crumb, "⧉ Form Flow",
  always leads back to — so the title reads "Form Flow" and the trail is
  that one crumb. A `crumb` slot replaces the trailing crumb when the page
  wants more than the plain name — the form edit page links its name back
  to the show page.

  A drill-in (`root` given) always walks through "Flows", whichever kind of
  page sits at the end of it — reaching a form or a subflow both mean
  walking the flows tree to get there. Without a root, the page names its
  own top-level section instead (`section`): `"flows"` for a flow shown or
  edited directly, `"forms"` for a form from the catalog.

  `root` and `parent_node` are the structs the pages already load
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

  attr(:section, :string,
    default: nil,
    doc: ~s("flows" or "forms" — the section the page is in; nil on the landing)
  )

  attr(:name, :string,
    default: nil,
    doc: "what the page is about — a flow's or form's name; nil on a section's index"
  )

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

  slot(:metadata,
    doc: "what the page says about the thing — its kind, type, version — one per slot"
  )

  slot(:crumb, doc: "the trailing crumb, when it is more than the plain name")
  slot(:actions, doc: "the page's buttons, right-aligned")

  def header(assigns) do
    ~H"""
    <div class="mb-4 flex items-start justify-between gap-4">
      <div class="min-w-0">
        <h2 class="flex flex-wrap items-baseline gap-x-2 text-lg font-semibold leading-tight">
          <span>{title(assigns)}</span>
          <%= if @root && @name do %>
            <span class="text-zinc-300">·</span>
            <span class="font-normal text-zinc-500">{@name}</span>
          <% end %>
          <%= for metadata <- @metadata do %>
            <span class="text-zinc-300">·</span>
            <span class="text-sm font-normal text-zinc-500">{render_slot(metadata)}</span>
          <% end %>
        </h2>
        <nav
          aria-label="Breadcrumb"
          class={["mt-1 text-xs text-zinc-500", @target && "flex flex-wrap items-center gap-x-1.5"]}
        >
          <%= if @section do %>
            <.crumb to={templates_path(@base)} target={@target} components={@components}>
              <span aria-hidden="true">⧉</span> Form Flow
            </.crumb>
            <span class="text-zinc-400">/</span>
          <% else %>
            <span class="text-zinc-700"><span aria-hidden="true">⧉</span> Form Flow</span>
          <% end %>
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
            <%= if @name do %>
              <.crumb to={"#{@base}/#{@section}"} target={@target} components={@components}>
                {section_title(@section)}
              </.crumb>
              <span class="text-zinc-400">/</span>
            <% end %>
          <% end %>
          <%= cond do %>
            <% @crumb != [] -> %>
              <span class="text-zinc-700">{render_slot(@crumb)}</span>
            <% @name -> %>
              <span class="text-zinc-700">{@name}</span>
            <% @section -> %>
              <span class="text-zinc-700">{section_title(@section)}</span>
            <% true -> %>
          <% end %>
        </nav>
      </div>
      <div :if={@actions != []} class="flex shrink-0 items-center gap-2">
        {render_slot(@actions)}
      </div>
    </div>
    """
  end

  # The root flow's name leads a drill-in; otherwise the page's own name,
  # the section's on an index, or the root's on the landing
  defp title(%{root: %{} = root}), do: root.name || "Untitled"
  defp title(%{name: name}) when is_binary(name), do: name
  defp title(%{section: section}) when is_binary(section), do: section_title(section)
  defp title(_landing), do: "Form Flow"

  defp section_title(section), do: String.capitalize(section)

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
