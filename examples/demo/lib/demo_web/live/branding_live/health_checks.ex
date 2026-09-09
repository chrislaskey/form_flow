defmodule DemoWeb.BrandingLive.HealthChecks do
  @moduledoc """
  Scratch directions for a flow's health check: the trigger an admin sees
  on the flows index (and later in a page header), and the modal it opens.

  Everything here is hardcoded — one flow, one report — so the shapes can
  be compared side by side. Each trigger direction is a `trigger/1` clause
  rendered in four states (healthy, errors, warnings only, everything
  ignored); each modal direction is a `modal/1` clause rendered inline as a
  static panel. Nothing here is wired to the real component.
  """

  use DemoWeb, :html

  # -- Data ------------------------------------------------------------------

  @flow %{
    name: "Dog License",
    kind: "Complex flow",
    steps: 12,
    subflows: 2,
    forms: 9,
    connections: 11,
    perspectives: ["Applicant", "Reviewer"],
    types: ["Wizard (in order)"],
    checks_run: 31
  }

  @entries [
    %{
      level: :error,
      code: "end_unreachable",
      where: "Review",
      message: "Review does not connect Start to End",
      hint: "Connect the last step to End on the Review canvas.",
      ignored: nil
    },
    %{
      level: :error,
      code: "form_not_published",
      where: "Review / Decision",
      message: "“Review / Decision” has no published version — users cannot start it",
      hint: "Open the form and publish its draft.",
      ignored: nil
    },
    %{
      level: :warning,
      code: "unconnected",
      where: "Application / Vaccination records",
      message: "“Application / Vaccination records” is not connected from Start",
      hint: "Wire it in, or remove the step.",
      ignored: %{user_id: "demo-admin", on: "2026-09-08"}
    },
    %{
      level: :warning,
      code: "dead_end",
      where: "Application / License options",
      message: "“Application / License options” leads nowhere — nothing follows it",
      hint: "Connect it to the next step, or to End.",
      ignored: nil
    },
    %{
      level: :info,
      code: "unpublished_changes",
      where: "Application / Owner contact",
      message: "“Application / Owner contact” has a draft with changes not yet published",
      hint: "Publish when the changes are ready.",
      ignored: nil
    }
  ]

  @states [
    %{id: :healthy, label: "Healthy", counts: %{error: 0, warning: 0, info: 0, ignored: 0}},
    %{id: :errors, label: "Errors", counts: %{error: 2, warning: 1, info: 1, ignored: 1}},
    %{
      id: :warnings,
      label: "Warnings only",
      counts: %{error: 0, warning: 2, info: 1, ignored: 0}
    },
    %{id: :ignored, label: "All ignored", counts: %{error: 0, warning: 0, info: 0, ignored: 3}}
  ]

  @triggers [
    %{
      id: :neutral_pill,
      title: "T1 · Neutral button + pill",
      note: "Where we are now, for reference."
    },
    %{
      id: :dot_text,
      title: "T2 · Status dot + words",
      note: "No chrome at all: a coloured dot and the count in words. Reads like a status column."
    },
    %{
      id: :ci_checks,
      title: "T3 · CI-style check counts",
      note: "One small pill per level with any, like a commit's checks. Zero levels disappear."
    },
    %{
      id: :tinted_chip,
      title: "T4 · Tinted chip",
      note: "Soft tinted background in the level's colour, with an icon. Green says “Healthy”."
    },
    %{
      id: :icon_badge,
      title: "T5 · Icon with a corner badge",
      note: "A heart-pulse icon; the notification-badge count sits on its shoulder."
    },
    %{
      id: :checks_bar,
      title: "T6 · Checks passed bar",
      note:
        "A thin bar of passed vs. failed checks with “29 / 31 checks”. Says how close, not just what."
    },
    %{
      id: :coloured_words,
      title: "T7 · Coloured words only",
      note: "“2 errors · 1 warning” with each count in its colour. Quietest; densest."
    },
    %{
      id: :ghost_dot,
      title: "T8 · Ghost button with dot",
      note:
        "An outlined button reading “Health”, the dot doing the colour. Fits a header CTA row."
    },
    %{
      id: :ring,
      title: "T9 · Score ring",
      note: "A small ring filled by the share of checks that pass; the count in the middle."
    },
    %{
      id: :three_dots,
      title: "T10 · Three dots",
      note: "Error, warning, info as three tiny dots, filled when present, hollow when zero."
    },
    %{
      id: :shield,
      title: "T11 · Shield",
      note:
        "A shield icon in the level's colour with the count beside it; check inside when healthy."
    },
    %{
      id: :split,
      title: "T12 · Split button",
      note:
        "“Health” on the left, the count in a coloured right segment. Two clicks, one control."
    }
  ]

  @modals [
    %{
      id: :tiles,
      title: "M1 · Facts, tiles, list",
      note: "Where we are now, tidied: a facts grid, four count tiles, the list with switches."
    },
    %{
      id: :sidebar,
      title: "M2 · Sidebar summary",
      note:
        "The flow's facts stacked in a left rail; entries grouped under level headings on the right."
    },
    %{
      id: :checklist,
      title: "M3 · Every check, as a checklist",
      note:
        "Passing checks shown too, ticked and collapsed, so “healthy” has evidence. Failing ones expanded."
    },
    %{
      id: :report_card,
      title: "M4 · Report card",
      note: "A verdict headline, a stacked bar of the levels, entries grouped by where they are."
    },
    %{
      id: :table,
      title: "M5 · Table",
      note: "Level, where, what, ignore — one row per entry. Scans well with many entries."
    },
    %{
      id: :minimal,
      title: "M6 · Minimal",
      note:
        "One sentence of summary, a plain list with a coloured edge per level, “Ignore” as a text action."
    },
    %{
      id: :inspector,
      title: "M7 · Inspector",
      note:
        "Entries on the left, the selected one explained on the right with what to do about it."
    },
    %{
      id: :by_location,
      title: "M8 · Grouped by flow",
      note:
        "Sections per flow — root, Application, Review — so an admin fixes one canvas at a time."
    }
  ]

  # Icons to try in T5's corner-badge button. Heroicons where one fits; the
  # medical ones are drawn inline, since heroicons has no stethoscope.
  @icon_variants [
    %{id: :heart, label: "Heart", hero: "hero-heart"},
    %{id: :heart_pulse, label: "Heart pulse"},
    %{id: :pulse, label: "Pulse"},
    %{id: :stethoscope, label: "Stethoscope"},
    %{id: :doctor, label: "Doctor"},
    %{id: :hospital, label: "Hospital"},
    %{id: :cross, label: "Medical cross"},
    %{id: :first_aid, label: "First-aid kit"},
    %{id: :pill, label: "Pill"},
    %{id: :clipboard, label: "Clipboard", hero: "hero-clipboard-document-check"},
    %{id: :shield, label: "Shield", hero: "hero-shield-check"},
    %{id: :lifebuoy, label: "Lifebuoy", hero: "hero-lifebuoy"},
    %{id: :beaker, label: "Beaker", hero: "hero-beaker"},
    %{id: :wrench, label: "Wrench", hero: "hero-wrench-screwdriver"},
    %{id: :check_badge, label: "Check badge", hero: "hero-check-badge"}
  ]

  def flow, do: @flow
  def icon_variants, do: @icon_variants
  def entries, do: @entries
  def states, do: @states
  def triggers, do: @triggers
  def modals, do: @modals

  # -- Triggers ------------------------------------------------------------------

  attr :direction, :atom, required: true
  attr :state, :map, required: true
  attr :checks, :integer, default: 31, doc: "how many checks ran, for the bar and ring"

  def trigger(%{direction: :neutral_pill} = assigns) do
    ~H"""
    <button type="button" class="btn btn-neutral">
      Health
      <span class={[
        "inline-flex h-6 min-w-6 items-center justify-center rounded-full px-2 text-xs font-semibold",
        solid(level(@state))
      ]}>
        {count_or_check(@state)}
      </span>
    </button>
    """
  end

  def trigger(%{direction: :dot_text} = assigns) do
    ~H"""
    <button type="button" class="inline-flex items-center gap-2 text-sm text-gray-800 hover:underline">
      <span class={["size-2.5 rounded-full", dot(level(@state))]} />
      {words(@state)}
    </button>
    """
  end

  def trigger(%{direction: :ci_checks} = assigns) do
    ~H"""
    <button type="button" class="inline-flex items-center gap-1">
      <%= if level(@state) == :ok do %>
        <span class="inline-flex items-center gap-1 rounded-full border border-emerald-200 bg-emerald-50 px-2 py-0.5 text-xs font-medium text-emerald-700">
          <.icon name="hero-check-circle-mini" class="size-3.5" /> Passing
        </span>
      <% else %>
        <span
          :for={{lvl, n} <- present(@state)}
          class={[
            "inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-xs font-medium",
            chip(lvl)
          ]}
        >
          <span class={["size-1.5 rounded-full", dot(lvl)]} /> {n}
        </span>
      <% end %>
      <span :if={@state.counts.ignored > 0} class="ml-1 text-xs text-gray-400">
        {@state.counts.ignored} ignored
      </span>
    </button>
    """
  end

  def trigger(%{direction: :tinted_chip} = assigns) do
    ~H"""
    <button
      type="button"
      class={[
        "inline-flex items-center gap-1.5 rounded-md px-2.5 py-1 text-sm font-medium",
        tint(level(@state))
      ]}
    >
      <.icon name={level_icon(level(@state))} class="size-4" />
      {if level(@state) == :ok, do: "Healthy", else: "#{open(@state)} to fix"}
    </button>
    """
  end

  def trigger(%{direction: :icon_badge} = assigns) do
    ~H"""
    <button
      type="button"
      class="relative inline-flex size-9 items-center justify-center rounded-lg border border-gray-200 bg-white text-gray-700 hover:bg-gray-50"
    >
      <.icon name="hero-heart" class="size-5" />
      <span class={[
        "absolute -right-1.5 -top-1.5 inline-flex h-5 min-w-5 items-center justify-center rounded-full px-1 text-[11px] font-semibold ring-2 ring-white",
        solid(level(@state))
      ]}>
        {count_or_check(@state)}
      </span>
    </button>
    """
  end

  def trigger(%{direction: :checks_bar} = assigns) do
    ~H"""
    <button type="button" class="flex w-36 flex-col gap-1 text-left">
      <span class="flex items-center justify-between text-xs text-gray-600">
        <span>{passed(@state)} / {@checks} checks</span>
        <span class={["font-semibold", text(level(@state))]}>{if level(@state) == :ok,
          do: "✓",
          else: open(@state)}</span>
      </span>
      <span class="flex h-1.5 w-full overflow-hidden rounded-full bg-gray-200">
        <span
          class="h-full bg-emerald-500"
          style={"width: #{trunc(passed(@state) / @checks * 100)}%"}
        />
        <span
          :if={@state.counts.error > 0}
          class="h-full bg-red-500"
          style={"width: #{@state.counts.error * 100 / @checks}%"}
        />
        <span
          :if={@state.counts.warning > 0}
          class="h-full bg-amber-400"
          style={"width: #{@state.counts.warning * 100 / @checks}%"}
        />
        <span
          :if={@state.counts.info > 0}
          class="h-full bg-sky-400"
          style={"width: #{@state.counts.info * 100 / @checks}%"}
        />
      </span>
    </button>
    """
  end

  def trigger(%{direction: :coloured_words} = assigns) do
    ~H"""
    <button type="button" class="text-sm hover:underline">
      <%= if level(@state) == :ok do %>
        <span class="font-medium text-emerald-700">Healthy</span>
      <% else %>
        <span :for={{{lvl, n}, i} <- Enum.with_index(present(@state))}>
          <span :if={i > 0} class="text-gray-300"> · </span>
          <span class={["font-medium", text(lvl)]}>{n} {plural(lvl, n)}</span>
        </span>
      <% end %>
      <span :if={@state.counts.ignored > 0} class="text-gray-400"> · {@state.counts.ignored} ignored</span>
    </button>
    """
  end

  def trigger(%{direction: :ghost_dot} = assigns) do
    ~H"""
    <button
      type="button"
      class="inline-flex items-center gap-2 rounded-lg border border-gray-300 bg-white px-3 py-1.5 text-sm font-medium text-gray-800 hover:border-gray-400"
    >
      <span class={["size-2 rounded-full", dot(level(@state))]} /> Health
      <span :if={level(@state) != :ok} class="text-gray-500">{open(@state)}</span>
    </button>
    """
  end

  def trigger(%{direction: :ring} = assigns) do
    ~H"""
    <button type="button" class="inline-flex items-center gap-2">
      <span class="relative inline-flex size-9 items-center justify-center">
        <svg viewBox="0 0 36 36" class="size-9 -rotate-90">
          <circle cx="18" cy="18" r="15" fill="none" stroke="#e5e7eb" stroke-width="4" />
          <circle
            cx="18"
            cy="18"
            r="15"
            fill="none"
            stroke={stroke(level(@state))}
            stroke-width="4"
            stroke-linecap="round"
            stroke-dasharray={"#{trunc(passed(@state) / @checks * 94.2)} 94.2"}
          />
        </svg>
        <span class={["absolute text-[11px] font-semibold", text(level(@state))]}>
          {count_or_check(@state)}
        </span>
      </span>
      <span class="text-sm text-gray-700">{trunc(passed(@state) / @checks * 100)}%</span>
    </button>
    """
  end

  def trigger(%{direction: :three_dots} = assigns) do
    ~H"""
    <button
      type="button"
      class="inline-flex items-center gap-2 rounded-md px-2 py-1 hover:bg-gray-100"
    >
      <span class="inline-flex items-center gap-1">
        <span
          :for={lvl <- [:error, :warning, :info]}
          class={[
            "size-2.5 rounded-full border-2",
            if(@state.counts[lvl] > 0,
              do: "#{dot(lvl)} #{border(lvl)}",
              else: "border-gray-300 bg-transparent"
            )
          ]}
          title={"#{@state.counts[lvl]} #{plural(lvl, @state.counts[lvl])}"}
        />
      </span>
      <span class="text-xs text-gray-600">
        {if level(@state) == :ok, do: "clear", else: "#{open(@state)} open"}
      </span>
    </button>
    """
  end

  def trigger(%{direction: :shield} = assigns) do
    ~H"""
    <button type="button" class="inline-flex items-center gap-1.5 text-sm font-medium">
      <.icon
        name={
          if level(@state) == :ok,
            do: "hero-shield-check-solid",
            else: "hero-shield-exclamation-solid"
        }
        class={["size-5", text(level(@state))]}
      />
      <span :if={level(@state) != :ok} class="text-gray-800">{open(@state)}</span>
      <span :if={level(@state) == :ok} class="text-gray-500">Healthy</span>
    </button>
    """
  end

  def trigger(%{direction: :split} = assigns) do
    ~H"""
    <span class="inline-flex overflow-hidden rounded-lg text-sm font-medium shadow-sm">
      <button type="button" class="bg-gray-900 px-3 py-1.5 text-white hover:bg-gray-800">Health</button>
      <button type="button" class={["min-w-9 px-2.5 py-1.5", solid(level(@state))]}>
        {count_or_check(@state)}
      </button>
    </span>
    """
  end

  @doc "T5 with a different icon: the corner-badge button around `variant`'s icon."
  attr :variant, :map, required: true
  attr :state, :map, required: true

  def icon_badge(assigns) do
    ~H"""
    <button
      type="button"
      class="relative inline-flex size-10 items-center justify-center rounded-lg border border-gray-200 bg-white text-gray-700 hover:bg-gray-50"
      title={@variant.label}
    >
      <.icon :if={@variant[:hero]} name={@variant.hero} class="size-5" />
      <.medical_icon :if={!@variant[:hero]} id={@variant.id} class="size-5" />
      <span class={[
        "absolute -right-1.5 -top-1.5 inline-flex h-5 min-w-5 items-center justify-center rounded-full px-1 text-[11px] font-semibold ring-2 ring-white",
        solid(level(@state))
      ]}>
        {count_or_check(@state)}
      </span>
    </button>
    """
  end

  attr :id, :atom, required: true
  attr :class, :string, default: nil

  # 24-unit stroke icons in the Lucide manner, so they sit beside heroicons
  defp medical_icon(assigns) do
    ~H"""
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.75"
      stroke-linecap="round"
      stroke-linejoin="round"
      class={@class}
      aria-hidden="true"
    >
      <%= case @id do %>
        <% :heart_pulse -> %>
          <path d="M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4.05 3 5.5l7 7Z" />
          <path d="M3.22 12H9.5l.5-1 2 4.5 2-7 1.5 3.5h5.27" />
        <% :pulse -> %>
          <path d="M22 12h-2.48a2 2 0 0 0-1.93 1.46l-2.35 8.36a.25.25 0 0 1-.48 0L9.24 2.18a.25.25 0 0 0-.48 0l-2.35 8.36A2 2 0 0 1 4.49 12H2" />
        <% :stethoscope -> %>
          <path d="M11 2v2" />
          <path d="M5 2v2" />
          <path d="M5 3H4a2 2 0 0 0-2 2v4a6 6 0 0 0 12 0V5a2 2 0 0 0-2-2h-1" />
          <path d="M8 15a6 6 0 0 0 12 0v-3" />
          <circle cx="20" cy="10" r="2" />
        <% :doctor -> %>
          <circle cx="12" cy="7" r="4" />
          <path d="M5 21a7 7 0 0 1 14 0" />
          <path d="M12 14.5v4" />
          <path d="M10 16.5h4" />
        <% :hospital -> %>
          <path d="M12 6v4" />
          <path d="M14 14h-4" />
          <path d="M14 18h-4" />
          <path d="M14 8h-4" />
          <path d="M18 12h2a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2v-9a2 2 0 0 1 2-2h2" />
          <path d="M18 22V4a2 2 0 0 0-2-2H8a2 2 0 0 0-2 2v18" />
        <% :cross -> %>
          <path d="M11 2a2 2 0 0 0-2 2v5H4a2 2 0 0 0-2 2v2c0 1.1.9 2 2 2h5v5c0 1.1.9 2 2 2h2a2 2 0 0 0 2-2v-5h5a2 2 0 0 0 2-2v-2a2 2 0 0 0-2-2h-5V4a2 2 0 0 0-2-2h-2z" />
        <% :first_aid -> %>
          <path d="M12 11v4" />
          <path d="M14 13h-4" />
          <path d="M16 6V4a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v2" />
          <path d="M18 6v14" />
          <path d="M6 6v14" />
          <rect width="20" height="14" x="2" y="6" rx="2" />
        <% :pill -> %>
          <path d="m10.5 20.5 10-10a4.95 4.95 0 1 0-7-7l-10 10a4.95 4.95 0 1 0 7 7Z" />
          <path d="m8.5 8.5 7 7" />
      <% end %>
    </svg>
    """
  end

  # -- Modals ---------------------------------------------------------------------

  attr :direction, :atom, required: true
  attr :flow, :map, default: @flow
  attr :entries, :list, default: @entries

  def modal(%{direction: :tiles} = assigns) do
    ~H"""
    <.panel title="Health check" subtitle={@flow.name}>
      <dl class="mb-6 grid grid-cols-3 gap-x-8 gap-y-4 text-sm">
        <.fact label="Kind">{@flow.kind}</.fact>
        <.fact label="Steps">{@flow.steps}</.fact>
        <.fact label="Subflows">{@flow.subflows}</.fact>
        <.fact label="Forms">{@flow.forms}</.fact>
        <.fact label="Perspectives">{Enum.join(@flow.perspectives, ", ")}</.fact>
        <.fact label="Flow types">{Enum.join(@flow.types, ", ")}</.fact>
      </dl>
      <div class="mb-6 grid grid-cols-4 gap-3">
        <.tile :for={lvl <- [:error, :warning, :info]} level={lvl} count={count(@entries, lvl)} />
        <.tile level={:ignored} count={Enum.count(@entries, & &1.ignored)} />
      </div>
      <ul class="divide-y divide-gray-200">
        <li
          :for={e <- @entries}
          class={["flex items-start justify-between gap-6 py-4", e.ignored && "text-gray-400"]}
        >
          <div>
            <div class="flex flex-wrap items-baseline gap-x-2">
              <span class={[
                "rounded px-1.5 py-0.5 text-[11px] font-semibold uppercase tracking-wide",
                if(e.ignored, do: "bg-gray-200 text-gray-600", else: solid(e.level))
              ]}>
                {e.level}
              </span>
              <span class={e.ignored && "line-through"}>{e.message}</span>
            </div>
            <p :if={e.ignored} class="mt-1 text-sm italic">
              Ignored by {e.ignored.user_id} on {e.ignored.on}
            </p>
          </div>
          <.switch on={e.ignored != nil} />
        </li>
      </ul>
    </.panel>
    """
  end

  def modal(%{direction: :sidebar} = assigns) do
    ~H"""
    <.panel title="Health check" subtitle={@flow.name} padded={false}>
      <div class="grid grid-cols-[13rem_1fr]">
        <aside class="space-y-5 border-r border-gray-200 bg-gray-50 p-6 text-sm">
          <div>
            <p class="text-xs font-semibold uppercase tracking-wider text-gray-400">Flow</p>
            <dl class="mt-2 space-y-2">
              <.row label="Kind">{@flow.kind}</.row>
              <.row label="Steps">{@flow.steps}</.row>
              <.row label="Subflows">{@flow.subflows}</.row>
              <.row label="Forms">{@flow.forms}</.row>
              <.row label="Connections">{@flow.connections}</.row>
            </dl>
          </div>
          <div>
            <p class="text-xs font-semibold uppercase tracking-wider text-gray-400">For</p>
            <div class="mt-2 flex flex-wrap gap-1">
              <span
                :for={p <- @flow.perspectives}
                class="rounded-full bg-white px-2 py-0.5 text-xs text-gray-700 ring-1 ring-gray-200"
              >{p}</span>
            </div>
          </div>
          <div>
            <p class="text-xs font-semibold uppercase tracking-wider text-gray-400">Checks</p>
            <p class="mt-2 text-gray-700">
              {@flow.checks_run} run · {@flow.checks_run - length(@entries)} passed
            </p>
          </div>
        </aside>
        <div class="p-6">
          <section
            :for={lvl <- [:error, :warning, :info]}
            :if={count_all(@entries, lvl) > 0}
            class="mb-6 last:mb-0"
          >
            <h4 class="mb-2 flex items-center gap-2 text-sm font-semibold text-gray-900">
              <span class={["size-2.5 rounded-full", dot(lvl)]} />
              {String.capitalize(plural(lvl, 2))}
              <span class="font-normal text-gray-400">{count_all(@entries, lvl)}</span>
            </h4>
            <ul class="space-y-2">
              <li
                :for={e <- Enum.filter(@entries, &(&1.level == lvl))}
                class={[
                  "flex items-start justify-between gap-4 rounded-lg border border-gray-200 p-3 text-sm",
                  e.ignored && "border-dashed text-gray-400"
                ]}
              >
                <div>
                  <p class="text-xs text-gray-400">{e.where}</p>
                  <p class={e.ignored && "line-through"}>{e.message}</p>
                  <p :if={e.ignored} class="mt-1 text-xs italic">
                    Ignored by {e.ignored.user_id} · {e.ignored.on}
                  </p>
                </div>
                <label class="inline-flex shrink-0 items-center gap-1.5 text-xs text-gray-600">
                  <input type="checkbox" class="checkbox checkbox-xs" checked={e.ignored != nil} />
                  Ignore
                </label>
              </li>
            </ul>
          </section>
        </div>
      </div>
    </.panel>
    """
  end

  def modal(%{direction: :checklist} = assigns) do
    ~H"""
    <.panel
      title="Health check"
      subtitle={"#{@flow.kind} · #{@flow.subflows} subflows · #{@flow.forms} forms · #{Enum.join(@flow.perspectives, ", ")}"}
    >
      <p class="mb-4 text-sm text-gray-600">
        <span class="font-semibold text-gray-900">{@flow.checks_run - length(@entries)} of {@flow.checks_run}</span>
        checks pass. {count(@entries, :error)} errors, {count(@entries, :warning)} warning, {count(
          @entries,
          :info
        )} info, {Enum.count(@entries, & &1.ignored)} ignored.
      </p>
      <ul class="divide-y divide-gray-100">
        <li :for={e <- @entries} class="py-3">
          <div class="flex items-start gap-3">
            <.icon
              name={level_icon(e.level)}
              class={[
                "mt-0.5 size-5 shrink-0",
                if(e.ignored, do: "text-gray-300", else: text(e.level))
              ]}
            />
            <div class="min-w-0 flex-1">
              <p class={["text-sm", e.ignored && "text-gray-400 line-through"]}>{e.message}</p>
              <p class="mt-1 text-xs text-gray-500">{e.hint}</p>
            </div>
            <button type="button" class="shrink-0 text-xs text-gray-500 hover:text-gray-900">
              {if e.ignored, do: "Ignored · undo", else: "Ignore"}
            </button>
          </div>
        </li>
        <li :for={t <- passing()} class="flex items-center gap-3 py-2 text-sm text-gray-400">
          <.icon name="hero-check-circle-mini" class="size-5 shrink-0 text-emerald-400" />
          <span>{t}</span>
        </li>
        <li class="py-2 text-xs text-gray-400">
          … and {@flow.checks_run - length(@entries) - length(passing())} more passing checks
        </li>
      </ul>
    </.panel>
    """
  end

  def modal(%{direction: :report_card} = assigns) do
    ~H"""
    <.panel title={@flow.name} subtitle="Health check">
      <div class="mb-6 flex items-start gap-4 rounded-xl bg-red-50 p-4 ring-1 ring-red-100">
        <.icon name="hero-exclamation-triangle-solid" class="size-8 shrink-0 text-red-600" />
        <div>
          <p class="text-lg font-semibold text-red-800">Needs attention</p>
          <p class="text-sm text-red-700">
            Users cannot finish this flow yet: {count(@entries, :error)} errors block it.
          </p>
        </div>
      </div>
      <div class="mb-1 flex h-3 w-full overflow-hidden rounded-full bg-gray-200">
        <span
          class="bg-emerald-500"
          style={"width: #{(@flow.checks_run - length(@entries)) * 100 / @flow.checks_run}%"}
        />
        <span
          class="bg-red-500"
          style={"width: #{count(@entries, :error) * 100 / @flow.checks_run}%"}
        />
        <span
          class="bg-amber-400"
          style={"width: #{count(@entries, :warning) * 100 / @flow.checks_run}%"}
        />
        <span class="bg-sky-400" style={"width: #{count(@entries, :info) * 100 / @flow.checks_run}%"} />
        <span
          class="bg-gray-400"
          style={"width: #{Enum.count(@entries, & &1.ignored) * 100 / @flow.checks_run}%"}
        />
      </div>
      <div class="mb-6 flex flex-wrap gap-x-4 gap-y-1 text-xs text-gray-600">
        <span><span class="inline-block size-2 rounded-full bg-emerald-500" /> {@flow.checks_run -
          length(@entries)} passed</span>
        <span><span class="inline-block size-2 rounded-full bg-red-500" /> {count(@entries, :error)} errors</span>
        <span><span class="inline-block size-2 rounded-full bg-amber-400" /> {count(
          @entries,
          :warning
        )} warning</span>
        <span><span class="inline-block size-2 rounded-full bg-sky-400" /> {count(@entries, :info)} info</span>
        <span><span class="inline-block size-2 rounded-full bg-gray-400" /> {Enum.count(
          @entries,
          & &1.ignored
        )} ignored</span>
      </div>
      <div class="mb-6 grid grid-cols-4 gap-4 text-center text-sm">
        <div>
          <p class="text-2xl font-semibold text-gray-900">{@flow.steps}</p><p class="text-gray-500">
            steps
          </p>
        </div>
        <div>
          <p class="text-2xl font-semibold text-gray-900">{@flow.subflows}</p><p class="text-gray-500">
            subflows
          </p>
        </div>
        <div>
          <p class="text-2xl font-semibold text-gray-900">{@flow.forms}</p><p class="text-gray-500">
            forms
          </p>
        </div>
        <div>
          <p class="text-2xl font-semibold text-gray-900">{length(@flow.perspectives)}</p><p class="text-gray-500">
            perspectives
          </p>
        </div>
      </div>
      <ul class="space-y-2">
        <li
          :for={e <- @entries}
          class={[
            "flex items-center justify-between gap-4 rounded-lg px-3 py-2 text-sm",
            tint(e.level),
            e.ignored && "opacity-50"
          ]}
        >
          <span class={e.ignored && "line-through"}>{e.message}</span>
          <.switch on={e.ignored != nil} small />
        </li>
      </ul>
    </.panel>
    """
  end

  def modal(%{direction: :table} = assigns) do
    ~H"""
    <.panel title="Health check" subtitle={@flow.name} padded={false}>
      <div class="flex flex-wrap gap-2 border-b border-gray-200 px-6 py-4 text-xs">
        <span
          :for={
            {k, v} <- [
              {"Kind", @flow.kind},
              {"Steps", @flow.steps},
              {"Subflows", @flow.subflows},
              {"Forms", @flow.forms},
              {"For", Enum.join(@flow.perspectives, ", ")},
              {"Type", Enum.join(@flow.types, ", ")}
            ]
          }
          class="rounded-md bg-gray-100 px-2 py-1 text-gray-700"
        >
          <span class="text-gray-400">{k}</span> {v}
        </span>
      </div>
      <table class="w-full text-left text-sm">
        <thead class="bg-gray-50 text-xs uppercase tracking-wide text-gray-500">
          <tr>
            <th class="px-6 py-2 font-medium">Level</th>
            <th class="py-2 font-medium">Where</th>
            <th class="py-2 font-medium">What</th>
            <th class="px-6 py-2 text-right font-medium">Ignore</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-gray-100">
          <tr :for={e <- @entries} class={e.ignored && "text-gray-400"}>
            <td class="px-6 py-3">
              <span class={[
                "inline-flex items-center gap-1.5 font-medium",
                if(e.ignored, do: "text-gray-400", else: text(e.level))
              ]}><span class={[
                "size-2 rounded-full",
                if(e.ignored, do: "bg-gray-300", else: dot(e.level))
              ]} />{e.level}</span>
            </td>
            <td class="py-3 pr-4 text-gray-500">{e.where}</td>
            <td class="py-3 pr-4">
              <span class={e.ignored && "line-through"}>{short(e.message)}</span>
              <span :if={e.ignored} class="block text-xs italic">by {e.ignored.user_id}, {e.ignored.on}</span>
            </td>
            <td class="px-6 py-3 text-right"><.switch on={e.ignored != nil} small bare /></td>
          </tr>
        </tbody>
      </table>
    </.panel>
    """
  end

  def modal(%{direction: :minimal} = assigns) do
    ~H"""
    <.panel title="Health check">
      <p class="mb-6 text-base text-gray-700">
        <span class="font-semibold text-gray-900">{@flow.name}</span>
        is a {String.downcase(@flow.kind)} of {@flow.subflows} subflows and {@flow.forms} forms, for {Enum.join(
          @flow.perspectives,
          " and "
        )}.
        It has <span class="font-semibold text-red-600">{count(@entries, :error)} errors</span>, <span class="font-semibold text-amber-600">{count(@entries, :warning)} warning</span>, and <span class="font-semibold text-sky-600">{count(@entries, :info)} note</span>;
        <span class="text-gray-400">{Enum.count(@entries, & &1.ignored)} entry is ignored.</span>
      </p>
      <ul class="space-y-3">
        <li
          :for={e <- @entries}
          class={["border-l-4 pl-4", if(e.ignored, do: "border-gray-200", else: border(e.level))]}
        >
          <div class="flex items-start justify-between gap-4">
            <p class={["text-base", e.ignored && "text-gray-400 line-through"]}>{e.message}</p>
            <button
              type="button"
              class="shrink-0 text-sm text-gray-500 hover:text-gray-900 hover:underline"
            >
              {if e.ignored, do: "Undo", else: "Ignore"}
            </button>
          </div>
          <p :if={e.ignored} class="mt-1 text-sm text-gray-400">
            Ignored by {e.ignored.user_id} on {e.ignored.on}
          </p>
        </li>
      </ul>
    </.panel>
    """
  end

  def modal(%{direction: :inspector} = assigns) do
    ~H"""
    <.panel title="Health check" subtitle={@flow.name} padded={false}>
      <div class="grid grid-cols-[1fr_1.2fr]">
        <ul class="divide-y divide-gray-100 border-r border-gray-200">
          <li
            :for={{e, i} <- Enum.with_index(@entries)}
            class={[
              "flex items-center gap-3 px-5 py-3 text-sm",
              i == 1 && "bg-indigo-50",
              e.ignored && "text-gray-400"
            ]}
          >
            <span class={[
              "size-2.5 shrink-0 rounded-full",
              if(e.ignored, do: "bg-gray-300", else: dot(e.level))
            ]} />
            <span class="min-w-0 truncate">{e.where}</span>
            <.icon :if={i == 1} name="hero-chevron-right-mini" class="ml-auto size-4 text-indigo-500" />
          </li>
          <li class="px-5 py-3 text-xs text-gray-400">
            {@flow.checks_run - length(@entries)} checks passing
          </li>
        </ul>
        <div class="space-y-5 p-6">
          <div>
            <span class={[
              "rounded px-1.5 py-0.5 text-[11px] font-semibold uppercase tracking-wide",
              solid(:error)
            ]}>error</span>
            <h4 class="mt-2 text-base font-semibold text-gray-900">
              Review / Decision has no published version
            </h4>
            <p class="mt-1 text-sm text-gray-600">
              Users start a form by pinning its latest published version. Without one, the Decision step cannot be started, so a reviewer cannot finish the flow.
            </p>
          </div>
          <dl class="grid grid-cols-2 gap-3 text-sm">
            <.fact label="Where">Dog License / Review</.fact>
            <.fact label="Check">form_not_published</.fact>
          </dl>
          <div class="rounded-lg bg-gray-50 p-3 text-sm text-gray-700">
            <span class="font-medium">To fix:</span> open the form and publish its draft.
          </div>
          <div class="flex items-center justify-between">
            <button
              type="button"
              class="rounded-lg bg-gray-900 px-3 py-1.5 text-sm font-medium text-white"
            >Open Decision</button>
            <.switch on={false} label="Ignore this" />
          </div>
        </div>
      </div>
    </.panel>
    """
  end

  def modal(%{direction: :by_location} = assigns) do
    ~H"""
    <.panel title="Health check" subtitle={@flow.name}>
      <div class="mb-6 flex flex-wrap items-center gap-x-6 gap-y-2 text-sm text-gray-600">
        <span><span class="font-semibold text-gray-900">{@flow.steps}</span> steps</span>
        <span><span class="font-semibold text-gray-900">{@flow.subflows}</span> subflows</span>
        <span><span class="font-semibold text-gray-900">{@flow.forms}</span> forms</span>
        <span><span class="font-semibold text-gray-900">{Enum.join(@flow.perspectives, ", ")}</span></span>
        <span class="ml-auto"><span class="font-semibold text-red-600">{count(@entries, :error)}</span>
        · <span class="font-semibold text-amber-600">{count(@entries, :warning)}</span>
        · <span class="font-semibold text-sky-600">{count(@entries, :info)}</span>
        · <span class="text-gray-400">{Enum.count(@entries, & &1.ignored)} ignored</span></span>
      </div>
      <div :for={{name, sub, items} <- grouped(@entries)} class="mb-5 last:mb-0">
        <div class="mb-2 flex items-baseline justify-between">
          <h4 class="text-sm font-semibold text-gray-900">
            {name} <span class="font-normal text-gray-400">{sub}</span>
          </h4>
          <button type="button" class="text-xs text-indigo-600 hover:underline">Open canvas</button>
        </div>
        <p
          :if={items == []}
          class="rounded-lg border border-dashed border-gray-200 px-3 py-2 text-sm text-gray-400"
        >
          Nothing to report.
        </p>
        <ul
          :if={items != []}
          class="overflow-hidden rounded-lg border border-gray-200 divide-y divide-gray-100"
        >
          <li
            :for={e <- items}
            class={[
              "flex items-center justify-between gap-4 px-3 py-2.5 text-sm",
              e.ignored && "bg-gray-50 text-gray-400"
            ]}
          >
            <span class="flex items-center gap-2">
              <span class={[
                "size-2.5 shrink-0 rounded-full",
                if(e.ignored, do: "bg-gray-300", else: dot(e.level))
              ]} />
              <span class={e.ignored && "line-through"}>{short(e.message)}</span>
            </span>
            <.switch on={e.ignored != nil} small />
          </li>
        </ul>
      </div>
    </.panel>
    """
  end

  # -- Shared pieces ------------------------------------------------------------------

  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :padded, :boolean, default: true
  slot :inner_block, required: true

  defp panel(assigns) do
    ~H"""
    <div class="w-[44rem] max-w-full overflow-hidden rounded-xl border border-gray-200 bg-white shadow-xl">
      <div class="flex items-start justify-between gap-4 border-b border-gray-100 px-6 py-4">
        <div>
          <h3 class="text-lg font-semibold text-gray-900">{@title}</h3>
          <p :if={@subtitle} class="text-sm text-gray-500">{@subtitle}</p>
        </div>
        <span class="text-gray-400">✕</span>
      </div>
      <div class={@padded && "p-6"}>{render_slot(@inner_block)}</div>
    </div>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp fact(assigns) do
    ~H"""
    <div>
      <dt class="text-xs text-gray-500">{@label}</dt>
      <dd class="mt-0.5 font-medium text-gray-900">{render_slot(@inner_block)}</dd>
    </div>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp row(assigns) do
    ~H"""
    <div class="flex justify-between gap-2">
      <dt class="text-gray-500">{@label}</dt>
      <dd class="font-medium text-gray-900">{render_slot(@inner_block)}</dd>
    </div>
    """
  end

  attr :level, :atom, required: true
  attr :count, :integer, required: true

  defp tile(assigns) do
    ~H"""
    <div class="rounded-lg border border-gray-200 px-4 py-3">
      <p class="text-xs text-gray-500">{String.capitalize(plural(@level, 2))}</p>
      <p class={[
        "mt-1 text-2xl font-semibold",
        if(@count > 0 and @level != :ignored, do: text(@level), else: "text-gray-900")
      ]}>
        {@count}
      </p>
    </div>
    """
  end

  attr :on, :boolean, required: true
  attr :small, :boolean, default: false
  attr :bare, :boolean, default: false
  attr :label, :string, default: nil

  defp switch(assigns) do
    ~H"""
    <button
      type="button"
      role="switch"
      aria-checked={to_string(@on)}
      class="inline-flex shrink-0 items-center gap-2 text-sm"
    >
      <span class={[
        "relative inline-flex shrink-0 items-center rounded-full transition-colors",
        if(@small, do: "h-5 w-9", else: "h-6 w-11"),
        if(@on, do: "bg-gray-900", else: "bg-gray-300")
      ]}>
        <span class={[
          "inline-block rounded-full bg-white shadow transition-transform",
          if(@small, do: "size-4", else: "size-5"),
          if(@on, do: if(@small, do: "translate-x-4", else: "translate-x-5"), else: "translate-x-0.5")
        ]} />
      </span>
      <span :if={!@bare} class={if(@on, do: "font-medium text-gray-900", else: "text-gray-500")}>
        {@label || if(@on, do: "Ignored", else: "Ignore")}
      </span>
    </button>
    """
  end

  # -- Helpers ----------------------------------------------------------------------

  defp level(%{counts: c}) do
    cond do
      c.error > 0 -> :error
      c.warning > 0 -> :warning
      c.info > 0 -> :info
      true -> :ok
    end
  end

  defp open(%{counts: c}), do: c.error + c.warning + c.info
  defp passed(state), do: @flow.checks_run - open(state)
  defp count_or_check(state), do: if(level(state) == :ok, do: "✓", else: open(state))

  defp present(%{counts: c}),
    do: for(lvl <- [:error, :warning, :info], c[lvl] > 0, do: {lvl, c[lvl]})

  defp words(state) do
    case present(state) do
      [] ->
        if state.counts.ignored > 0,
          do: "Healthy, #{state.counts.ignored} ignored",
          else: "Healthy"

      levels ->
        Enum.map_join(levels, ", ", fn {lvl, n} -> "#{n} #{plural(lvl, n)}" end)
    end
  end

  defp plural(:error, 1), do: "error"
  defp plural(:error, _), do: "errors"
  defp plural(:warning, 1), do: "warning"
  defp plural(:warning, _), do: "warnings"
  defp plural(:info, _), do: "info"
  defp plural(:ignored, _), do: "ignored"

  defp count(entries, lvl), do: Enum.count(entries, &(&1.level == lvl and is_nil(&1.ignored)))
  defp count_all(entries, lvl), do: Enum.count(entries, &(&1.level == lvl))

  # The message without its quoted subject, when a row already names it
  defp short(message) do
    case String.replace(message, ~r/^“[^”]+” /, "") do
      <<first::utf8, rest::binary>> -> String.upcase(<<first::utf8>>) <> rest
      other -> other
    end
  end

  defp grouped(entries) do
    [
      {"Dog License", "root", Enum.filter(entries, &(&1.where == "Dog License"))},
      {"Application", "subflow · Applicant",
       Enum.filter(entries, &String.starts_with?(&1.where, "Application"))},
      {"Review", "subflow · Reviewer",
       Enum.filter(entries, &String.starts_with?(&1.where, "Review"))}
    ]
  end

  defp passing do
    [
      "Dog License connects Start to End",
      "Application connects Start to End",
      "Every step in Application has a published form",
      "Check pet details points “Form to review” at a form in this flow"
    ]
  end

  defp solid(:ok), do: "bg-emerald-500 text-white"
  defp solid(:error), do: "bg-red-500 text-white"
  defp solid(:warning), do: "bg-amber-400 text-amber-950"
  defp solid(:info), do: "bg-sky-500 text-white"

  defp dot(:ok), do: "bg-emerald-500"
  defp dot(:error), do: "bg-red-500"
  defp dot(:warning), do: "bg-amber-400"
  defp dot(:info), do: "bg-sky-500"

  defp border(:ok), do: "border-emerald-500"
  defp border(:error), do: "border-red-500"
  defp border(:warning), do: "border-amber-400"
  defp border(:info), do: "border-sky-500"

  defp text(:ok), do: "text-emerald-600"
  defp text(:error), do: "text-red-600"
  defp text(:warning), do: "text-amber-600"
  defp text(:info), do: "text-sky-600"

  defp stroke(:ok), do: "#10b981"
  defp stroke(:error), do: "#ef4444"
  defp stroke(:warning), do: "#fbbf24"
  defp stroke(:info), do: "#0ea5e9"

  defp tint(:ok), do: "bg-emerald-50 text-emerald-700"
  defp tint(:error), do: "bg-red-50 text-red-700"
  defp tint(:warning), do: "bg-amber-50 text-amber-800"
  defp tint(:info), do: "bg-sky-50 text-sky-700"

  defp chip(:error), do: "border-red-200 bg-red-50 text-red-700"
  defp chip(:warning), do: "border-amber-200 bg-amber-50 text-amber-800"
  defp chip(:info), do: "border-sky-200 bg-sky-50 text-sky-700"

  defp level_icon(:ok), do: "hero-check-circle-solid"
  defp level_icon(:error), do: "hero-exclamation-circle-solid"
  defp level_icon(:warning), do: "hero-exclamation-triangle-solid"
  defp level_icon(:info), do: "hero-information-circle-solid"
end
