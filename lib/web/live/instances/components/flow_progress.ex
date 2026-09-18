defmodule FormFlow.Web.Instances.Components.Flows.Progress do
  @moduledoc """
  `FormFlow.Web.Instances.Components.Flows.Progress` function component renders
  a "forms" flow's forms and where the user is among them - the card under a
  form page's header, above the form they are filling.

  The card is one row: a ring on the left, how far along as a percentage
  inside it - the step over the count - with the steps behind the user in
  the brand colour and the one they are on in a lighter tint of it; then a
  link back to the flow instance's page, the flow's name, and "Step 2 of 5
  · next Health Information"; then **Show steps** on the right. The steps
  themselves are folded away by default, because a percentage and a next
  step are what most visits need, and unfold inside the card in columns -
  the current one bold, done ones checked, the ones ahead grey - because
  the order can change and a percentage alone does not show it.

  The component is type-agnostic: it draws what it is given. Whether to draw
  it at all and where each step goes (`step_links`) are the flow type's
  decisions - `progress_component/1` and `editable?/2` of
  `FormFlow.Config.Flows.Type` - asked by `FormFlow.Web.Instances.Forms.Shared`.

  A step links one of two ways, and `step_links` says which by path: `:edit`
  to the position's edit page - which is the page that starts it, so jumping
  needs no event of its own - and `:view` to its answers, which is where a
  submitted form belongs (its edit page only says it was submitted
  already). A path `step_links` has no entry for is the same row as plain
  text, the current form among them. The row is identical either way, so the
  list doesn't shift as forms become reachable; the link only wraps it.

  So an in-order wizard's steps read back: the forms behind the user link to
  their answers, the one they are on is plain, the ones ahead are plain and
  grey. An any-order wizard's all link - what is done to its answers, the
  rest to its form.

  `badge/1` lives here too: the wording and the palette of a form's state,
  shared with the flow instance page's listing so the two can't drift. So
  does `ring/1`, which that page draws for the whole flow and for each
  subflow (`FormFlow.Web.Instances.Flows.Show`).
  """

  use Phoenix.Component

  alias FormFlow.Web.Components.Core
  alias FormFlow.Web.Instances.Paths

  attr(:id, :string, required: true)
  attr(:base, :string, required: true, doc: "the router's mount prefix, for the links")
  attr(:flow_instance_id, :string, required: true)
  attr(:forms, :list, required: true, doc: "one \"forms\" flow's forms, in order")
  attr(:current_path, :list, default: nil, doc: "the form being filled, if any")
  attr(:components, :atom, default: nil)

  attr(:context, :any,
    default: nil,
    doc: "the page's `FormFlow.Context`, for the flow's and subflow's names"
  )

  attr(:step_links, :map,
    default: %{},
    doc:
      "where each step links, `:view` or `:edit` by path - a path absent " <>
        "from it is drawn as plain text, and so the current form always is"
  )

  # Called as a plain function by the flow type's `progress_component/1`,
  # with a map rather than a component's assigns - so merged, not
  # assign/2'd, and rendered without change tracking
  def flow_progress(assigns) do
    count = length(assigns.forms)
    step = Enum.find_index(assigns.forms, &(&1.path == assigns.current_path))
    step = step && step + 1
    done = Enum.count(assigns.forms, &(&1.status == :completed))
    percent = if step, do: round(step / count * 100), else: round(done / count * 100)
    behind = if step, do: round((step - 1) / count * 100), else: round(done / count * 100)
    next = step && Enum.at(assigns.forms, step)

    assigns =
      Map.merge(assigns, %{
        count: count,
        step: step,
        percent: percent,
        behind: behind,
        each: round(100 / count),
        next: next,
        flow_name: flow_name(assigns[:context]),
        subflow_name: subflow_name(assigns[:context]),
        step_links: assigns[:step_links] || %{},
        components: assigns[:components]
      })

    ~H"""
    <details id={@id} class="group/progress mb-6 rounded-2xl border border-zinc-300">
      <summary class="flex cursor-pointer list-none flex-wrap items-center gap-5 px-5 py-4 [&::-webkit-details-marker]:hidden">
        <.ring percent={@percent} behind={@behind} each={@each} />
        <div class="min-w-0 flex-1">
          <p class="text-xs text-zinc-500">
            <.link navigate={Paths.flow_path(@base, @flow_instance_id)} class="hover:underline">
              ← Back to flow overview
            </.link>
          </p>
          <p class="truncate text-lg font-semibold leading-tight">{@flow_name}</p>
          <p class="text-sm text-zinc-500">
            <span :if={@subflow_name}>{@subflow_name} ·</span>
            <span :if={@step}>Step {@step} of {@count}</span>
            <span :if={!@step}>{@count} steps</span>
            <span :if={@next}>· next {@next.label}</span>
          </p>
        </div>
        <span class="flex items-center gap-1 text-sm text-cyan-600">
          <span class="group-open/progress:hidden">Show steps</span>
          <span class="hidden group-open/progress:inline">Hide steps</span>
          <Core.icon
            components={@components}
            name="hero-chevron-down"
            class="size-4 transition-transform group-open/progress:rotate-180"
          />
        </span>
      </summary>
      <ol class="grid grid-cols-2 gap-x-6 gap-y-1.5 border-t border-zinc-200 px-5 py-4 text-sm sm:grid-cols-3 lg:grid-cols-4">
        <li
          :for={{form, index} <- Enum.with_index(@forms, 1)}
          class={[
            "flex items-center gap-2",
            form.path == @current_path && "font-semibold",
            form.status in [:available, :pending] && form.path != @current_path && "text-zinc-400"
          ]}
          aria-current={form.path == @current_path && "step"}
        >
          <span class={[
            "w-5 shrink-0 text-right font-mono text-xs tabular-nums",
            form.status == :completed && "text-primary"
          ]}>
            {marker(form.status, index)}
          </span>
          <% target = @step_links[form.path] %>
          <.link
            :if={target}
            navigate={step_path(target, @base, @flow_instance_id, form.path)}
            class="truncate hover:underline"
          >
            {form.label}
          </.link>
          <span :if={is_nil(target)} class="truncate">{form.label}</span>
          <span class="sr-only">- {elem(badge(form.status), 0)}</span>
        </li>
      </ol>
    </details>
    """
  end

  attr(:percent, :integer, required: true, doc: "the number inside")
  attr(:behind, :integer, required: true, doc: "what is done, as a percentage - the brand colour")
  attr(:each, :integer, required: true, doc: "what is under way, as a percentage - the tint")

  attr(:size, :atom,
    default: :lg,
    values: [:lg, :sm],
    doc: ":lg is the card's, with a percent sign; :sm fits a heading line"
  )

  @doc """
  The two-tone ring every progress surface draws: what is done in the brand
  colour, what is under way in a lighter tint of it, what is ahead grey,
  with a number inside. On a form page the tint is the step the user is
  on; on the flow instance's page it is the forms in progress. `pathLength`
  lets the dashes be percentages whatever the radius.
  """
  def ring(assigns) do
    ~H"""
    <span class={[
      "relative grid shrink-0 place-items-center",
      if(@size == :lg, do: "size-16", else: "size-9")
    ]}>
      <svg viewBox="0 0 36 36" class="absolute inset-0 -rotate-90" aria-hidden="true">
        <circle cx="18" cy="18" r="15.5" fill="none" stroke="currentColor" stroke-width="3" class="text-zinc-200" />
        <circle
          cx="18"
          cy="18"
          r="15.5"
          fill="none"
          stroke="currentColor"
          stroke-width="3"
          pathLength="100"
          stroke-dasharray={"#{@each} 100"}
          stroke-dashoffset={-@behind}
          class="text-primary/30"
        />
        <circle
          :if={@behind > 0}
          cx="18"
          cy="18"
          r="15.5"
          fill="none"
          stroke="currentColor"
          stroke-width="3"
          pathLength="100"
          stroke-dasharray={"#{@behind} 100"}
          class="text-primary"
        />
      </svg>
      <span class={[
        "relative font-semibold tabular-nums",
        if(@size == :lg, do: "text-base", else: "text-[10px]")
      ]}>
        {@percent}<span :if={@size == :lg} class="text-xs text-zinc-400">%</span>
      </span>
    </span>
    """
  end

  @doc """
  A form's derived status as `{text, kind}` - the wording and the
  `FormFlow.Web.CoreComponents.badge/1` palette every surface showing
  progress uses.
  """
  def badge(:completed), do: {"Done", :success}
  def badge(:in_progress), do: {"In progress", :warning}
  def badge(:available), do: {"Available", :info}
  def badge(_pending), do: {"Pending", :neutral}

  defp step_path(:edit, base, id, path), do: Paths.form_edit_path(base, id, path)
  defp step_path(:view, base, id, path), do: Paths.form_path(base, id, path)

  defp marker(:completed, _index), do: "✓"
  defp marker(_status, index), do: index

  # The names on the card come from the page's context when it has one; the
  # subflow's only when it is not the flow itself, so a simple flow's card
  # says its name once
  defp flow_name(%{flow: %{name: name}}) when is_binary(name), do: name
  defp flow_name(_context), do: "This flow"

  defp subflow_name(%{flow: %{id: id}, subflow: %{id: sub_id, name: name}})
       when id != sub_id and is_binary(name),
       do: name

  defp subflow_name(_context), do: nil
end
