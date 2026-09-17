defmodule DemoWeb.ExplorationsLive.FormInstanceParts do
  @moduledoc """
  The UI components of the form instance page that more than one
  exploration draws: the T2 header, the status badge and save state, the
  F1 card and F3 rectangle with their step lists, the two-tone ring, the
  Edit / View / History tabs, A2's toolbar, and the inert form under it all.

  Shared by `DemoWeb.ExplorationsLive.FormInstanceContinued` and
  `DemoWeb.ExplorationsLive.FormInstanceReview`, so a direction picked on
  one page is drawn the same on the other. Everything here is scratch: the
  data is the pages' hardcoded step lists, and nothing is wired up.

  A step list is a list of maps with `n`, `label`, and `status` - `:done`,
  `:current`, or `:pending` - and, for a flow with subflows, a `group`.
  """

  use DemoWeb, :html

  @doc "The step the user is on."
  def current(forms), do: Enum.find(forms, &(&1.status == :current))

  @doc "How far along: the step the user is on over the count, as a percentage."
  def percent(forms), do: round(current(forms).n / length(forms) * 100)

  @doc "The step `offset` places from the current one, or nil."
  def neighbour(forms, offset) do
    n = current(forms).n + offset
    Enum.find(forms, &(&1.n == n))
  end

  @doc "The steps chunked by their subflow, in order."
  def groups(forms), do: Enum.chunk_by(forms, &Map.get(&1, :group))

  # -- Header (T2) -----------------------------------------------------------

  attr :forms, :list, required: true
  attr :status, :any, default: nil, doc: "ST1: a status badge after the title"
  attr :flow, :boolean, default: true, doc: "whether \"in Dog License\" follows the name"
  attr :class, :any, default: nil
  slot :title_aside, doc: "X3c: a control after the name, where the status badge would sit"
  slot :actions

  def page_header(assigns) do
    ~H"""
    <div class={["mb-4 flex flex-col gap-3 xl:flex-row xl:items-center xl:justify-between", @class]}>
      <div class="min-w-0">
        <nav
          aria-label="Breadcrumb"
          class="flex flex-wrap items-center gap-x-1.5 text-xs text-zinc-500"
        >
          <span class="hover:underline">Flows</span>
          <span class="text-zinc-400">/</span>
          <span class="hover:underline">Dog License</span>
          <span class="text-zinc-400">/</span>
          <span class="text-zinc-700">{current(@forms).label}</span>
        </nav>
        <h2 class="mt-1 flex flex-wrap items-center gap-x-2 text-2xl font-semibold leading-tight">
          <span>{current(@forms).label}</span>
          <span :if={@flow} class="text-base font-normal text-zinc-400">in Dog License</span>
          <.status_badge :if={@status} status={@status} />
          {render_slot(@title_aside)}
        </h2>
      </div>
      <div :if={@actions != []} class="flex flex-wrap items-center gap-2 xl:shrink-0 xl:flex-nowrap">
        {render_slot(@actions)}
      </div>
    </div>
    """
  end

  attr :status, :string, required: true
  attr :class, :any, default: nil

  def status_badge(assigns) do
    ~H"""
    <span class={[
      "badge badge-soft",
      case @status do
        "Draft" -> "badge-info"
        "Submitted" -> "badge-success"
        "Reopened" -> "badge-warning"
      end,
      @class
    ]}>
      {@status}
    </span>
    """
  end

  attr :prefix, :any, default: nil, doc: "ST3: the status as the first word"
  attr :who, :string, default: "dog_owner", doc: "the user_id that last saved"

  def save_state(assigns) do
    ~H"""
    <span class="mr-2 flex items-center gap-2 text-sm text-zinc-600">
      <span class="size-2 shrink-0 rounded-full bg-zinc-400" />
      <span>
        <span :if={@prefix}>{@prefix} · saved</span>
        <span :if={!@prefix}>Saved</span>
        <span class="text-zinc-500">· 3 min ago · {@who}</span>
      </span>
    </span>
    """
  end

  # -- F1 cards ----------------------------------------------------------------

  attr :id, :string, default: "card"
  attr :variant, :atom, required: true
  attr :forms, :list, required: true

  def card(%{variant: :plain} = assigns) do
    ~H"""
    <div class="mb-6 flex flex-wrap items-center gap-5 rounded-2xl border border-zinc-300 px-5 py-4">
      <.ring forms={@forms} size={:lg} />
      <.card_text forms={@forms} />
    </div>
    """
  end

  def card(%{variant: :toggle} = assigns) do
    ~H"""
    <details class="group/c mb-6 rounded-2xl border border-zinc-300">
      <summary class="flex cursor-pointer list-none flex-wrap items-center gap-5 px-5 py-4 [&::-webkit-details-marker]:hidden">
        <.ring forms={@forms} size={:lg} />
        <.card_text forms={@forms} />
        <span class="flex items-center gap-1 text-sm text-indigo-600">
          <span class="group-open/c:hidden">Show steps</span>
          <span class="hidden group-open/c:inline">Hide steps</span>
          <.icon name="hero-chevron-down" class="size-4 transition-transform group-open/c:rotate-180" />
        </span>
      </summary>
      <ol class="grid grid-cols-2 gap-x-6 gap-y-1.5 border-t border-zinc-200 px-5 py-4 text-sm sm:grid-cols-3 lg:grid-cols-4">
        <.step_row :for={form <- @forms} form={form} forms={@forms} />
      </ol>
    </details>
    """
  end

  def card(%{variant: :segments} = assigns) do
    ~H"""
    <div class="mb-6 overflow-hidden rounded-2xl border border-zinc-300">
      <div class="flex flex-wrap items-center gap-5 px-5 pt-4 pb-3">
        <.ring forms={@forms} size={:lg} />
        <.card_text forms={@forms} />
      </div>
      <.segments forms={@forms} class="mx-5 mb-4" />
    </div>
    """
  end

  def card(%{variant: :caret} = assigns) do
    ~H"""
    <div class="mb-6 flex flex-wrap items-center gap-5 rounded-2xl border border-zinc-300 px-5 py-4">
      <.ring forms={@forms} size={:lg} />
      <.card_text forms={@forms} />
      <.steps_dropdown id={"#{@id}-steps"} forms={@forms}>
        <span class="btn btn-ghost btn-sm btn-circle" aria-label="Show steps"><.icon
          name="hero-chevron-down"
          class="size-5"
        /></span>
      </.steps_dropdown>
    </div>
    """
  end

  attr :forms, :list, required: true

  def card_text(assigns) do
    ~H"""
    <div class="min-w-0 flex-1">
      <p class="text-xs text-zinc-500">
        <span class="hover:underline">← Back to flow overview</span>
      </p>
      <p class="truncate text-lg font-semibold leading-tight">Dog License</p>
      <p class="text-sm text-zinc-500">
        Step {current(@forms).n} of {length(@forms)}
        <span :if={neighbour(@forms, 1)}>· next {neighbour(@forms, 1).label}</span>
      </p>
    </div>
    """
  end

  # -- F3 rectangles ----------------------------------------------------------

  attr :id, :string, default: "pill"
  attr :variant, :atom, required: true
  attr :forms, :list, required: true

  def pill(%{variant: :rect} = assigns) do
    ~H"""
    <span class={pill_box()}>
      <.ring forms={@forms} size={:sm} />
      <.pill_text forms={@forms} />
    </span>
    """
  end

  def pill(%{variant: :caret} = assigns) do
    ~H"""
    <span class={[pill_box(), "pr-2"]}>
      <.ring forms={@forms} size={:sm} />
      <.pill_text forms={@forms} />
      <.steps_dropdown id={"#{@id}-steps"} forms={@forms}>
        <span class="btn btn-ghost btn-sm btn-circle" aria-label="Show steps"><.icon
          name="hero-chevron-down"
          class="size-5"
        /></span>
      </.steps_dropdown>
    </span>
    """
  end

  def pill(%{variant: :hover} = assigns) do
    ~H"""
    <span class={["group/h relative", pill_box()]}>
      <.ring forms={@forms} size={:sm} />
      <.pill_text forms={@forms} />
      <div class="invisible absolute right-0 top-full z-30 mt-1 w-64 opacity-0 transition group-hover/h:visible group-hover/h:opacity-100">
        <.steps_menu forms={@forms} />
      </div>
    </span>
    """
  end

  def pill(%{variant: :bar} = assigns) do
    ~H"""
    <span class={[pill_box(), "min-w-56 pl-4"]}>
      <span class="min-w-0 flex-1 leading-tight">
        <span class="flex items-baseline justify-between gap-3">
          <span class="text-sm font-semibold">Dog License</span>
          <span class="text-sm font-semibold tabular-nums">{percent(@forms)}%</span>
        </span>
        <span class="mt-1.5 block h-1 w-full overflow-hidden rounded-full bg-zinc-200">
          <span class="block h-full rounded-full bg-primary" style={"width: #{percent(@forms)}%"} />
        </span>
        <span class="mt-1 block text-xs text-zinc-500">
          Step {current(@forms).n} of {length(@forms)} ·
          <span class="hover:underline">back to flow overview</span>
        </span>
      </span>
    </span>
    """
  end

  def pill_box,
    do: "flex items-center gap-3 rounded-xl border border-zinc-300 bg-white py-2.5 pl-2.5 pr-5"

  attr :forms, :list, required: true

  def pill_text(assigns) do
    ~H"""
    <span class="leading-tight">
      <span class="block text-sm font-semibold">Dog License</span>
      <span class="block text-xs text-zinc-500">
        Step {current(@forms).n} of {length(@forms)} ·
        <span class="hover:underline">back to flow overview</span>
      </span>
    </span>
    """
  end

  # -- Steps, listed ------------------------------------------------------------

  # A <details> dropdown, as the demo's user switcher and the templates
  # index's row menu: the trigger is the slot, the menu is the steps
  attr :id, :string, required: true
  attr :forms, :list, required: true
  slot :inner_block, required: true

  def steps_dropdown(assigns) do
    ~H"""
    <details
      id={@id}
      class="dropdown dropdown-end"
      phx-click-away={Phoenix.LiveView.JS.remove_attribute("open")}
    >
      <summary class="flex cursor-pointer list-none [&::-webkit-details-marker]:hidden">
        {render_slot(@inner_block)}
      </summary>
      <div class="dropdown-content z-30 mt-1 w-64">
        <.steps_menu forms={@forms} />
      </div>
    </details>
    """
  end

  attr :forms, :list, required: true

  def steps_menu(assigns) do
    assigns = assign(assigns, :groups, groups(assigns.forms))

    ~H"""
    <div class="max-h-80 overflow-y-auto rounded-xl border border-zinc-200 bg-white py-1 text-sm shadow-lg">
      <%= for group <- @groups do %>
        <p
          :if={length(@groups) > 1}
          class="px-3 pb-0.5 pt-2 text-[10px] font-semibold uppercase tracking-wider text-zinc-400"
        >
          {Map.get(hd(group), :group)}
        </p>
        <ol>
          <.step_row :for={form <- group} form={form} forms={@forms} class="px-3 py-1" />
        </ol>
      <% end %>
    </div>
    """
  end

  attr :form, :map, required: true
  attr :forms, :list, required: true
  attr :class, :any, default: nil

  def step_row(assigns) do
    ~H"""
    <li
      class={[
        "flex items-center gap-2",
        @form.status == :current && "font-semibold",
        @form.n > current(@forms).n && "text-zinc-400",
        @class
      ]}
      aria-current={@form.status == :current && "step"}
    >
      <span class={[
        "w-5 shrink-0 text-right font-mono text-xs tabular-nums",
        @form.n < current(@forms).n && "text-primary"
      ]}>
        {@form.n}
      </span>
      <span class="truncate">{@form.label}</span>
    </li>
    """
  end

  attr :forms, :list, required: true
  attr :class, :any, default: nil

  def segments(assigns) do
    ~H"""
    <div class={["flex gap-px", @class]} role="list">
      <div
        :for={form <- @forms}
        role="listitem"
        title={"#{form.n}. #{form.label}"}
        class={[
          "h-1.5 flex-1 first:rounded-l-full last:rounded-r-full",
          cond do
            form.n < current(@forms).n -> "bg-primary/60"
            form.n == current(@forms).n -> "bg-primary"
            true -> "bg-zinc-200"
          end
        ]}
      />
    </div>
    """
  end

  # A two-tone ring: the steps behind the user in the brand colour, the
  # step they are on in a lighter tint of it, what is ahead grey. The number
  # inside is how far along they are - the step over the count. `pathLength`
  # lets the dashes be percentages whatever the radius.
  attr :forms, :list, required: true
  attr :size, :atom, required: true

  def ring(assigns) do
    count = length(assigns.forms)
    behind = round((current(assigns.forms).n - 1) / count * 100)
    step = round(100 / count)

    assigns = assign(assigns, behind: behind, step: step, percent: percent(assigns.forms))

    ~H"""
    <span class={[
      "relative grid shrink-0 place-items-center",
      if(@size == :lg, do: "size-16", else: "size-9")
    ]}>
      <svg viewBox="0 0 36 36" class="absolute inset-0 -rotate-90" aria-hidden="true">
        <circle
          cx="18"
          cy="18"
          r="15.5"
          fill="none"
          stroke="currentColor"
          stroke-width="3"
          class="text-zinc-200"
        />
        <circle
          cx="18"
          cy="18"
          r="15.5"
          fill="none"
          stroke="currentColor"
          stroke-width="3"
          pathLength="100"
          stroke-dasharray={"#{@step} 100"}
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
        "relative tabular-nums font-semibold",
        if(@size == :lg, do: "text-base", else: "text-[10px]")
      ]}>
        {@percent}<span :if={@size == :lg} class="text-xs text-zinc-400">%</span>
      </span>
    </span>
    """
  end

  # -- Tabs ---------------------------------------------------------------------

  @tab_items [edit: "Edit", view: "View", history: "History"]

  @doc "The three views of a form, as {path key, label}."
  def tab_items, do: @tab_items

  attr :variant, :atom, required: true
  attr :active, :atom, required: true
  attr :status, :any, default: nil, doc: "ST2: a status badge at the row's right"
  attr :size, :atom, default: :sm, doc: ":base for a toolbar's taller row"
  attr :class, :any, default: nil
  slot :aside, doc: "what sits at the row's right instead of, or beside, the status"

  def tabs(%{variant: :underline} = assigns) do
    assigns = assign(assigns, :items, @tab_items)

    ~H"""
    <div class={["flex items-center justify-between gap-4 border-b border-zinc-200", @class]}>
      <nav
        class={["-mb-px flex gap-6", if(@size == :base, do: "text-base", else: "text-sm")]}
        aria-label="Views"
      >
        <span
          :for={{key, label} <- @items}
          class={[
            "border-b-2",
            if(@size == :base, do: "pb-3", else: "pb-2.5"),
            if(key == @active,
              do: "border-primary font-semibold text-zinc-900",
              else: "border-transparent text-zinc-500 hover:text-zinc-900"
            )
          ]}
          aria-current={key == @active && "page"}
        >
          {label}
        </span>
      </nav>
      <span :if={@status || @aside != []} class="mb-2 flex items-center gap-3">
        {render_slot(@aside)}
        <.status_badge :if={@status} status={@status} />
      </span>
    </div>
    """
  end

  def tabs(%{variant: :segmented} = assigns) do
    assigns = assign(assigns, :items, @tab_items)

    ~H"""
    <div class={["flex items-center justify-between gap-4", @class]}>
      <nav class="inline-flex rounded-lg bg-zinc-100 p-0.5 text-sm" aria-label="Views">
        <span
          :for={{key, label} <- @items}
          class={[
            "rounded-md px-3 py-1",
            if(key == @active,
              do: "bg-white font-semibold shadow-sm",
              else: "text-zinc-500 hover:text-zinc-900"
            )
          ]}
          aria-current={key == @active && "page"}
        >
          {label}
        </span>
      </nav>
      <.status_badge :if={@status} status={@status} />
    </div>
    """
  end

  def tabs(%{variant: :links} = assigns) do
    assigns = assign(assigns, :items, @tab_items)

    ~H"""
    <div class={["flex items-center justify-between gap-4", @class]}>
      <nav class="flex items-center gap-2 text-sm" aria-label="Views">
        <%= for {{key, label}, index} <- Enum.with_index(@items) do %>
          <span :if={index > 0} class="text-zinc-300">·</span>
          <span
            class={
              if(key == @active,
                do: "font-semibold text-zinc-900",
                else: "text-zinc-500 hover:underline"
              )
            }
            aria-current={key == @active && "page"}
          >
            {label}
          </span>
        <% end %>
      </nav>
      <.status_badge :if={@status} status={@status} />
    </div>
    """
  end

  # A2's toolbar: the tabs where the form's name was; the save state, the
  # status, and the actions right. Without `editing` - History, View - the
  # buttons go and the last event is said instead. `flush` drops the top
  # border and the gap above, so the bar reads as the header's last line
  # rather than a second thing under it.
  attr :active, :atom, required: true
  attr :editing, :boolean, default: false
  attr :status, :any, default: nil
  attr :flush, :boolean, default: false
  attr :who, :string, default: "dog_owner"

  def toolbar(assigns) do
    ~H"""
    <div class={[
      "sticky top-0 z-10 flex flex-wrap items-center justify-between gap-3 border-b border-zinc-200 bg-white/95 px-6 backdrop-blur",
      if(@flush, do: "mt-1", else: "mt-4 border-t")
    ]}>
      <.tabs variant={:underline} active={@active} size={:base} class="border-b-0 pt-3" />
      <span :if={@editing} class="flex items-center gap-2 py-2.5">
        <.save_state who={@who} />
        <.status_badge :if={@status} status={@status} class="mr-2" />
        <button type="button" class="btn btn-ghost">Save draft</button>
        <button type="button" class="btn btn-primary">Submit</button>
      </span>
      <span :if={!@editing} class="flex items-center gap-3 py-2.5 text-sm text-zinc-500">
        <span>Reopened yesterday by <code class="text-xs">reviewer</code></span>
        <.status_badge :if={@status} status={@status} />
      </span>
    </div>
    """
  end

  # -- The form ----------------------------------------------------------------

  attr :long, :boolean, default: false

  def mock_form(assigns) do
    ~H"""
    <form class="space-y-4" onsubmit="return false">
      <div class="grid gap-4 sm:grid-cols-2">
        <.field label="Full name" value="Grace Hopper" />
        <.field label="Phone" value="(555) 010-2244" />
      </div>
      <.field label="Street address" value="12 Harbor Lane" />
      <%= if @long do %>
        <div class="grid gap-4 sm:grid-cols-2">
          <.field label="City" value="Portsmouth" />
          <.field label="Postal code" value="03801" />
        </div>
        <.field label="Email" value="grace@example.com" />
        <div class="grid gap-4 sm:grid-cols-2">
          <.field label="Co-owner name" value="" />
          <.field label="Co-owner phone" value="" />
        </div>
        <.field label="Mailing address, if different" value="" />
        <.field label="Emergency contact" value="Ada Lovelace" />
        <.field label="Emergency contact phone" value="(555) 010-9876" />
        <.field label="Preferred contact method" value="Email" />
        <.field label="Anything else we should know" value="" />
      <% end %>
    </form>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  def field(assigns) do
    ~H"""
    <label class="block">
      <span class="text-sm font-medium">{@label}</span>
      <input type="text" class="input input-bordered mt-1 w-full" value={@value} readonly />
    </label>
    """
  end
end
