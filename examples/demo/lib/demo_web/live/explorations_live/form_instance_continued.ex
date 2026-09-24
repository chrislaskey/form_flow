defmodule DemoWeb.ExplorationsLive.FormInstanceContinued do
  @moduledoc """
  Round three of the form instance page, continuing
  `DemoWeb.ExplorationsLive.FormInstance`. What was picked there is fixed
  here: the T2 header (the form's name alone, "in Dog License" after it),
  the F1 card and F3 pill as the flow badge, R2 as the rail that stays in
  the running. What this page iterates:

    * **F1** at `rounded-2xl`, and **F3** as a rectangle - `rounded-xl`, a
      lighter border, a shadow - each with a way to see the steps, since
      the order can change and a percentage alone does not show it
    * **Edit / View / History** as tabs that are really URL paths, and
      where the form's **status** sits beside them
    * the **History** view: what replaces the form when that tab is chosen
    * **R2** with the tabs and status folded in
    * the **combinations** the pieces suggest: F3 with A2's sticky toolbar,
      F1 with A1's sticky header, R2 with A1

  Hardcoded as before: Dog License, Owner Information open at step two,
  saved three minutes ago by dog_owner. Nothing is wired up.

  Mounted on `live "/explorations/form-instance-continued", ExplorationsLive.FormInstanceContinued`.
  """

  use DemoWeb, :live_view

  import DemoWeb.ExplorationsLive.FormInstanceParts

  alias DemoWeb.ExplorationsLive.Shared

  # -- Data ------------------------------------------------------------------

  @five [
    %{n: 1, label: "About your pet", status: :done},
    %{n: 2, label: "Owner Information", status: :current},
    %{n: 3, label: "Health Information", status: :pending},
    %{n: 4, label: "Household Information", status: :pending},
    %{n: 5, label: "License Options", status: :pending}
  ]

  @many_labels [
    {"Pet", "Pet details"},
    {"Pet", "Owner contact"},
    {"Pet", "Co-owner"},
    {"Pet", "Address history"},
    {"Pet", "Vaccinations"},
    {"Pet", "Rabies certificate"},
    {"Pet", "Microchip"},
    {"Pet", "Spay or neuter"},
    {"Household", "Household members"},
    {"Household", "Other pets"},
    {"Household", "Property"},
    {"Household", "Fencing"},
    {"Household", "Landlord consent"},
    {"Household", "Insurance"},
    {"Household", "Prior licenses"},
    {"Household", "Violations"},
    {"History and options", "Emergency contact"},
    {"History and options", "Veterinarian"},
    {"History and options", "Behavior"},
    {"History and options", "Training"},
    {"History and options", "Service animal"},
    {"History and options", "License options"},
    {"History and options", "Fees"},
    {"History and options", "Declaration"}
  ]

  @many @many_labels
        |> Enum.with_index(1)
        |> Enum.map(fn {{group, label}, n} ->
          %{
            n: n,
            group: group,
            label: label,
            status:
              cond do
                n < 7 -> :done
                n == 7 -> :current
                true -> :pending
              end
          }
        end)

  # The form's event records, newest first, for the History view
  @events [
    %{what: "Saved", who: "dog_owner", when: "3 minutes ago", at: "2026-09-16 17:42 UTC"},
    %{what: "Saved", who: "dog_owner", when: "18 minutes ago", at: "2026-09-16 17:27 UTC"},
    %{
      what: "Reopened",
      who: "reviewer",
      when: "yesterday",
      at: "2026-09-15 09:12 UTC",
      note: "Phone number does not match the vaccination record."
    },
    %{what: "Submitted", who: "dog_owner", when: "3 days ago", at: "2026-09-13 16:05 UTC"},
    %{what: "Saved", who: "dog_owner", when: "3 days ago", at: "2026-09-13 15:58 UTC"},
    %{what: "Started", who: "dog_owner", when: "3 days ago", at: "2026-09-13 15:40 UTC"}
  ]

  @cards [
    %{
      id: :plain,
      title: "F1a · Rounded card",
      note:
        "Round two's F1 at rounded-2xl: ring, back link, flow name, step count and what is next."
    },
    %{
      id: :toggle,
      title: "F1b · Card with Show steps",
      note:
        "A Show steps control at the card's right unfolds every step inside the card, in columns, the current one bold. Closed by default; the card stays F1a's height until asked."
    },
    %{
      id: :segments,
      title: "F1c · Card with segments along the bottom",
      note:
        "One segment per step runs along the card's lower edge, so the count and the position are a shape; each names itself on hover. The steps are always visible without a list."
    },
    %{
      id: :caret,
      title: "F1d · Card with a caret menu",
      note:
        "A caret at the card's right opens the steps as a dropdown over the form rather than inside the card. The card never changes size."
    }
  ]

  @pills [
    %{
      id: :rect,
      title: "F3a · Rectangle",
      note:
        "Round two's pill at rounded-xl with a zinc-200 border and a small shadow: ring, flow name, step count and back link."
    },
    %{
      id: :caret,
      title: "F3b · Rectangle with a caret",
      note:
        "A caret on the right edge opens the steps as a dropdown, aligned to the badge's right, grouped under their subflow when there is more than one. Click to open."
    },
    %{
      id: :hover,
      title: "F3c · Rectangle that opens on hover",
      note:
        "The same dropdown, shown while the pointer rests on the badge - no caret, the whole badge is the trigger. Hover to see it."
    },
    %{
      id: :bar,
      title: "F3d · Rectangle with a bar, no ring",
      note:
        "The percentage as a number, a hairline bar under the flow's name in place of the ring. Flatter, and the bar can be segmented later."
    }
  ]

  @tabs [
    %{
      id: :underline,
      title: "N1 · Underlined tabs",
      note:
        "Edit, View, History along one hairline, the chosen one underlined in the brand colour. Each is a link to its own path."
    },
    %{
      id: :segmented,
      title: "N2 · Segmented control",
      note:
        "The three in a grey capsule, the chosen one white with a shadow. Compact enough to sit in a toolbar or a rail."
    },
    %{
      id: :links,
      title: "N3 · Text links",
      note:
        "Edit · View · History as plain links with dots between, the chosen one bold. The quietest; reads as navigation rather than as a control."
    }
  ]

  @statuses [
    %{
      id: :title,
      title: "ST1 · Badge after the title",
      note:
        "A soft badge - Draft, Submitted, Reopened - at the end of the title line. Read with the name."
    },
    %{
      id: :tabs,
      title: "ST2 · Badge at the tabs' right",
      note:
        "The tab row carries it on its right end, so status and the view of it sit on one line and the title stays a title."
    },
    %{
      id: :save,
      title: "ST3 · Word inside the save state",
      note:
        "\"Draft · saved 3 min ago · dog_owner\" - the status is the first word of the save state, beside the buttons. One line says everything about where the form stands."
    }
  ]

  @histories [
    %{
      id: :timeline,
      title: "H1 · Timeline",
      note:
        "The events newest first down a hairline, a dot each, what and who on the line, when under it, a reviewer's note quoted beneath."
    },
    %{
      id: :table,
      title: "H2 · Table",
      note:
        "Event, who, when as three columns; the note as a second line in the first. Scans faster past a dozen rows."
    }
  ]

  @rails [
    %{
      id: :plain,
      title: "R2a · Narrow rail",
      note:
        "Round two's R2: a ring and the flow in the rail's head, groups folded to the current one."
    },
    %{
      id: :tabs_in_rail,
      title: "R2b · Tabs and status in the rail",
      note:
        "Edit, View, History as a short list under the rail's head, the status badge beside the flow's name. The rail is the whole left edge of the page; the header above the form carries only the name and the actions."
    },
    %{
      id: :tabs_above,
      title: "R2c · Tabs above the form",
      note:
        "The rail unchanged; N1 tabs under the form's header with the status at their right, so the rail stays about the flow and the tabs about the form."
    }
  ]

  @combos [
    %{
      id: :f3_a2,
      title: "X1 · F3 + A2, editing",
      note:
        "T2 header with the F3b rectangle on its right; under it A2's toolbar stays at the top as the form scrolls, with the N1 tabs on its left and the save state and buttons on its right. Scroll the frame. The status badge sits between the save state and the buttons."
    },
    %{
      id: :f3_a2_history,
      title: "X2 · F3 + A2, History chosen",
      note:
        "X1 with History as the path: the toolbar keeps the tabs, drops Save draft and Submit, and the form gives way to the H1 timeline."
    },
    %{
      id: :f3_a2_flush,
      title: "X1b · F3 + A2, no top border on the bar",
      note:
        "X1 with the toolbar's top border gone and the gap above it closed, as X3a's sticky block has none: the tabs read as the header's last line, and the whole header is shorter. Status and save state as in X1."
    },
    %{
      id: :f1_a1_tabs_in_header,
      title: "X3a · F1 + A1, tabs in the sticky header",
      note:
        "The whole header is sticky: title and actions, then the N1 tabs under them as part of what stays. The F1b card scrolls away with the form."
    },
    %{
      id: :f1_a1_segmented,
      title: "X3b · F1 + A1, segmented tabs among the actions",
      note:
        "The header is sticky, with the N2 capsule left of the save state and the buttons, one row; the F1b card scrolls with the form."
    },
    %{
      id: :f1_a1_swapped,
      title: "X3c · F1 + A1, tabs after the title, status among the actions",
      note:
        "X3b with the two swapped: the N2 capsule sits after the title where Draft was, and the Draft badge leads the actions. The F1b card scrolls with the form."
    },
    %{
      id: :r2_a1,
      title: "X4 · R2b + A1",
      note:
        "The rail holds the flow, its steps, and the tabs, and stays; the header with the actions stays at the top above the scrolling form."
    }
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Form instance page, continued")
     |> assign(:many?, false)
     |> assign(:cards, @cards)
     |> assign(:pills, @pills)
     |> assign(:tabs, @tabs)
     |> assign(:statuses, @statuses)
     |> assign(:histories, @histories)
     |> assign(:rails, @rails)
     |> assign(:combos, @combos)
     |> assign(:events, @events)}
  end

  @impl true
  def handle_event("toggle_many", _params, socket) do
    {:noreply, assign(socket, :many?, not socket.assigns.many?)}
  end

  defp forms(true), do: @many
  defp forms(false), do: @five

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="space-y-6">
        <header class="space-y-2">
          <Shared.back_link />
          <h1 class="text-2xl font-semibold">Form instance page, continued</h1>
          <p class="text-base-content/70">
            Round three. Fixed from <.link
              navigate="/explorations/form-instance"
              class="text-indigo-600 hover:underline"
            >
              round two
            </.link>: the T2 header, the F1 card and F3 pill as the flow badge, R2 as
            the rail. Iterated here: both badges with a way to see the steps, F3
            as a rectangle, Edit / View / History as tabs that are paths, where
            the status sits, what the History view is, R2 with those folded in,
            and the combinations at the bottom. Hardcoded; nothing is wired up.
          </p>
          <label class="inline-flex items-center gap-2 text-sm text-gray-700">
            <input
              type="checkbox"
              class="checkbox checkbox-sm checkbox-primary"
              checked={@many?}
              phx-click="toggle_many"
            /> Draw the badges, rails, and combinations with a twenty-four step flow instead of five
          </label>
        </header>

        <.section
          id="cards"
          title="F1 · the card"
          intro="Rounded-2xl, and four ways to reach the steps from it. Under the T2 header."
        >
          <div :for={d <- @cards} class="space-y-3">
            <.direction_title d={d} />
            <.frame label={"#{length(forms(@many?))} steps · #{percent(forms(@many?))}%"}>
              <.page_header forms={forms(@many?)} />
              <.card variant={d.id} forms={forms(@many?)} />
              <.mock_form />
            </.frame>
          </div>
        </.section>

        <.section
          id="pills"
          title="F3 · the badge in the header"
          intro="A rectangle now: rounded-xl, a zinc-200 border, a small shadow. In the header's right, where the actions will also be."
        >
          <div :for={d <- @pills} class="space-y-3">
            <.direction_title d={d} />
            <.frame label={"#{length(forms(@many?))} steps · #{percent(forms(@many?))}%"}>
              <.page_header forms={forms(@many?)}>
                <:actions>
                  <.pill id={"pill-#{d.id}"} variant={d.id} forms={forms(@many?)} />
                </:actions>
              </.page_header>
              <.mock_form />
            </.frame>
          </div>
        </.section>

        <.section
          id="tabs"
          title="Edit / View / History"
          intro="Three views of one form, each its own path - .../edit, the form's own, .../history - drawn as tabs. Edit is the one chosen."
        >
          <div :for={d <- @tabs} class="space-y-3">
            <.direction_title d={d} />
            <.frame label="Owner Information · editing">
              <.page_header forms={forms(false)} />
              <.tabs variant={d.id} active={:edit} />
              <div class="mt-5"><.mock_form /></div>
            </.frame>
          </div>
        </.section>

        <.section
          id="statuses"
          title="Status"
          intro="Where the form's status - Draft, Submitted, Reopened - reads. Drawn with the N1 tabs and C3's actions."
        >
          <div :for={d <- @statuses} class="space-y-3">
            <.direction_title d={d} />
            <.frame label="Owner Information · draft">
              <.page_header forms={forms(false)} status={d.id == :title && "Draft"}>
                <:actions>
                  <.save_state prefix={d.id == :save && "Draft"} />
                  <button type="button" class="btn btn-ghost">Save draft</button>
                  <button type="button" class="btn btn-primary">Submit</button>
                </:actions>
              </.page_header>
              <.tabs variant={:underline} active={:edit} status={d.id == :tabs && "Draft"} />
              <div class="mt-5"><.mock_form /></div>
            </.frame>
          </div>
        </.section>

        <.section
          id="histories"
          title="History"
          intro="What stands in for the form when History is the path: the form's event records - started, saved, submitted, reopened - with who and when."
        >
          <div :for={d <- @histories} class="space-y-3">
            <.direction_title d={d} />
            <.frame label="Owner Information · history">
              <.page_header forms={forms(false)} status="Reopened" />
              <.tabs variant={:underline} active={:history} />
              <div class="mt-5"><.history variant={d.id} events={@events} /></div>
            </.frame>
          </div>
        </.section>

        <.section
          id="rails"
          title="R2 · the narrow rail"
          intro="The rail as a full left column, groups folded to the current one, with the tabs and the status placed in it or beside it."
        >
          <div :for={d <- @rails} class="space-y-3">
            <.direction_title d={d} />
            <.frame label={"#{length(forms(@many?))} steps"} flush>
              <.rail_page variant={d.id} forms={forms(@many?)} />
            </.frame>
          </div>
        </.section>

        <.section
          id="combos"
          title="Combinations"
          intro="The pieces put together on one page each, in scrolling frames with a long form, so what stays at the top and what scrolls can be seen."
        >
          <div :for={d <- @combos} class="space-y-3">
            <.direction_title d={d} />
            <.frame label="Owner Information · scroll the frame" flush>
              <.combo variant={d.id} forms={forms(@many?)} events={@events} />
            </.frame>
          </div>
        </.section>
      </div>
    </Layouts.app>
    """
  end

  # -- Page furniture --------------------------------------------------------

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :intro, :string, required: true
  slot :inner_block, required: true

  defp section(assigns) do
    ~H"""
    <section id={@id} class="space-y-10 border-t border-gray-200 pt-10">
      <header class="space-y-2">
        <h2 class="text-2xl font-semibold">{@title}</h2>
        <p class="text-base-content/70">{@intro}</p>
      </header>
      {render_slot(@inner_block)}
    </section>
    """
  end

  attr :d, :map, required: true

  defp direction_title(assigns) do
    ~H"""
    <div class="flex flex-wrap items-baseline gap-x-3 gap-y-1">
      <h3 class="font-semibold text-gray-900">{@d.title}</h3>
      <p class="text-sm text-gray-500">{@d.note}</p>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :flush, :boolean, default: false
  slot :inner_block, required: true

  defp frame(assigns) do
    ~H"""
    <div class="space-y-1.5">
      <p class="text-[10px] font-semibold uppercase tracking-wider text-gray-400">{@label}</p>
      <div class={[
        "rounded-xl border border-dashed border-gray-300 bg-white",
        !@flush && "px-6 py-5"
      ]}>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  # -- History ---------------------------------------------------------------

  attr :variant, :atom, required: true
  attr :events, :list, required: true

  defp history(%{variant: :timeline} = assigns) do
    ~H"""
    <ol class="relative ml-2 border-l border-zinc-200 pl-6">
      <li :for={event <- @events} class="relative pb-6 last:pb-0">
        <span class={[
          "absolute -left-[31px] top-1.5 size-2.5 rounded-full ring-4 ring-white",
          event_dot(event.what)
        ]} />
        <p class="text-sm">
          <span class="font-semibold">{event.what}</span>
          <span class="text-zinc-500">by</span>
          <code class="text-xs">{event.who}</code>
        </p>
        <p class="text-xs text-zinc-500" title={event.at}>{event.when} · {event.at}</p>
        <blockquote
          :if={event[:note]}
          class="mt-2 border-l-2 border-zinc-200 pl-3 text-sm text-zinc-600"
        >
          {event.note}
        </blockquote>
      </li>
    </ol>
    """
  end

  defp history(%{variant: :table} = assigns) do
    ~H"""
    <div class="overflow-hidden rounded-lg border border-zinc-200">
      <table class="w-full text-sm">
        <thead class="bg-zinc-50 text-left text-xs font-medium text-zinc-500">
          <tr>
            <th class="px-4 py-2">Event</th>
            <th class="px-4 py-2">Who</th>
            <th class="px-4 py-2">When</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-zinc-200">
          <tr :for={event <- @events}>
            <td class="px-4 py-2.5">
              <span class="flex items-center gap-2">
                <span class={["size-2 rounded-full", event_dot(event.what)]} />
                <span class="font-medium">{event.what}</span>
              </span>
              <p :if={event[:note]} class="mt-1 pl-4 text-xs text-zinc-500">{event.note}</p>
            </td>
            <td class="px-4 py-2.5"><code class="text-xs">{event.who}</code></td>
            <td class="px-4 py-2.5 text-zinc-500" title={event.at}>
              {event.when}
              <span class="block text-xs text-zinc-400">{event.at}</span>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp event_dot("Submitted"), do: "bg-success"
  defp event_dot("Reopened"), do: "bg-warning"
  defp event_dot("Started"), do: "bg-primary"
  defp event_dot(_saved), do: "bg-zinc-300"

  # -- R2 rails ------------------------------------------------------------------

  attr :variant, :atom, required: true
  attr :forms, :list, required: true

  defp rail_page(%{variant: :plain} = assigns) do
    ~H"""
    <div class="grid lg:grid-cols-4">
      <aside class="border-b border-zinc-200 lg:col-span-1 lg:border-b-0 lg:border-r">
        <.rail_head forms={@forms} />
        <.rail_list forms={@forms} />
      </aside>
      <div class="px-6 py-5 lg:col-span-3">
        <.page_header forms={@forms} flow={false}>
          <:actions>
            <.save_state />
            <button type="button" class="btn btn-ghost">Save draft</button>
            <button type="button" class="btn btn-primary">Submit</button>
          </:actions>
        </.page_header>
        <.mock_form />
      </div>
    </div>
    """
  end

  defp rail_page(%{variant: :tabs_in_rail} = assigns) do
    ~H"""
    <div class="grid lg:grid-cols-4">
      <aside class="border-b border-zinc-200 lg:col-span-1 lg:border-b-0 lg:border-r">
        <.rail_head forms={@forms} status="Draft" />
        <.rail_tabs active={:edit} />
        <.rail_list forms={@forms} />
      </aside>
      <div class="px-6 py-5 lg:col-span-3">
        <.page_header forms={@forms} flow={false}>
          <:actions>
            <.save_state />
            <button type="button" class="btn btn-ghost">Save draft</button>
            <button type="button" class="btn btn-primary">Submit</button>
          </:actions>
        </.page_header>
        <.mock_form />
      </div>
    </div>
    """
  end

  defp rail_page(%{variant: :tabs_above} = assigns) do
    ~H"""
    <div class="grid lg:grid-cols-4">
      <aside class="border-b border-zinc-200 lg:col-span-1 lg:border-b-0 lg:border-r">
        <.rail_head forms={@forms} />
        <.rail_list forms={@forms} />
      </aside>
      <div class="px-6 py-5 lg:col-span-3">
        <.page_header forms={@forms} flow={false}>
          <:actions>
            <.save_state />
            <button type="button" class="btn btn-ghost">Save draft</button>
            <button type="button" class="btn btn-primary">Submit</button>
          </:actions>
        </.page_header>
        <.tabs variant={:underline} active={:edit} status="Draft" />
        <div class="mt-5"><.mock_form /></div>
      </div>
    </div>
    """
  end

  attr :forms, :list, required: true
  attr :status, :any, default: nil

  defp rail_head(assigns) do
    ~H"""
    <div class="flex items-center gap-3 border-b border-zinc-200 px-4 py-3">
      <.ring forms={@forms} size={:sm} />
      <div class="min-w-0 flex-1 leading-tight">
        <p class="flex items-center gap-2">
          <span class="truncate text-sm font-semibold">Dog License</span>
          <.status_badge :if={@status} status={@status} class="badge-xs" />
        </p>
        <p class="text-xs text-zinc-500">
          Step {current(@forms).n} of {length(@forms)} ·
          <span class="hover:underline">back to flow overview</span>
        </p>
      </div>
    </div>
    """
  end

  attr :active, :atom, required: true

  defp rail_tabs(assigns) do
    assigns = assign(assigns, :items, tab_items())

    ~H"""
    <nav class="border-b border-zinc-200 px-2 py-2" aria-label="Views">
      <span
        :for={{key, label} <- @items}
        class={[
          "block rounded-md px-2 py-1 text-sm",
          if(key == @active, do: "bg-zinc-100 font-semibold", else: "text-zinc-500 hover:bg-zinc-50")
        ]}
        aria-current={key == @active && "page"}
      >
        {label}
      </span>
    </nav>
    """
  end

  attr :forms, :list, required: true

  defp rail_list(assigns) do
    assigns = assign(assigns, :groups, groups(assigns.forms))

    ~H"""
    <nav aria-label="Steps">
      <%= if length(@groups) == 1 do %>
        <ol class="py-2">
          <.rail_row :for={form <- @forms} form={form} forms={@forms} />
        </ol>
      <% else %>
        <details
          :for={group <- @groups}
          class="group/g border-b border-zinc-200 last:border-b-0"
          open={Enum.any?(group, &(&1.status == :current))}
        >
          <summary class="flex cursor-pointer list-none items-center justify-between gap-2 px-4 py-2 text-xs font-semibold text-zinc-600 hover:bg-zinc-100 [&::-webkit-details-marker]:hidden">
            <span>{Map.get(hd(group), :group)}</span>
            <span class="flex items-center gap-2 font-normal text-zinc-400">
              {group_summary(@forms, group)}
              <.icon
                name="hero-chevron-right"
                class="size-4 transition-transform group-open/g:rotate-90"
              />
            </span>
          </summary>
          <ol class="pb-2">
            <.rail_row :for={form <- group} form={form} forms={@forms} />
          </ol>
        </details>
      <% end %>
    </nav>
    """
  end

  attr :form, :map, required: true
  attr :forms, :list, required: true

  defp rail_row(assigns) do
    ~H"""
    <.step_row
      form={@form}
      forms={@forms}
      class={["px-4 py-2 text-sm", @form.status == :current && "bg-zinc-100"]}
    />
    """
  end

  defp group_summary(forms, group) do
    cond do
      Enum.any?(group, &(&1.status == :current)) -> "#{length(group)} steps"
      List.last(group).n < current(forms).n -> "behind you"
      true -> "#{length(group)} steps ahead"
    end
  end

  # -- Combinations ----------------------------------------------------------

  attr :variant, :atom, required: true
  attr :forms, :list, required: true
  attr :events, :list, required: true

  defp combo(%{variant: :f3_a2} = assigns) do
    ~H"""
    <div class="max-h-[30rem] overflow-y-auto">
      <div class="px-6 pt-5">
        <.page_header forms={@forms} class="mb-0">
          <:actions><.pill id="x1-pill" variant={:caret} forms={@forms} /></:actions>
        </.page_header>
      </div>
      <.toolbar active={:edit} editing status="Draft" />
      <div class="px-6 py-5"><.mock_form long /></div>
    </div>
    """
  end

  defp combo(%{variant: :f3_a2_history} = assigns) do
    ~H"""
    <div class="max-h-[30rem] overflow-y-auto">
      <div class="px-6 pt-5">
        <.page_header forms={@forms} class="mb-0">
          <:actions><.pill id="x2-pill" variant={:caret} forms={@forms} /></:actions>
        </.page_header>
      </div>
      <.toolbar active={:history} status="Reopened" />
      <div class="px-6 py-5"><.history variant={:timeline} events={@events} /></div>
    </div>
    """
  end

  defp combo(%{variant: :f3_a2_flush} = assigns) do
    ~H"""
    <div class="max-h-[30rem] overflow-y-auto">
      <div class="px-6 pt-5">
        <.page_header forms={@forms} class="mb-0">
          <:actions><.pill id="x1b-pill" variant={:caret} forms={@forms} /></:actions>
        </.page_header>
      </div>
      <.toolbar active={:edit} editing status="Draft" flush />
      <div class="px-6 py-5"><.mock_form long /></div>
    </div>
    """
  end

  defp combo(%{variant: :f1_a1_tabs_in_header} = assigns) do
    ~H"""
    <div class="max-h-[30rem] overflow-y-auto">
      <div class="sticky top-0 z-10 bg-white/95 px-6 pt-4 backdrop-blur">
        <.page_header forms={@forms} class="mb-3">
          <:actions>
            <.status_badge status="Draft" class="mr-2" />
            <button type="button" class="btn btn-ghost">Save draft</button>
            <button type="button" class="btn btn-primary">Submit</button>
          </:actions>
        </.page_header>
        <.tabs variant={:underline} active={:edit}>
          <:aside><.save_state /></:aside>
        </.tabs>
      </div>
      <div class="px-6 py-5">
        <.card variant={:toggle} forms={@forms} />
        <.mock_form long />
      </div>
    </div>
    """
  end

  defp combo(%{variant: :f1_a1_segmented} = assigns) do
    ~H"""
    <div class="max-h-[30rem] overflow-y-auto">
      <div class="sticky top-0 z-10 border-b border-zinc-200 bg-white/95 px-6 pt-4 backdrop-blur">
        <.page_header forms={@forms} status="Draft">
          <:actions>
            <.tabs variant={:segmented} active={:edit} class="mr-2" />
            <.save_state />
            <button type="button" class="btn btn-ghost">Save draft</button>
            <button type="button" class="btn btn-primary">Submit</button>
          </:actions>
        </.page_header>
      </div>
      <div class="px-6 py-5">
        <.card variant={:toggle} forms={@forms} />
        <.mock_form long />
      </div>
    </div>
    """
  end

  defp combo(%{variant: :f1_a1_swapped} = assigns) do
    ~H"""
    <div class="max-h-[30rem] overflow-y-auto">
      <div class="sticky top-0 z-10 border-b border-zinc-200 bg-white/95 px-6 pt-4 backdrop-blur">
        <.page_header forms={@forms}>
          <:title_aside><.tabs variant={:segmented} active={:edit} /></:title_aside>
          <:actions>
            <.status_badge status="Draft" />
            <.save_state />
            <button type="button" class="btn btn-ghost">Save draft</button>
            <button type="button" class="btn btn-primary">Submit</button>
          </:actions>
        </.page_header>
      </div>
      <div class="px-6 py-5">
        <.card variant={:toggle} forms={@forms} />
        <.mock_form long />
      </div>
    </div>
    """
  end

  defp combo(%{variant: :r2_a1} = assigns) do
    ~H"""
    <div class="max-h-[30rem] overflow-y-auto">
      <div class="grid lg:grid-cols-4">
        <aside class="self-start border-b border-zinc-200 lg:sticky lg:top-0 lg:col-span-1 lg:max-h-[30rem] lg:overflow-y-auto lg:border-b-0 lg:border-r">
          <.rail_head forms={@forms} status="Draft" />
          <.rail_tabs active={:edit} />
          <.rail_list forms={@forms} />
        </aside>
        <div class="lg:col-span-3">
          <div class="sticky top-0 z-10 border-b border-zinc-200 bg-white/95 px-6 pt-4 backdrop-blur">
            <.page_header forms={@forms} flow={false}>
              <:actions>
                <.save_state />
                <button type="button" class="btn btn-ghost">Save draft</button>
                <button type="button" class="btn btn-primary">Submit</button>
              </:actions>
            </.page_header>
          </div>
          <div class="px-6 py-5"><.mock_form long /></div>
        </div>
      </div>
    </div>
    """
  end
end
