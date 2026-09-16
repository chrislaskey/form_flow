defmodule DemoWeb.ExplorationsLive.TemplateLayout do
  @moduledoc """
  Scratch page for the templates pages' chrome: the header a flow or form
  page puts above its canvas (title, breadcrumb, metadata, actions), and
  the fact sheet it puts below.

  Everything is hardcoded - one Dog License flow, its Applicant subflow, one
  Review Health Info form - so the directions can be compared side by side.
  Each header direction is a `page_header/1` clause rendered once per mock
  page; each fact-sheet direction is a `details/1` clause rendered under a
  drawn canvas. Nothing here is wired to the real components.

  Mounted on `live "/explorations/template-layout", ExplorationsLive.TemplateLayout`.
  """

  use DemoWeb, :live_view

  alias DemoWeb.ExplorationsLive.Shared

  # -- Data ------------------------------------------------------------------

  # The five pages the header serves, with what each really shows today.
  # `actions` are the header's buttons in their current order; `group`
  # says what kind of action each is, for the directions that sort them.
  @pages [
    %{
      id: :flow_show,
      label: "Flow · Show · root",
      title: "Dog License",
      sub: nil,
      crumbs: ["Flows"],
      last: "Dog License",
      kind: "Complex flow",
      type: "Wizard (in order)",
      perspectives: "Applicant, Reviewer",
      version: nil,
      status: "Published",
      mode: :show,
      actions: [
        %{k: :health},
        %{k: :btn, label: "Status: Published", style: "btn-ghost", group: :nav},
        %{k: :btn, label: "Flow Overview", style: "btn-ghost", group: :nav},
        %{k: :btn, label: "Duplicate Flow", style: "btn-ghost", group: :mutate},
        %{k: :btn, label: "History", style: "btn-ghost", group: :nav},
        %{k: :toggle, edit?: false},
        %{k: :trash}
      ],
      facts: [
        {"Name", "Dog License", nil},
        {"Slug", "dog-license", :code},
        {"Status", "Published", "Users can start it and continue where they left off."},
        {"Flow kind", "Complex flow", nil},
        {"Form flow type", "Wizard (in order)", nil},
        {"Perspectives", "Applicant, Reviewer", nil}
      ]
    },
    %{
      id: :subflow_show,
      label: "Subflow · Show · drill-in",
      title: "Dog License",
      sub: "Applicant",
      crumbs: ["Flows", "Dog License"],
      last: "Applicant",
      kind: "Simple flow",
      type: nil,
      perspectives: nil,
      version: nil,
      status: nil,
      mode: :show,
      actions: [
        %{k: :health},
        %{k: :btn, label: "Flow Overview", style: "btn-ghost", group: :nav},
        %{k: :btn, label: "History", style: "btn-ghost", group: :nav},
        %{k: :toggle, edit?: false},
        %{k: :trash}
      ],
      facts: [
        {"Step name", "Applicant", nil},
        {"Step slug", "applicant", :code},
        {"Flow kind", "Simple flow", nil}
      ]
    },
    %{
      id: :flow_edit,
      label: "Flow · Edit · root",
      title: "Dog License",
      sub: nil,
      crumbs: ["Flows"],
      last: "Dog License",
      kind: "Complex flow",
      type: "Wizard (in order)",
      perspectives: "Applicant, Reviewer",
      version: nil,
      status: "Published",
      mode: :edit,
      actions: [
        %{k: :health},
        %{k: :btn, label: "Flow Overview", style: "btn-ghost", group: :nav},
        %{k: :toggle, edit?: true},
        %{k: :btn, label: "Discard changes", style: "btn-error btn-ghost", group: :danger},
        %{k: :btn, label: "Save", style: "btn-primary", group: :primary}
      ],
      facts: []
    },
    %{
      id: :form_show,
      label: "Form · Show · through a step",
      title: "Dog License",
      sub: "Review Health Info",
      crumbs: ["Flows", "Dog License", "Reviewer"],
      last: "Review Health Info",
      kind: nil,
      type: "Review",
      perspectives: nil,
      version: "v1 · published",
      extra: "Form to review: Applicant / Health Information",
      status: nil,
      mode: :show,
      actions: [
        %{k: :health},
        %{k: :trash}
      ],
      facts: []
    },
    %{
      id: :form_edit,
      label: "Form · Edit draft",
      title: "Dog License",
      sub: "Review Health Info",
      crumbs: ["Flows", "Dog License", "Reviewer", "Review Health Info", "Versions"],
      last: "Edit",
      kind: nil,
      type: nil,
      perspectives: nil,
      version: "draft",
      status: nil,
      mode: :edit,
      actions: [
        %{k: :health},
        %{k: :btn, label: "Delete draft", style: "btn-error btn-ghost", group: :danger},
        %{k: :btn, label: "Save draft", style: "", group: :mutate},
        %{k: :btn, label: "Publish", style: "btn-primary", group: :primary}
      ],
      facts: []
    }
  ]

  @headers [
    %{
      id: :current,
      title: "H1 · Current",
      note:
        "Where we are now, for reference: title with dotted metadata, breadcrumb under, every action right."
    },
    %{
      id: :crumb_first,
      title: "H2 · Breadcrumb first, bigger title",
      note:
        "The trail on top, small; the title under it, larger, and nothing after it - the metadata moves to the fact sheet. Actions right."
    },
    %{
      id: :chips,
      title: "H3 · Chips under the title",
      note:
        "The dotted metadata becomes a row of quiet chips under the title: kind, type, version, status. Scannable, and the title stays a title."
    },
    %{
      id: :overflow,
      title: "H4 · One primary, the rest in ⋯",
      note:
        "Health, the page's one main control, and an overflow menu. The header stops being a toolbar; the rarely used actions are one click further."
    },
    %{
      id: :toolbar,
      title: "H5 · Title row, then a toolbar",
      note:
        "Two rows with clear jobs: the top says where you are, the bar under it is where you act. A segmented Show | Edit control replaces the switch."
    },
    %{
      id: :tabs,
      title: "H6 · Tabs",
      note:
        "Show, Edit, Overview, History as tabs under the title, the way a repo page does it. Only Save and Delete stay as buttons."
    },
    %{
      id: :app_bar,
      title: "H7 · One line",
      note:
        "The breadcrumb is the title: the trail with the last crumb bold. Actions right. The shortest header the page can have."
    },
    %{
      id: :eyebrow,
      title: "H8 · Eyebrow and a back link",
      note:
        "A small uppercase eyebrow carries the kind, type, and status; a big title; one ← back link in place of the trail."
    },
    %{
      id: :two_tier,
      title: "H9 · Two tiers: root, then page",
      note:
        "A thin strip for the root flow - its trail, health, status - then the page's own title and its own actions. Root-level actions stop mixing with page-level ones."
    },
    %{
      id: :card,
      title: "H10 · Header card with facts folded in",
      note:
        "Title and actions on top, the key facts as a mini fact sheet along the bottom of the same card. The section below the canvas shrinks to what is left."
    },
    %{
      id: :three_col,
      title: "H11 · Three columns",
      note:
        "Title and trail left, a compact fact list in the middle, actions right. Dense; everything visible at once."
    },
    %{
      id: :status_forward,
      title: "H12 · Status forward, quiet links",
      note:
        "A coloured status pill and health beside the title; Overview, History, Duplicate as a text-link row; only the switch and the mutating buttons stay right."
    }
  ]

  @details [
    %{
      id: :current,
      title: "D1 · Current, plus Flow kind",
      note:
        "The three-column list as it is today, with Flow kind added - it is missing there now."
    },
    %{
      id: :card,
      title: "D2 · Bordered fact sheet",
      note:
        "The form page's box: a heading with its Edit action, four columns of label over value inside a border."
    },
    %{
      id: :groups,
      title: "D3 · Two groups",
      note:
        "Who the flow is (name, slug, status) and what it is (kind, type, perspectives) as two cards, each with its own heading. Mirrors the Edit page's two rows."
    },
    %{
      id: :rows,
      title: "D4 · Settings rows",
      note:
        "One fact per row, label left, value right, a hairline between. Reads top to bottom; long values have room."
    },
    %{
      id: :sentence,
      title: "D5 · A sentence, then the table",
      note:
        "The facts read out as a line of prose first, so the page explains itself, with the compact table under it for scanning."
    },
    %{
      id: :rail,
      title: "D6 · Facts in a side rail",
      note:
        "The canvas gives up a column: facts stack in a rail beside it, visible while you look at the steps. No scrolling under the canvas."
    },
    %{
      id: :chips_above,
      title: "D7 · Kind facts above the canvas, identity below",
      note:
        "Kind, type, perspectives, status as chips between the header and the canvas; only name and slug stay under it."
    }
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Template page layouts")
     |> assign(:pages, @pages)
     |> assign(:headers, @headers)
     |> assign(:details, @details)
     |> assign(:all_pages, false)}
  end

  @impl true
  def handle_event("toggle_all_pages", _params, socket) do
    {:noreply, update(socket, :all_pages, &(!&1))}
  end

  defp shown_pages(pages, true), do: pages
  defp shown_pages(pages, false), do: Enum.filter(pages, &(&1.id in [:subflow_show, :form_show]))

  defp flow_page(pages), do: Enum.find(pages, &(&1.id == :flow_show))

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="space-y-6">
        <header class="space-y-2">
          <Shared.back_link />
          <h1 class="text-2xl font-semibold">Template page layouts</h1>
          <p class="text-base-content/70">
            The chrome around a flow's or form's canvas: the header above it and
            the fact sheet below. Today the header is title top-left with dotted
            metadata, breadcrumb bottom-left, every action to the right - and the
            metadata repeats in the fact sheet. Hardcoded: the Dog License flow,
            its Applicant subflow, and the Review Health Info form. Nothing here
            is wired up.
          </p>
          <label class="inline-flex items-center gap-2 text-sm text-gray-700">
            <input
              type="checkbox"
              class="checkbox checkbox-sm checkbox-primary"
              checked={@all_pages}
              phx-click="toggle_all_pages"
            /> Show all five pages per direction (root flow show and edit, form edit too)
          </label>
        </header>

        <section id="headers" class="space-y-10 border-t border-gray-200 pt-10">
          <header class="space-y-2">
            <h2 class="text-2xl font-semibold">Header directions</h2>
            <p class="text-base-content/70">
              Each direction, once per page. The form pages' version actions
              (Continue editing, New draft, Archive) already sit on the Form
              versions heading, so their headers carry only health and delete.
            </p>
          </header>

          <div :for={d <- @headers} class="space-y-3">
            <div class="flex flex-wrap items-baseline gap-x-3 gap-y-1">
              <h3 class="font-semibold text-gray-900">{d.title}</h3>
              <p class="text-sm text-gray-500">{d.note}</p>
            </div>
            <div class={[
              "grid gap-4",
              if(@all_pages, do: "grid-cols-1", else: "grid-cols-1 2xl:grid-cols-2")
            ]}>
              <.frame :for={p <- shown_pages(@pages, @all_pages)} label={p.label}>
                <.page_header direction={d.id} page={p} />
              </.frame>
            </div>
          </div>
        </section>

        <section id="details" class="space-y-10 border-t border-gray-200 pt-10">
          <header class="space-y-2">
            <h2 class="text-2xl font-semibold">Fact sheet directions</h2>
            <p class="text-base-content/70">
              What sits under the canvas on the root flow's show page, with the
              header reduced to H2 (trail, title, actions) so the facts live in
              one place. The Edit page would carry the same layout with inputs
              in place of values.
            </p>
          </header>

          <div :for={d <- @details} class="space-y-3">
            <div class="flex flex-wrap items-baseline gap-x-3 gap-y-1">
              <h3 class="font-semibold text-gray-900">{d.title}</h3>
              <p class="text-sm text-gray-500">{d.note}</p>
            </div>
            <.frame label={flow_page(@pages).label}>
              <.details direction={d.id} page={flow_page(@pages)} />
            </.frame>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end

  # -- Frames ----------------------------------------------------------------

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp frame(assigns) do
    ~H"""
    <div class="space-y-1.5">
      <p class="text-[10px] font-semibold uppercase tracking-wider text-gray-400">{@label}</p>
      <div class="rounded-xl border border-dashed border-gray-300 bg-white px-6 py-5">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  # -- Header directions -----------------------------------------------------

  attr :direction, :atom, required: true
  attr :page, :map, required: true

  defp page_header(%{direction: :current} = assigns) do
    ~H"""
    <div class="flex flex-col gap-4 xl:flex-row xl:items-start xl:justify-between">
      <div class="min-w-0">
        <h2 class="flex flex-wrap items-baseline gap-x-2 text-xl font-semibold leading-tight">
          <span>{@page.title}</span>
          <span :if={@page.sub} class="font-normal text-zinc-500">{@page.sub}</span>
          <%= for m <- metadata(@page) do %>
            <span class="text-zinc-300">·</span>
            <span class="text-sm font-normal text-zinc-500">{m}</span>
          <% end %>
        </h2>
        <.trail page={@page} class="mt-1 text-sm" />
      </div>
      <.actions page={@page} />
    </div>
    """
  end

  defp page_header(%{direction: :crumb_first} = assigns) do
    ~H"""
    <div>
      <.trail page={@page} class="text-xs" />
      <div class="mt-1 flex flex-col gap-3 xl:flex-row xl:items-center xl:justify-between">
        <h2 class="flex flex-wrap items-baseline gap-x-2 text-2xl font-semibold leading-tight">
          <span>{@page.sub || @page.title}</span>
          <span :if={@page.sub} class="text-base font-normal text-zinc-400">in {@page.title}</span>
        </h2>
        <.actions page={@page} />
      </div>
    </div>
    """
  end

  defp page_header(%{direction: :chips} = assigns) do
    ~H"""
    <div>
      <.trail page={@page} class="text-xs" />
      <div class="mt-1 flex flex-col gap-3 xl:flex-row xl:items-start xl:justify-between">
        <div class="min-w-0">
          <h2 class="flex flex-wrap items-baseline gap-x-2 text-2xl font-semibold leading-tight">
            <span>{@page.title}</span>
            <span :if={@page.sub} class="font-normal text-zinc-500">{@page.sub}</span>
          </h2>
          <div class="mt-2 flex flex-wrap items-center gap-1.5">
            <.chip :for={m <- metadata(@page)} tone={chip_tone(m)}>{m}</.chip>
          </div>
        </div>
        <.actions page={@page} />
      </div>
    </div>
    """
  end

  defp page_header(%{direction: :overflow} = assigns) do
    {shown, hidden} = split_overflow(assigns.page)
    assigns = assign(assigns, shown: shown, hidden: hidden)

    ~H"""
    <div>
      <.trail page={@page} class="text-xs" />
      <div class="mt-1 flex flex-col gap-3 xl:flex-row xl:items-center xl:justify-between">
        <h2 class="flex flex-wrap items-baseline gap-x-2 text-2xl font-semibold leading-tight">
          <span>{@page.title}</span>
          <span :if={@page.sub} class="font-normal text-zinc-500">{@page.sub}</span>
          <span :if={@page.version} class="text-sm font-normal text-zinc-500">{@page.version}</span>
        </h2>
        <div class="flex items-center gap-2">
          <.action :for={a <- @shown} action={a} />
          <span :if={@hidden != []} class="btn btn-ghost btn-square" aria-label="More">
            <.icon name="hero-ellipsis-horizontal" class="size-5" />
          </span>
        </div>
      </div>
      <p :if={@hidden != []} class="mt-2 text-right text-xs text-zinc-400">
        in ⋯: {Enum.map_join(@hidden, ", ", &action_label/1)}
      </p>
    </div>
    """
  end

  defp page_header(%{direction: :toolbar} = assigns) do
    ~H"""
    <div>
      <.trail page={@page} class="text-xs" />
      <h2 class="mt-1 flex flex-wrap items-baseline gap-x-2 text-2xl font-semibold leading-tight">
        <span>{@page.title}</span>
        <span :if={@page.sub} class="font-normal text-zinc-500">{@page.sub}</span>
      </h2>
      <div class="mt-3 flex flex-wrap items-center justify-between gap-3 rounded-lg border border-zinc-200 bg-zinc-50 px-3 py-2">
        <div class="flex flex-wrap items-center gap-3">
          <.segmented :if={flow?(@page)} edit?={@page.mode == :edit} />
          <.chip :if={@page.status} tone={:green}>{@page.status}</.chip>
          <.chip :if={@page.version} tone={chip_tone(@page.version)}>{@page.version}</.chip>
          <span :if={@page.kind} class="text-sm text-zinc-500">{@page.kind}</span>
        </div>
        <div class="flex flex-wrap items-center gap-2">
          <.action :for={a <- Enum.reject(@page.actions, &(&1.k == :toggle))} action={a} />
        </div>
      </div>
    </div>
    """
  end

  defp page_header(%{direction: :tabs} = assigns) do
    ~H"""
    <div>
      <.trail page={@page} class="text-xs" />
      <div class="mt-1 flex flex-col gap-3 xl:flex-row xl:items-center xl:justify-between">
        <h2 class="flex flex-wrap items-baseline gap-x-2 text-2xl font-semibold leading-tight">
          <span>{@page.title}</span>
          <span :if={@page.sub} class="font-normal text-zinc-500">{@page.sub}</span>
          <.chip :if={@page.status} tone={:green}>{@page.status}</.chip>
          <.chip :if={@page.version} tone={chip_tone(@page.version)}>{@page.version}</.chip>
        </h2>
        <div class="flex items-center gap-2">
          <.action
            :for={
              a <-
                Enum.filter(
                  @page.actions,
                  &(&1.k in [:health, :trash] or Map.get(&1, :group) in [:primary, :danger, :mutate])
                )
            }
            action={a}
          />
        </div>
      </div>
      <div :if={flow?(@page)} class="mt-3 flex gap-6 border-b border-zinc-200 text-sm">
        <.tab active={@page.mode == :show}>Show</.tab>
        <.tab active={@page.mode == :edit}>Edit</.tab>
        <.tab active={false}>Overview</.tab>
        <.tab active={false}>History</.tab>
        <.tab :if={@page.status} active={false}>Health</.tab>
      </div>
      <div :if={!flow?(@page)} class="mt-3 flex gap-6 border-b border-zinc-200 text-sm">
        <.tab active={@page.mode == :show}>Form</.tab>
        <.tab active={false}>Details</.tab>
        <.tab active={@page.mode == :edit}>Versions</.tab>
      </div>
    </div>
    """
  end

  defp page_header(%{direction: :app_bar} = assigns) do
    ~H"""
    <div class="flex flex-col gap-3 xl:flex-row xl:items-center xl:justify-between">
      <h2 class="flex flex-wrap items-center gap-x-1.5 text-base leading-tight text-zinc-500">
        <span class="text-zinc-400" aria-hidden="true">⧉</span>
        <span>Form Flow</span>
        <%= for c <- @page.crumbs do %>
          <.icon name="hero-chevron-right-mini" class="size-4 text-zinc-300" />
          <span>{c}</span>
        <% end %>
        <.icon name="hero-chevron-right-mini" class="size-4 text-zinc-300" />
        <span class="text-lg font-semibold text-zinc-900">{@page.last}</span>
        <.chip :if={@page.version} tone={chip_tone(@page.version)} class="ml-1">
          {@page.version}
        </.chip>
      </h2>
      <.actions page={@page} />
    </div>
    """
  end

  defp page_header(%{direction: :eyebrow} = assigns) do
    ~H"""
    <div class="flex flex-col gap-3 xl:flex-row xl:items-end xl:justify-between">
      <div class="min-w-0">
        <p class="text-[11px] font-semibold uppercase tracking-wider text-zinc-400">
          {Enum.join(metadata(@page) ++ List.wrap(@page.status), " · ")}
        </p>
        <h2 class="mt-0.5 text-2xl font-semibold leading-tight">{@page.sub || @page.title}</h2>
        <p class="mt-1 text-sm text-zinc-500">
          <span class="hover:underline">← {back_label(@page)}</span>
        </p>
      </div>
      <.actions page={@page} />
    </div>
    """
  end

  defp page_header(%{direction: :two_tier} = assigns) do
    {root_actions, page_actions} = split_tiers(assigns.page)
    assigns = assign(assigns, root_actions: root_actions, page_actions: page_actions)

    ~H"""
    <div>
      <div class="-mx-6 -mt-5 flex flex-wrap items-center justify-between gap-2 rounded-t-xl border-b border-zinc-200 bg-zinc-50 px-6 py-2">
        <.trail page={@page} class="text-xs" drop_last={@page.sub != nil} />
        <div class="flex items-center gap-1">
          <.action :for={a <- @root_actions} action={a} small />
        </div>
      </div>
      <div class="mt-4 flex flex-col gap-3 xl:flex-row xl:items-center xl:justify-between">
        <h2 class="flex flex-wrap items-baseline gap-x-2 text-2xl font-semibold leading-tight">
          <span>{@page.sub || @page.title}</span>
          <%= for m <- metadata(@page) do %>
            <span class="text-zinc-300">·</span>
            <span class="text-sm font-normal text-zinc-500">{m}</span>
          <% end %>
        </h2>
        <div class="flex items-center gap-2">
          <.action :for={a <- @page_actions} action={a} />
        </div>
      </div>
    </div>
    """
  end

  defp page_header(%{direction: :card} = assigns) do
    ~H"""
    <div>
      <.trail page={@page} class="text-xs" />
      <div class="mt-2 rounded-lg border border-zinc-300">
        <div class="flex flex-col gap-3 p-4 xl:flex-row xl:items-center xl:justify-between">
          <h2 class="flex flex-wrap items-baseline gap-x-2 text-2xl font-semibold leading-tight">
            <span>{@page.title}</span>
            <span :if={@page.sub} class="font-normal text-zinc-500">{@page.sub}</span>
          </h2>
          <.actions page={@page} />
        </div>
        <dl class="flex flex-wrap gap-x-8 gap-y-2 border-t border-zinc-200 bg-zinc-50 px-4 py-3 text-sm">
          <div :for={{label, value} <- card_facts(@page)} class="min-w-0">
            <dt class="text-[11px] font-medium uppercase tracking-wide text-zinc-400">{label}</dt>
            <dd class="text-zinc-800">{value}</dd>
          </div>
        </dl>
      </div>
    </div>
    """
  end

  defp page_header(%{direction: :three_col} = assigns) do
    ~H"""
    <div class="flex flex-col gap-4 xl:flex-row xl:items-start xl:justify-between">
      <div class="min-w-0 xl:w-1/3">
        <h2 class="flex flex-wrap items-baseline gap-x-2 text-xl font-semibold leading-tight">
          <span>{@page.title}</span>
          <span :if={@page.sub} class="font-normal text-zinc-500">{@page.sub}</span>
        </h2>
        <.trail page={@page} class="mt-1 text-sm" />
      </div>
      <dl class="grid grid-cols-[auto_1fr] gap-x-3 gap-y-0.5 text-sm xl:w-1/3">
        <%= for {label, value} <- card_facts(@page) do %>
          <dt class="text-zinc-400">{label}</dt>
          <dd class="text-zinc-700">{value}</dd>
        <% end %>
      </dl>
      <.actions page={@page} class="xl:w-1/3 xl:justify-end" />
    </div>
    """
  end

  defp page_header(%{direction: :status_forward} = assigns) do
    ~H"""
    <div class="flex flex-col gap-3 xl:flex-row xl:items-start xl:justify-between">
      <div class="min-w-0">
        <h2 class="flex flex-wrap items-center gap-x-2 text-2xl font-semibold leading-tight">
          <span>{@page.title}</span>
          <span :if={@page.sub} class="font-normal text-zinc-500">{@page.sub}</span>
          <.status_pill :if={@page.status} label={@page.status} tone={:green} />
          <.status_pill :if={@page.version} label={@page.version} tone={chip_tone(@page.version)} />
          <.health />
        </h2>
        <div class="mt-1 flex flex-wrap items-center gap-x-3 text-sm">
          <.trail page={@page} class="text-zinc-500" />
          <span class="text-zinc-300">|</span>
          <span
            :for={
              a <-
                Enum.filter(@page.actions, &(Map.get(&1, :group) in [:nav, :mutate] and &1.k == :btn))
            }
            class="text-indigo-600 hover:underline"
          >
            {a.label}
          </span>
        </div>
      </div>
      <div class="flex items-center gap-2">
        <.action
          :for={
            a <-
              Enum.filter(
                @page.actions,
                &(&1.k in [:toggle, :trash] or Map.get(&1, :group) in [:primary, :danger])
              )
          }
          action={a}
        />
      </div>
    </div>
    """
  end

  # -- Fact sheet directions -------------------------------------------------

  attr :direction, :atom, required: true
  attr :page, :map, required: true

  defp details(%{direction: :current} = assigns) do
    ~H"""
    <.page_header direction={:crumb_first} page={@page} />
    <.canvas />
    <dl class="mt-3 grid grid-cols-1 gap-4 md:grid-cols-3">
      <.fact :for={f <- @page.facts} fact={f} />
    </dl>
    """
  end

  defp details(%{direction: :card} = assigns) do
    ~H"""
    <.page_header direction={:crumb_first} page={@page} />
    <.canvas />
    <div class="mt-6 flex items-center justify-between gap-3">
      <div>
        <h3 class="text-lg font-bold">Flow details</h3>
        <p class="text-gray-500">
          What every step of this flow shares: its name, slug, status, and kind.
        </p>
      </div>
      <span class="btn">Edit flow details</span>
    </div>
    <div class="mt-3 rounded-lg border border-zinc-300 p-6">
      <dl class="grid grid-cols-1 gap-4 text-sm md:grid-cols-4">
        <.fact :for={f <- @page.facts} fact={f} />
      </dl>
    </div>
    """
  end

  defp details(%{direction: :groups} = assigns) do
    {identity, kind} = Enum.split(assigns.page.facts, 3)
    assigns = assign(assigns, identity: identity, kind: kind)

    ~H"""
    <.page_header direction={:crumb_first} page={@page} />
    <.canvas />
    <div class="mt-6 grid gap-4 md:grid-cols-2">
      <div>
        <h3 class="text-lg font-bold">Identity</h3>
        <p class="mb-3 text-gray-500">Who this flow is, and how users reach it.</p>
        <div class="rounded-lg border border-zinc-300 p-5">
          <dl class="grid grid-cols-1 gap-4 text-sm sm:grid-cols-3">
            <.fact :for={f <- @identity} fact={f} />
          </dl>
        </div>
      </div>
      <div>
        <h3 class="text-lg font-bold">Kind</h3>
        <p class="mb-3 text-gray-500">What sort of flow it is, and who its forms are for.</p>
        <div class="rounded-lg border border-zinc-300 p-5">
          <dl class="grid grid-cols-1 gap-4 text-sm sm:grid-cols-3">
            <.fact :for={f <- @kind} fact={f} />
          </dl>
        </div>
      </div>
    </div>
    """
  end

  defp details(%{direction: :rows} = assigns) do
    ~H"""
    <.page_header direction={:crumb_first} page={@page} />
    <.canvas />
    <dl class="mt-6 divide-y divide-zinc-200 rounded-lg border border-zinc-200 text-sm">
      <div :for={{label, value, extra} <- @page.facts} class="flex items-baseline gap-6 px-4 py-2.5">
        <dt class="w-40 shrink-0 text-zinc-500">{label}</dt>
        <dd class="min-w-0">
          <span :if={extra == :code} class="rounded bg-zinc-100 px-1 font-mono text-xs">{value}</span>
          <span :if={extra != :code}>{value}</span>
          <span :if={is_binary(extra)} class="ml-2 text-xs text-zinc-400">{extra}</span>
        </dd>
      </div>
    </dl>
    """
  end

  defp details(%{direction: :sentence} = assigns) do
    ~H"""
    <.page_header direction={:crumb_first} page={@page} />
    <.canvas />
    <p class="mt-6 text-base text-zinc-700">
      <span class="font-semibold">Dog License</span>
      is a <span class="font-medium">complex flow</span>
      presented as a <span class="font-medium">wizard, in order</span>, for
      <span class="font-medium">applicants</span>
      and <span class="font-medium">reviewers</span>. It is <span class="font-medium text-green-700">published</span>: users can start it and continue where they left off.
    </p>
    <table class="mt-3 text-sm">
      <tbody>
        <tr :for={{label, value, extra} <- @page.facts} class="align-baseline">
          <th class="py-0.5 pr-6 text-left font-normal text-zinc-400">{label}</th>
          <td class={["py-0.5 text-zinc-700", extra == :code && "font-mono text-xs"]}>{value}</td>
        </tr>
      </tbody>
    </table>
    """
  end

  defp details(%{direction: :rail} = assigns) do
    ~H"""
    <.page_header direction={:crumb_first} page={@page} />
    <div class="mt-4 flex flex-col gap-4 lg:flex-row">
      <div class="min-w-0 flex-1"><.canvas class="mt-0" /></div>
      <aside class="w-full shrink-0 rounded-lg border border-zinc-200 bg-zinc-50 p-4 lg:w-72">
        <div class="flex items-center justify-between">
          <h3 class="text-sm font-semibold text-zinc-700">Flow details</h3>
          <span class="text-xs text-indigo-600 hover:underline">Edit</span>
        </div>
        <dl class="mt-3 space-y-3 text-sm">
          <.fact :for={f <- @page.facts} fact={f} />
        </dl>
      </aside>
    </div>
    """
  end

  defp details(%{direction: :chips_above} = assigns) do
    ~H"""
    <.page_header direction={:crumb_first} page={@page} />
    <div class="mt-2 flex flex-wrap items-center gap-1.5">
      <.chip tone={:green}>Published</.chip>
      <.chip tone={:zinc}>Complex flow</.chip>
      <.chip tone={:zinc}>Wizard (in order)</.chip>
      <.chip tone={:zinc}>For: Applicant, Reviewer</.chip>
      <span class="ml-1 text-xs text-indigo-600 hover:underline">Edit</span>
    </div>
    <.canvas />
    <dl class="mt-3 grid grid-cols-1 gap-4 md:grid-cols-3">
      <.fact :for={f <- Enum.take(@page.facts, 2)} fact={f} />
    </dl>
    """
  end

  # -- Pieces ----------------------------------------------------------------

  attr :page, :map, required: true
  attr :class, :any, default: nil
  attr :drop_last, :boolean, default: false

  defp trail(assigns) do
    ~H"""
    <nav
      aria-label="Breadcrumb"
      class={["flex flex-wrap items-center gap-x-1.5 text-zinc-500", @class]}
    >
      <span><span aria-hidden="true">⧉</span> Form Flow</span>
      <%= for c <- @page.crumbs do %>
        <span class="text-zinc-400">/</span>
        <span class="hover:underline">{c}</span>
      <% end %>
      <%= if !@drop_last do %>
        <span class="text-zinc-400">/</span>
        <span class="text-zinc-700">{@page.last}</span>
      <% end %>
    </nav>
    """
  end

  attr :page, :map, required: true
  attr :class, :any, default: nil

  defp actions(assigns) do
    ~H"""
    <div class={["flex flex-wrap items-center gap-2 xl:shrink-0", @class]}>
      <.action :for={a <- @page.actions} action={a} />
    </div>
    """
  end

  attr :action, :map, required: true
  attr :small, :boolean, default: false

  defp action(%{action: %{k: :health}} = assigns) do
    ~H"""
    <.health small={@small} />
    """
  end

  defp action(%{action: %{k: :toggle}} = assigns) do
    ~H"""
    <span class="mx-2 flex items-center gap-1.5 text-sm">
      <span class={if(@action.edit?, do: "text-zinc-500", else: "font-semibold text-zinc-900")}>Show</span>
      <span class={[
        "relative inline-flex h-6 w-11 shrink-0 items-center rounded-full",
        if(@action.edit?, do: "bg-cyan-600", else: "bg-zinc-300")
      ]}>
        <span class={[
          "inline-block h-5 w-5 rounded-full bg-white shadow",
          if(@action.edit?, do: "translate-x-5", else: "translate-x-0.5")
        ]} />
      </span>
      <span class={if(@action.edit?, do: "font-semibold text-zinc-900", else: "text-zinc-500")}>Edit</span>
    </span>
    """
  end

  defp action(%{action: %{k: :trash}} = assigns) do
    ~H"""
    <span class={["btn btn-error btn-ghost btn-square", @small && "btn-sm"]} aria-label="Delete">
      <.icon name="hero-trash" class="size-5" />
    </span>
    """
  end

  defp action(%{action: %{k: :btn}} = assigns) do
    ~H"""
    <span class={["btn", @action.style, @small && "btn-sm"]}>{@action.label}</span>
    """
  end

  attr :small, :boolean, default: false

  defp health(assigns) do
    ~H"""
    <span
      class={[
        "relative inline-flex items-center justify-center text-zinc-600",
        if(@small, do: "size-7", else: "size-9")
      ]}
      title="Healthy · 31 checks"
    >
      <.icon name="hero-heart" class="size-5" />
      <span class="absolute -right-0.5 -top-0.5 flex size-3.5 items-center justify-center rounded-full bg-green-500 text-white ring-2 ring-white">
        <.icon name="hero-check-mini" class="size-2.5" />
      </span>
    </span>
    """
  end

  attr :tone, :atom, default: :zinc
  attr :class, :any, default: nil
  slot :inner_block, required: true

  defp chip(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center rounded-full border px-2 py-0.5 text-xs font-medium",
      tone_classes(@tone),
      @class
    ]}>
      {render_slot(@inner_block)}
    </span>
    """
  end

  attr :label, :string, required: true
  attr :tone, :atom, required: true

  defp status_pill(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center gap-1.5 rounded-full border px-2.5 py-0.5 text-sm font-medium",
      tone_classes(@tone)
    ]}>
      <span class={["size-1.5 rounded-full", dot_classes(@tone)]} />
      {@label}
    </span>
    """
  end

  attr :edit?, :boolean, required: true

  defp segmented(assigns) do
    ~H"""
    <span class="inline-flex overflow-hidden rounded-md border border-zinc-300 text-sm">
      <span class={[
        "px-3 py-1",
        if(!@edit?, do: "bg-zinc-900 text-white", else: "bg-white text-zinc-600")
      ]}>Show</span>
      <span class={[
        "px-3 py-1",
        if(@edit?, do: "bg-zinc-900 text-white", else: "bg-white text-zinc-600")
      ]}>Edit</span>
    </span>
    """
  end

  attr :active, :boolean, required: true
  slot :inner_block, required: true

  defp tab(assigns) do
    ~H"""
    <span class={[
      "-mb-px border-b-2 pb-2",
      if(@active,
        do: "border-indigo-600 font-semibold text-zinc-900",
        else: "border-transparent text-zinc-500"
      )
    ]}>
      {render_slot(@inner_block)}
    </span>
    """
  end

  attr :fact, :any, required: true

  defp fact(assigns) do
    {label, value, extra} = assigns.fact
    assigns = assign(assigns, label: label, value: value, extra: extra)

    ~H"""
    <div class="min-w-0">
      <dt class="text-sm font-medium text-zinc-500">{@label}</dt>
      <dd class="mt-0.5 text-sm">
        <span :if={@extra == :code} class="rounded bg-zinc-100 px-1 font-mono text-xs">{@value}</span>
        <span :if={@extra != :code}>{@value}</span>
        <span :if={is_binary(@extra)} class="block text-xs text-zinc-500">{@extra}</span>
      </dd>
    </div>
    """
  end

  attr :class, :any, default: "mt-4"

  # A drawn stand-in for the ReactFlow canvas: dotted paper, four nodes
  defp canvas(assigns) do
    ~H"""
    <div
      class={["h-44 rounded-lg border border-zinc-200", @class]}
      style="background-image: radial-gradient(circle, #d4d4d8 1px, transparent 1px); background-size: 16px 16px;"
    >
      <svg viewBox="0 0 640 176" class="h-full w-full" aria-hidden="true">
        <g stroke="#a1a1aa" stroke-width="1.5" fill="none">
          <path d="M110 88 H180" />
          <path d="M300 88 H370" />
          <path d="M490 88 H560" />
        </g>
        <g font-family="ui-sans-serif, system-ui" font-size="12" text-anchor="middle">
          <rect x="40" y="70" width="70" height="36" rx="18" fill="#fff" stroke="#a1a1aa" />
          <text x="75" y="93" fill="#3f3f46">Start</text>
          <rect x="180" y="62" width="120" height="52" rx="6" fill="#fff" stroke="#6366f1" />
          <text x="240" y="84" fill="#18181b" font-weight="600">Applicant</text>
          <text x="240" y="100" fill="#71717a" font-size="10">Subflow · 5 steps</text>
          <rect x="370" y="62" width="120" height="52" rx="6" fill="#fff" stroke="#6366f1" />
          <text x="430" y="84" fill="#18181b" font-weight="600">Reviewer</text>
          <text x="430" y="100" fill="#71717a" font-size="10">Subflow · 3 steps</text>
          <rect x="560" y="70" width="60" height="36" rx="18" fill="#fff" stroke="#a1a1aa" />
          <text x="590" y="93" fill="#3f3f46">End</text>
        </g>
      </svg>
    </div>
    """
  end

  # -- Helpers ---------------------------------------------------------------

  defp metadata(page) do
    [
      page[:version],
      page[:kind],
      page[:type],
      page[:extra],
      page[:perspectives] && "For: #{page.perspectives}"
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp card_facts(page) do
    [
      {"Kind", page[:kind]},
      {"Type", page[:type]},
      {"Version", page[:version]},
      {"Status", page[:status]},
      {"For", page[:perspectives]},
      {"Reviews", page[:extra] && "Applicant / Health Information"}
    ]
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
  end

  defp flow?(page), do: page.id in [:flow_show, :subflow_show, :flow_edit]

  defp back_label(%{crumbs: crumbs}), do: List.last(crumbs)

  defp chip_tone("draft"), do: :amber
  defp chip_tone("v" <> _), do: :green
  defp chip_tone(_), do: :zinc

  defp tone_classes(:green), do: "border-green-200 bg-green-50 text-green-700"
  defp tone_classes(:amber), do: "border-amber-200 bg-amber-50 text-amber-700"
  defp tone_classes(:zinc), do: "border-zinc-200 bg-zinc-50 text-zinc-600"

  defp dot_classes(:green), do: "bg-green-500"
  defp dot_classes(:amber), do: "bg-amber-500"
  defp dot_classes(:zinc), do: "bg-zinc-400"

  defp action_label(%{k: :trash}), do: "Delete"
  defp action_label(%{k: :toggle}), do: "Show / Edit"
  defp action_label(%{label: label}), do: label

  # H4: health and the one thing the page is for stay out; everything else
  # goes behind ⋯. On a show page that one thing is the Show/Edit switch;
  # on an edit page it is Save (and Discard, which must stay in reach).
  defp split_overflow(%{mode: :show, actions: actions}) do
    Enum.split_with(actions, &(&1.k in [:health, :toggle]))
  end

  defp split_overflow(%{mode: :edit, actions: actions}) do
    Enum.split_with(
      actions,
      &(&1.k == :health or Map.get(&1, :group) in [:primary, :danger, :mutate])
    )
  end

  # H9: what belongs to the root flow (health, status, overview, history,
  # duplicate) rides the strip; what acts on this page stays with its title
  defp split_tiers(%{actions: actions}) do
    Enum.split_with(actions, fn a ->
      a.k == :health or (a.k == :btn and Map.get(a, :group) == :nav) or
        (a.k == :btn and a.label == "Duplicate Flow")
    end)
  end
end
