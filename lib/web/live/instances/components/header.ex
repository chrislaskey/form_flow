defmodule FormFlow.Web.Instances.Components.Header do
  @moduledoc """
  `FormFlow.Web.Instances.Components.Header` function component renders the
  header every instance page puts above its own content, the same shape as
  the templates side's `FormFlow.Web.Templates.Components.Header`: what the
  page is about on the left, its actions on the right.

  The left side is two lines. On top, small, the **breadcrumb** - Flows /
  the flow instance / this form - the trail back out, ending in the page
  itself, unlinked. Under it the **title** names the thing on the page: the
  form's label with "in <flow>" lighter after it, the flow instance's name,
  or "Flows" on the listing. What the page has to say about the thing - when
  it was started, which flow - is not here: it is the fact sheet in the
  page's body. The one exception is a form's **status** badge - Draft,
  Submitted, Reopened - which reads with the name, so the `status` slot
  sits at the end of the title line. A `description` is one line under the
  title for a page that needs to say what it shows. The right side is the
  page's `actions`.

  Side by side only where there is room for both; below `xl` the two stack.

  A form page's header **pins** (`sticky`): the title, the status, the
  tabs, the last event, and the buttons stay at the top of the window while
  the form scrolls under them, so Submit is never further away than the
  top of the screen. The listing and the flow instance's page do not pin -
  nothing on them is an action on what scrolls.

      <Header.header base={@base} flow_instance={@flow_instance} flow_name={@flow_name}>
        <:actions>
          <Core.button navigate={...}>Download PDF</Core.button>
        </:actions>
      </Header.header>

  Which page it is comes from what is given. `flow_instance` and
  `flow_name` alone are the instance's own page; `label` on top of them is
  a form inside it; neither is the listing. Every page draws it in every
  state it can be in - refused, not started, ready - so a page with nothing
  to show is still recognisably the page.
  """

  use Phoenix.Component

  alias FormFlow.Web.Instances.Paths

  attr(:base, :string, required: true)

  attr(:flow_instance, :map,
    default: nil,
    doc: "the `FormFlow.Data.Instances.Flow` the page is inside; nil on the listing"
  )

  attr(:flow_name, :string, default: nil, doc: "the flow's name, beside `flow_instance`")

  attr(:label, :string,
    default: nil,
    doc: "the form's label as the trail says it - the page is a form inside the flow instance"
  )

  attr(:title, :string,
    default: nil,
    doc:
      "the form's own name for the title line, when the trail's label carries more - " <>
        "\"Applicant / Owner Information\" in the trail, \"Owner Information\" as the title"
  )

  attr(:description, :string,
    default: nil,
    doc: "one line under the title saying what the page shows"
  )

  attr(:sticky, :boolean,
    default: false,
    doc: "the header stays at the top of the window while the page scrolls"
  )

  slot(:status, doc: "a form's status badge, at the end of the title line")
  slot(:actions, doc: "the page's buttons, right-aligned")

  def header(assigns) do
    ~H"""
    <div class={[
      "mb-4 flex flex-col gap-3 xl:flex-row xl:items-center xl:justify-between",
      @sticky && "sticky top-0 z-10 -mx-2 border-b border-zinc-200 bg-white/95 px-2 pt-4 pb-3 backdrop-blur"
    ]}>
      <div class="min-w-0">
        <nav aria-label="Breadcrumb" class="flex flex-wrap items-center gap-x-1.5 text-xs text-zinc-500">
          <%= if @flow_instance do %>
            <.link navigate={Paths.flows_path(@base)} class="hover:underline">Flows</.link>
            <span class="text-zinc-400">/</span>
            <%= if @label do %>
              <.link navigate={Paths.flow_path(@base, @flow_instance.id)} class="hover:underline">
                {@flow_name}
              </.link>
              <span class="text-zinc-400">/</span>
              <span class="text-zinc-700">{@label}</span>
            <% else %>
              <span class="text-zinc-700">{@flow_name}</span>
            <% end %>
          <% else %>
            <span class="text-zinc-700">Flows</span>
          <% end %>
        </nav>
        <h2 class="mt-1 flex flex-wrap items-center gap-x-2 text-2xl font-semibold leading-tight">
          <span>{title(assigns)}</span>
          <span :if={@label && @flow_instance} class="text-base font-normal text-zinc-400">
            in {@flow_name}
          </span>
          {render_slot(@status)}
        </h2>
        <p :if={@description} class="mt-0.5 text-sm text-zinc-500">{@description}</p>
      </div>
      <div :if={@actions != []} class="flex flex-wrap items-center gap-2 xl:shrink-0 xl:flex-nowrap">
        {render_slot(@actions)}
      </div>
    </div>
    """
  end

  defp title(%{title: title}) when is_binary(title), do: title
  defp title(%{label: label}) when is_binary(label), do: label
  defp title(%{flow_instance: %{}, flow_name: name}), do: name
  defp title(_listing), do: "Flows"
end
