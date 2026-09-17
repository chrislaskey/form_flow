defmodule DemoWeb.ExplorationsLive.FormInstance do
  @moduledoc """
  Scratch page for the form page inside a flow instance - `/users/:id/forms/...`
  - the page a user fills a form on. Five things are drawn several ways:

    * the **header**: what the trail and the title say when the subflow's
      name (Applicant, Reviewer) is only the gate that let the viewer in
    * the **flow badge**: the flow's name, how far through it the user is
      as a percentage and a step count, and the way back to the flow's
      page - one block that says the same at five steps and at thirty
    * the **side rail**: the forms as a full left column, the header and
      the form to its right
    * the **actions**: Submit and a future Save draft top right, staying
      in reach as a long form scrolls
    * the **save state**: when the form was last saved and by whom, beside
      the actions, in each state it can be in

  "How far" is the step the user is on over the count - step 2 of 5 is
  40% - not the forms finished. Finished-versus-current was a distinction
  the first round drew and the second dropped: what the user wants to know
  is how far along they are, not which of the two words applies.

  Everything is hardcoded - one Dog License instance, its Applicant forms,
  the Owner Information form open at step two - and nothing is wired up:
  Save draft does not exist in the library yet, and this page is where its
  shape is decided before it does. Round one of this page drew step chips,
  dots, and bottom bars; the twenty-four step toggle showed which of them
  did not scale, and round two keeps only what did.

  Mounted on `live "/explorations/form-instance", ExplorationsLive.FormInstance`.
  """

  use DemoWeb, :live_view

  alias DemoWeb.ExplorationsLive.Shared

  # -- Data ------------------------------------------------------------------

  # The five forms of the Applicant subflow as the snapshot has them. The
  # user is on the second.
  @five [
    %{n: 1, label: "About your pet", status: :done},
    %{n: 2, label: "Owner Information", status: :current},
    %{n: 3, label: "Health Information", status: :pending},
    %{n: 4, label: "Household Information", status: :pending},
    %{n: 5, label: "License Options", status: :pending}
  ]

  # A flow that has grown: twenty-four forms in three subflows, the user
  # on the seventh. What every direction has to survive.
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

  @headers [
    %{
      id: :current,
      title: "T1 · Current",
      note:
        "For reference. The subflow's name rides in the trail and in the title: \"Applicant / Owner Information\". It is the gate, not the page."
    },
    %{
      id: :form_only,
      title: "T2 · The form's name alone",
      note:
        "Trail Flows / Dog License / Owner Information; title Owner Information in Dog License. Where the user is comes from the badge or the rail, not the title."
    },
    %{
      id: :step_of,
      title: "T3 · Form name, with its place under it",
      note:
        "Same trail and title, plus one quiet line: \"Step 2 of 5 · 40%\". The header says how far along you are before anything else draws."
    }
  ]

  @badges [
    %{
      id: :card,
      title: "F1 · Flow card with a ring",
      note:
        "A bordered card under the header: a back link to the flow's page, the flow's name, a progress ring with the percentage in it, \"Step 2 of 5\", and what comes next. Same size at five steps and at thirty."
    },
    %{
      id: :strip,
      title: "F2 · Flow strip above the title",
      note:
        "A thin bar the width of the page, above the header: ← Dog License on the left, a hairline progress bar across the middle, \"Step 2 of 5 · 40%\" on the right. The header under it is the form's alone."
    },
    %{
      id: :pill,
      title: "F3 · Pill in the header's right",
      note:
        "The header's right side is the badge: a small ring, the flow's name, and the step count with the way back under it, in one pill. Actions, when they come, sit left of it."
    },
    %{
      id: :panel,
      title: "F4 · Badge as the header",
      note:
        "The flow is the page: a big percentage, the flow's name beside it, the step count and the next form under, a back link. The form's own name is the section heading over the form."
    },
    %{
      id: :segments,
      title: "F5 · Strip over segments",
      note:
        "F2's line, with one segment per step in place of the plain bar - so the bar still says how many steps there are and where you are among them, without a label each. The one round-one step direction that scaled."
    }
  ]

  @rails [
    %{
      id: :column,
      title: "R1 · Full left column",
      note:
        "Two columns from the top of the page. Left: the flow's name, its progress, and every form as a list, grouped under their subflow. Right: the header and the form. The rail is the flow's map; the header is the form's."
    },
    %{
      id: :narrow,
      title: "R2 · Narrow rail, groups folded",
      note:
        "A quarter-width rail of numbered steps and short labels; long labels truncate. Groups are collapsible and only the current group opens, so thirty steps fold to a dozen rows."
    },
    %{
      id: :sticky_rail,
      title: "R3 · Rail that stays, header that stays",
      note:
        "R1 with the rail pinned as the form scrolls and the form's header pinned above it, actions in reach. Scroll the frame to see both hold."
    }
  ]

  @actions [
    %{
      id: :header_sticky,
      title: "A1 · The whole header sticks",
      note:
        "Trail, title, and actions top right as the templates pages draw them, and the whole header pins to the top when the form scrolls under it. Scroll the frame."
    },
    %{
      id: :bar_sticky,
      title: "A2 · A toolbar under the header sticks",
      note:
        "The header scrolls away like content; a slim bar right under it - the form's name, the save state, Save draft, Submit - is what pins. Less UI held on screen than A1."
    },
    %{
      id: :actions_float,
      title: "A3 · Only the actions stick",
      note:
        "The header is ordinary; the buttons alone sit in a pill that pins to the top right and floats over the form as it scrolls. The smallest thing that can stay in reach."
    }
  ]

  @saves [
    %{
      id: :dot_text,
      title: "S2a · Dot and text",
      note:
        "Round one's S2: a coloured dot and \"Saved · 3 min ago · dog_owner\" left of the buttons. Grey saved, amber unsaved, a spinner saving, red failed."
    },
    %{
      id: :icon_text,
      title: "S2b · Icon and text",
      note:
        "A small icon says the state - a tick, a pencil, a spinner, a warning triangle - and the text says when and who. No colour needed to read it."
    },
    %{
      id: :chip,
      title: "S2c · A chip with the user's initials",
      note:
        "A soft badge: the saving user's initials in a circle, then \"Saved · 3 min ago\". Who saved it is a face, not an id; the id is the chip's title."
    },
    %{
      id: :under,
      title: "S2d · A line under the buttons",
      note:
        "The buttons stay alone on their row; the state is a tiny right-aligned line beneath them. Quietest of the five, and it keeps the header's height when the text gets long."
    },
    %{
      id: :two_line,
      title: "S2e · Two lines, stacked",
      note:
        "\"Saved\" on top, \"3 min ago · dog_owner\" small under it, beside the buttons. Reads as a status, not a sentence; the user id has its own line to be long on."
    }
  ]

  @states [
    %{id: :saved, word: "Saved", when: "3 min ago", who: "dog_owner"},
    %{id: :unsaved, word: "Unsaved changes", when: "last saved 3 min ago", who: "dog_owner"},
    %{id: :saving, word: "Saving…", when: nil, who: nil},
    %{id: :failed, word: "Could not save", when: "last saved 3 min ago", who: "dog_owner"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Form instance page")
     |> assign(:many?, false)
     |> assign(:headers, @headers)
     |> assign(:badges, @badges)
     |> assign(:rails, @rails)
     |> assign(:actions, @actions)
     |> assign(:saves, @saves)
     |> assign(:states, @states)}
  end

  @impl true
  def handle_event("toggle_many", _params, socket) do
    {:noreply, assign(socket, :many?, not socket.assigns.many?)}
  end

  defp forms(true), do: @many
  defp forms(false), do: @five

  defp current(forms), do: Enum.find(forms, &(&1.status == :current))

  # How far along: the step the user is on over the count. Step 2 of 5 is
  # 40%, step 7 of 24 is 29%.
  defp percent(forms), do: round(current(forms).n / length(forms) * 100)

  defp neighbour(forms, offset) do
    n = current(forms).n + offset
    Enum.find(forms, &(&1.n == n))
  end

  defp groups(forms), do: Enum.chunk_by(forms, &Map.get(&1, :group))

  # The state the in-context headers draw: saved, three minutes ago
  defp saved, do: hd(@states)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="space-y-6">
        <header class="space-y-2">
          <Shared.back_link />
          <h1 class="text-2xl font-semibold">Form instance page</h1>
          <p class="text-base-content/70">
            The page a user fills a form on inside a flow instance. Round two:
            how far along the user is as a percentage and a step count rather
            than finished-versus-current, a flow badge that says the same at
            any size, side rails as a full column, actions top right that stay
            in reach, and the save state beside them in every state. Hardcoded:
            the Dog License instance, its Applicant forms, Owner Information
            open at step two. Nothing is wired up; Save draft does not exist yet.
          </p>
          <label class="inline-flex items-center gap-2 text-sm text-gray-700">
            <input
              type="checkbox"
              class="checkbox checkbox-sm checkbox-primary"
              checked={@many?}
              phx-click="toggle_many"
            /> Draw the badge and rail directions with a twenty-four step flow instead of five
          </label>
        </header>

        <section id="headers" class="space-y-10 border-t border-gray-200 pt-10">
          <header class="space-y-2">
            <h2 class="text-2xl font-semibold">Header directions</h2>
            <p class="text-base-content/70">
              What the trail and the title say. The subflow a form belongs to -
              Applicant, Reviewer - decides who may open it; once someone has, it
              tells them nothing they need.
            </p>
          </header>
          <div :for={d <- @headers} class="space-y-3">
            <.direction_title d={d} />
            <.frame label="Owner Information · step 2 of 5 · Dog License">
              <.page_header direction={d.id} forms={forms(false)} />
            </.frame>
          </div>
        </section>

        <section id="badges" class="space-y-10 border-t border-gray-200 pt-10">
          <header class="space-y-2">
            <h2 class="text-2xl font-semibold">Flow badge directions</h2>
            <p class="text-base-content/70">
              One block that names the flow, says how far through it the user
              is, and leads back to the flow's page. The header under or beside
              it is the form's name alone. Tick the box above to draw each at
              twenty-four steps.
            </p>
          </header>
          <div :for={d <- @badges} class="space-y-3">
            <.direction_title d={d} />
            <.frame label={"#{length(forms(@many?))} steps · #{percent(forms(@many?))}%"}>
              <.badge_page direction={d.id} forms={forms(@many?)} />
            </.frame>
          </div>
        </section>

        <section id="rails" class="space-y-10 border-t border-gray-200 pt-10">
          <header class="space-y-2">
            <h2 class="text-2xl font-semibold">Side rail directions</h2>
            <p class="text-base-content/70">
              The forms as a column of their own, beside the header and the form
              rather than under the header. Tick the box above to draw each at
              twenty-four steps.
            </p>
          </header>
          <div :for={d <- @rails} class="space-y-3">
            <.direction_title d={d} />
            <.frame label={"#{length(forms(@many?))} steps"} flush>
              <.rail_page direction={d.id} forms={forms(@many?)} />
            </.frame>
          </div>
        </section>

        <section id="actions" class="space-y-10 border-t border-gray-200 pt-10">
          <header class="space-y-2">
            <h2 class="text-2xl font-semibold">Action directions</h2>
            <p class="text-base-content/70">
              Save draft and Submit top right, as the admin pages place their
              actions, and kept in reach as a long form scrolls. Each frame
              scrolls; the header's Submit is a remote submit for the form
              under it.
            </p>
          </header>
          <div :for={d <- @actions} class="space-y-3">
            <.direction_title d={d} />
            <.frame label="Owner Information · scroll the frame" flush>
              <.action_page direction={d.id} forms={forms(false)} />
            </.frame>
          </div>
        </section>

        <section id="saves" class="space-y-10 border-t border-gray-200 pt-10">
          <header class="space-y-2">
            <h2 class="text-2xl font-semibold">Save state directions</h2>
            <p class="text-base-content/70">
              When the form was last saved and by whom - the user_id the host
              handed the page - beside the actions, in the four states it can
              be in. Each direction once in the header, then its four states in
              a row.
            </p>
          </header>
          <div :for={d <- @saves} class="space-y-3">
            <.direction_title d={d} />
            <.frame label="Owner Information · saved, then every state">
              <.page_header direction={:form_only} forms={forms(false)}>
                <:actions>
                  <.save_state direction={d.id} state={saved()} placement={:header} />
                  <button type="button" class="btn btn-ghost">Save draft</button>
                  <button type="submit" form="mock-form" class="btn btn-primary">Submit</button>
                </:actions>
              </.page_header>
              <.save_under :if={d.id == :under} state={saved()} />
              <div class="mt-6 grid gap-3 border-t border-dashed border-zinc-200 pt-4 sm:grid-cols-2 xl:grid-cols-4">
                <div :for={s <- @states} class="rounded-lg bg-zinc-50 px-4 py-3">
                  <p class="mb-2 text-[10px] font-semibold uppercase tracking-wider text-zinc-400">
                    {s.id}
                  </p>
                  <.save_state direction={d.id} state={s} placement={:row} />
                </div>
              </div>
            </.frame>
          </div>
        </section>
      </div>
    </Layouts.app>
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
  attr :flush, :boolean, default: false, doc: "no padding - the direction lays out its own"
  slot :inner_block, required: true

  defp frame(assigns) do
    ~H"""
    <div class="space-y-1.5">
      <p class="text-[10px] font-semibold uppercase tracking-wider text-gray-400">{@label}</p>
      <div class={[
        "overflow-hidden rounded-xl border border-dashed border-gray-300 bg-white",
        !@flush && "px-6 py-5"
      ]}>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  # -- Header directions -----------------------------------------------------

  attr :direction, :atom, required: true
  attr :forms, :list, required: true
  attr :class, :any, default: nil
  slot :actions

  defp page_header(%{direction: :current} = assigns) do
    ~H"""
    <div class={["mb-4 flex flex-col gap-3 xl:flex-row xl:items-center xl:justify-between", @class]}>
      <div class="min-w-0">
        <.trail crumbs={["Flows", "Dog License"]} last="Applicant / Owner Information" />
        <h2 class="mt-1 flex flex-wrap items-baseline gap-x-2 text-2xl font-semibold leading-tight">
          <span>Applicant / Owner Information</span>
          <span class="text-base font-normal text-zinc-400">in Dog License</span>
        </h2>
      </div>
      <.actions_slot actions={@actions} />
    </div>
    """
  end

  defp page_header(%{direction: :form_only} = assigns) do
    ~H"""
    <div class={["mb-4 flex flex-col gap-3 xl:flex-row xl:items-center xl:justify-between", @class]}>
      <div class="min-w-0">
        <.trail crumbs={["Flows", "Dog License"]} last={current(@forms).label} />
        <h2 class="mt-1 flex flex-wrap items-baseline gap-x-2 text-2xl font-semibold leading-tight">
          <span>{current(@forms).label}</span>
          <span class="text-base font-normal text-zinc-400">in Dog License</span>
        </h2>
      </div>
      <.actions_slot actions={@actions} />
    </div>
    """
  end

  defp page_header(%{direction: :step_of} = assigns) do
    ~H"""
    <div class={["mb-4 flex flex-col gap-3 xl:flex-row xl:items-center xl:justify-between", @class]}>
      <div class="min-w-0">
        <.trail crumbs={["Flows", "Dog License"]} last={current(@forms).label} />
        <h2 class="mt-1 flex flex-wrap items-baseline gap-x-2 text-2xl font-semibold leading-tight">
          <span>{current(@forms).label}</span>
          <span class="text-base font-normal text-zinc-400">in Dog License</span>
        </h2>
        <p class="mt-0.5 text-sm text-zinc-500">
          Step {current(@forms).n} of {length(@forms)} · {percent(@forms)}%
        </p>
      </div>
      <.actions_slot actions={@actions} />
    </div>
    """
  end

  # The form's name alone, no flow after it - for the directions where the
  # flow is named by the badge or the rail right beside it
  defp page_header(%{direction: :bare} = assigns) do
    ~H"""
    <div class={["mb-4 flex flex-col gap-3 xl:flex-row xl:items-center xl:justify-between", @class]}>
      <div class="min-w-0">
        <.trail crumbs={["Flows", "Dog License"]} last={current(@forms).label} />
        <h2 class="mt-1 text-2xl font-semibold leading-tight">{current(@forms).label}</h2>
      </div>
      <.actions_slot actions={@actions} />
    </div>
    """
  end

  attr :crumbs, :list, required: true
  attr :last, :string, required: true

  defp trail(assigns) do
    ~H"""
    <nav aria-label="Breadcrumb" class="flex flex-wrap items-center gap-x-1.5 text-xs text-zinc-500">
      <%= for crumb <- @crumbs do %>
        <span class="hover:underline">{crumb}</span>
        <span class="text-zinc-400">/</span>
      <% end %>
      <span class="text-zinc-700">{@last}</span>
    </nav>
    """
  end

  attr :actions, :list, required: true

  defp actions_slot(assigns) do
    ~H"""
    <div :if={@actions != []} class="flex flex-wrap items-center gap-2 xl:shrink-0 xl:flex-nowrap">
      {render_slot(@actions)}
    </div>
    """
  end

  # -- Flow badge directions -------------------------------------------------

  attr :direction, :atom, required: true
  attr :forms, :list, required: true

  defp badge_page(%{direction: :card} = assigns) do
    ~H"""
    <.page_header direction={:bare} forms={@forms} />
    <div class="mb-6 flex flex-wrap items-center gap-5 rounded-lg border border-zinc-300 px-5 py-4">
      <.ring percent={percent(@forms)} size={:lg} />
      <div class="min-w-0 flex-1">
        <p class="text-xs text-zinc-500">
          <span class="hover:underline">← Back to flow</span>
        </p>
        <p class="truncate text-lg font-semibold leading-tight">Dog License</p>
        <p class="text-sm text-zinc-500">
          Step {current(@forms).n} of {length(@forms)}
          <span :if={neighbour(@forms, 1)}>· next {neighbour(@forms, 1).label}</span>
        </p>
      </div>
    </div>
    <.mock_form />
    """
  end

  defp badge_page(%{direction: :strip} = assigns) do
    ~H"""
    <.flow_strip forms={@forms} bar={:plain} />
    <.page_header direction={:bare} forms={@forms} class="mt-4" />
    <.mock_form />
    """
  end

  defp badge_page(%{direction: :pill} = assigns) do
    ~H"""
    <.page_header direction={:bare} forms={@forms}>
      <:actions>
        <span class="flex items-center gap-3 rounded-full border border-zinc-300 py-1.5 pl-1.5 pr-4">
          <.ring percent={percent(@forms)} size={:sm} />
          <span class="leading-tight">
            <span class="block text-sm font-semibold">Dog License</span>
            <span class="block text-xs text-zinc-500">
              Step {current(@forms).n} of {length(@forms)} ·
              <span class="hover:underline">back to flow</span>
            </span>
          </span>
        </span>
      </:actions>
    </.page_header>
    <.mock_form />
    """
  end

  defp badge_page(%{direction: :panel} = assigns) do
    ~H"""
    <div class="mb-6 flex flex-col gap-4 xl:flex-row xl:items-center xl:justify-between">
      <div class="flex items-center gap-5">
        <span class="text-5xl font-semibold tabular-nums leading-none tracking-tight">
          {percent(@forms)}<span class="text-2xl text-zinc-400">%</span>
        </span>
        <div class="min-w-0">
          <.trail crumbs={["Flows"]} last="Dog License" />
          <p class="mt-1 text-2xl font-semibold leading-tight">Dog License</p>
          <p class="text-sm text-zinc-500">
            Step {current(@forms).n} of {length(@forms)}
            <span :if={neighbour(@forms, 1)}>· next {neighbour(@forms, 1).label}</span>
          </p>
        </div>
      </div>
      <span class="text-sm text-indigo-600 hover:underline">← Back to flow</span>
    </div>
    <div class="mb-3">
      <h3 class="text-lg font-bold">{current(@forms).label}</h3>
      <div class="text-gray-500">Step {current(@forms).n} of {length(@forms)}.</div>
    </div>
    <.mock_form />
    """
  end

  defp badge_page(%{direction: :segments} = assigns) do
    ~H"""
    <.flow_strip forms={@forms} bar={:segments} />
    <.page_header direction={:bare} forms={@forms} class="mt-4" />
    <.mock_form />
    """
  end

  # The thin line above the header: back link, the bar, the count
  attr :forms, :list, required: true
  attr :bar, :atom, required: true

  defp flow_strip(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-x-4 gap-y-2 border-b border-zinc-200 pb-3 text-sm">
      <span class="flex items-center gap-1.5 font-medium hover:underline">
        <span aria-hidden="true" class="text-zinc-400">←</span> Dog License
      </span>
      <div class="min-w-32 flex-1">
        <div :if={@bar == :plain} class="h-1 w-full overflow-hidden rounded-full bg-zinc-200">
          <div class="h-full rounded-full bg-primary" style={"width: #{percent(@forms)}%"} />
        </div>
        <div :if={@bar == :segments} class="flex gap-px" role="list">
          <div
            :for={form <- @forms}
            role="listitem"
            title={"#{form.n}. #{form.label}"}
            class={[
              "h-1.5 flex-1 first:rounded-l-full last:rounded-r-full",
              segment_class(@forms, form)
            ]}
          />
        </div>
      </div>
      <span class="tabular-nums text-zinc-500">
        Step {current(@forms).n} of {length(@forms)} ·
        <span class="font-semibold text-zinc-900">{percent(@forms)}%</span>
      </span>
    </div>
    """
  end

  # Behind the user, the step they are on, ahead of them - one hue, three
  # weights, since finished-versus-current is not the point
  defp segment_class(forms, form) do
    cond do
      form.n < current(forms).n -> "bg-primary/60"
      form.n == current(forms).n -> "bg-primary"
      true -> "bg-zinc-200"
    end
  end

  # A progress ring with the percentage in it. `pathLength` lets the dash
  # be the percentage itself, whatever the radius.
  attr :percent, :integer, required: true
  attr :size, :atom, required: true

  defp ring(assigns) do
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
          stroke-linecap="round"
          pathLength="100"
          stroke-dasharray={"#{@percent} 100"}
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

  # -- Side rail directions --------------------------------------------------

  attr :direction, :atom, required: true
  attr :forms, :list, required: true

  defp rail_page(%{direction: :column} = assigns) do
    ~H"""
    <div class="grid lg:grid-cols-3">
      <aside class="border-b border-zinc-200 bg-zinc-50/60 lg:col-span-1 lg:border-b-0 lg:border-r">
        <.rail_head forms={@forms} />
        <.rail_list forms={@forms} collapse={false} />
      </aside>
      <div class="px-6 py-5 lg:col-span-2">
        <.page_header direction={:bare} forms={@forms}>
          <:actions>
            <button type="button" class="btn btn-ghost">Save draft</button>
            <button type="submit" form="mock-form" class="btn btn-primary">Submit</button>
          </:actions>
        </.page_header>
        <.mock_form />
      </div>
    </div>
    """
  end

  defp rail_page(%{direction: :narrow} = assigns) do
    ~H"""
    <div class="grid lg:grid-cols-4">
      <aside class="border-b border-zinc-200 lg:col-span-1 lg:border-b-0 lg:border-r">
        <div class="flex items-center gap-3 border-b border-zinc-200 px-4 py-3">
          <.ring percent={percent(@forms)} size={:sm} />
          <div class="min-w-0 leading-tight">
            <p class="truncate text-sm font-semibold">Dog License</p>
            <p class="text-xs text-zinc-500">Step {current(@forms).n} of {length(@forms)}</p>
          </div>
        </div>
        <.rail_list forms={@forms} collapse={true} />
      </aside>
      <div class="px-6 py-5 lg:col-span-3">
        <.page_header direction={:bare} forms={@forms}>
          <:actions>
            <button type="button" class="btn btn-ghost">Save draft</button>
            <button type="submit" form="mock-form" class="btn btn-primary">Submit</button>
          </:actions>
        </.page_header>
        <.mock_form />
      </div>
    </div>
    """
  end

  defp rail_page(%{direction: :sticky_rail} = assigns) do
    ~H"""
    <div class="max-h-[30rem] overflow-y-auto">
      <div class="grid lg:grid-cols-3">
        <aside class="self-start border-b border-zinc-200 bg-zinc-50/60 lg:sticky lg:top-0 lg:col-span-1 lg:max-h-[30rem] lg:overflow-y-auto lg:border-b-0 lg:border-r">
          <.rail_head forms={@forms} />
          <.rail_list forms={@forms} collapse={false} />
        </aside>
        <div class="lg:col-span-2">
          <div class="sticky top-0 z-10 border-b border-zinc-200 bg-white/95 px-6 pt-4 backdrop-blur">
            <.page_header direction={:bare} forms={@forms}>
              <:actions>
                <.save_state direction={:dot_text} state={saved()} placement={:header} />
                <button type="button" class="btn btn-ghost">Save draft</button>
                <button type="submit" form="mock-form" class="btn btn-primary">Submit</button>
              </:actions>
            </.page_header>
          </div>
          <div class="px-6 py-5">
            <.mock_form long />
          </div>
        </div>
      </div>
    </div>
    """
  end

  # The top of a rail: the way back, the flow, how far along
  attr :forms, :list, required: true

  defp rail_head(assigns) do
    ~H"""
    <div class="border-b border-zinc-200 px-5 py-4">
      <p class="text-xs text-zinc-500 hover:underline">← Back to flow</p>
      <p class="mt-1 text-lg font-semibold leading-tight">Dog License</p>
      <div class="mt-2 flex items-center gap-3 text-sm text-zinc-500">
        <div class="h-1 flex-1 overflow-hidden rounded-full bg-zinc-200">
          <div class="h-full rounded-full bg-primary" style={"width: #{percent(@forms)}%"} />
        </div>
        <span class="tabular-nums">Step {current(@forms).n} of {length(@forms)} · {percent(@forms)}%</span>
      </div>
    </div>
    """
  end

  # The forms as rows, grouped under their subflow when there is more than
  # one. `collapse` folds every group but the current one.
  attr :forms, :list, required: true
  attr :collapse, :boolean, required: true

  defp rail_list(assigns) do
    assigns = assign(assigns, :groups, groups(assigns.forms))

    ~H"""
    <nav aria-label="Steps">
      <%= if length(@groups) == 1 do %>
        <ol class="py-2">
          <.rail_row :for={form <- @forms} form={form} />
        </ol>
      <% else %>
        <details
          :for={group <- @groups}
          class="group/g border-b border-zinc-200 last:border-b-0"
          open={not @collapse or Enum.any?(group, &(&1.status == :current))}
        >
          <summary class="flex cursor-pointer list-none items-center justify-between gap-2 px-5 py-2 text-xs font-semibold text-zinc-600 hover:bg-zinc-100 [&::-webkit-details-marker]:hidden">
            <span>{Map.get(hd(group), :group)}</span>
            <span class="flex items-center gap-2 font-normal text-zinc-400">
              {group_summary(@forms, group)}
              <span aria-hidden="true" class="transition-transform group-open/g:rotate-90">›</span>
            </span>
          </summary>
          <ol class="pb-2">
            <.rail_row :for={form <- group} form={form} />
          </ol>
        </details>
      <% end %>
    </nav>
    """
  end

  attr :form, :map, required: true

  defp rail_row(assigns) do
    ~H"""
    <li
      class={[
        "flex items-center gap-3 px-5 py-2 text-sm",
        @form.status == :current && "bg-zinc-200/60 font-semibold",
        @form.status == :pending && "text-zinc-400"
      ]}
      aria-current={@form.status == :current && "step"}
    >
      <span class={[
        "w-5 shrink-0 text-right font-mono text-xs tabular-nums",
        @form.status == :done && "text-primary",
        @form.status == :current && "text-zinc-900",
        @form.status == :pending && "text-zinc-400"
      ]}>
        {@form.n}
      </span>
      <span class="min-w-0 flex-1 truncate">{@form.label}</span>
    </li>
    """
  end

  # What a folded group says about itself: where it sits relative to the
  # user - behind them, or still ahead - and how many steps it holds
  defp group_summary(forms, group) do
    cond do
      Enum.any?(group, &(&1.status == :current)) -> "#{length(group)} steps"
      List.last(group).n < current(forms).n -> "behind you"
      true -> "#{length(group)} steps ahead"
    end
  end

  # -- Action directions -----------------------------------------------------

  attr :direction, :atom, required: true
  attr :forms, :list, required: true

  defp action_page(%{direction: :header_sticky} = assigns) do
    ~H"""
    <div class="max-h-[26rem] overflow-y-auto">
      <div class="sticky top-0 z-10 border-b border-zinc-200 bg-white/95 px-6 pt-4 backdrop-blur">
        <.page_header direction={:form_only} forms={@forms}>
          <:actions>
            <.save_state direction={:dot_text} state={saved()} placement={:header} />
            <button type="button" class="btn btn-ghost">Save draft</button>
            <button type="submit" form="mock-form" class="btn btn-primary">Submit</button>
          </:actions>
        </.page_header>
      </div>
      <div class="px-6 py-5">
        <.flow_strip forms={@forms} bar={:segments} />
        <div class="mt-5">
          <.mock_form long />
        </div>
      </div>
    </div>
    """
  end

  defp action_page(%{direction: :bar_sticky} = assigns) do
    ~H"""
    <div class="max-h-[26rem] overflow-y-auto">
      <div class="px-6 pt-5">
        <.page_header direction={:form_only} forms={@forms} class="mb-0" />
      </div>
      <div class="sticky top-0 z-10 mt-4 flex flex-wrap items-center justify-between gap-3 border-y border-zinc-200 bg-white/95 px-6 py-2 backdrop-blur">
        <span class="flex items-center gap-3 text-sm">
          <span class="font-semibold">{current(@forms).label}</span>
          <span class="text-zinc-400">·</span>
          <span class="text-zinc-500">Step {current(@forms).n} of {length(@forms)}</span>
        </span>
        <span class="flex items-center gap-2">
          <.save_state direction={:dot_text} state={saved()} placement={:header} />
          <button type="button" class="btn btn-ghost btn-sm">Save draft</button>
          <button type="submit" form="mock-form" class="btn btn-primary btn-sm">Submit</button>
        </span>
      </div>
      <div class="px-6 py-5">
        <.mock_form long />
      </div>
    </div>
    """
  end

  defp action_page(%{direction: :actions_float} = assigns) do
    ~H"""
    <div class="max-h-[26rem] overflow-y-auto px-6 pb-5">
      <div class="pointer-events-none sticky top-0 z-10 flex justify-end pt-3">
        <span class="pointer-events-auto flex items-center gap-2 rounded-full border border-zinc-200 bg-white/95 p-1 pl-4 shadow-md backdrop-blur">
          <.save_state direction={:dot_text} state={saved()} placement={:header} />
          <button type="button" class="btn btn-ghost btn-sm rounded-full">Save draft</button>
          <button type="submit" form="mock-form" class="btn btn-primary btn-sm rounded-full">
            Submit
          </button>
        </span>
      </div>
      <div class="-mt-9">
        <.page_header direction={:form_only} forms={@forms} class="xl:pr-96" />
      </div>
      <.flow_strip forms={@forms} bar={:segments} />
      <div class="mt-5">
        <.mock_form long />
      </div>
    </div>
    """
  end

  # -- Save state directions -------------------------------------------------

  # One rendering of a save state. `placement` is `:header` beside the
  # buttons - one line, right margin - or `:row` in the states grid.
  attr :direction, :atom, required: true
  attr :state, :map, required: true
  attr :placement, :atom, required: true

  defp save_state(%{direction: :dot_text} = assigns) do
    ~H"""
    <span class={["flex items-center gap-2 text-sm", tone(@state.id), @placement == :header && "mr-2"]}>
      <.state_dot state={@state.id} />
      <span>
        {@state.word}
        <span :if={@state.when} class="text-zinc-500">· {@state.when}</span>
        <span :if={@state.who} class="text-zinc-500">· {@state.who}</span>
      </span>
    </span>
    """
  end

  defp save_state(%{direction: :icon_text} = assigns) do
    ~H"""
    <span class={[
      "flex items-center gap-1.5 text-sm",
      tone(@state.id),
      @placement == :header && "mr-2"
    ]}>
      <.state_icon state={@state.id} />
      <span>
        {@state.word}
        <span :if={@state.when} class="text-zinc-500">{@state.when}</span>
        <span :if={@state.who} class="text-zinc-500">by {@state.who}</span>
      </span>
    </span>
    """
  end

  defp save_state(%{direction: :chip} = assigns) do
    ~H"""
    <span
      class={[
        "inline-flex items-center gap-2 rounded-full py-1 pl-1 pr-3 text-xs font-medium",
        chip_tone(@state.id),
        @placement == :header && "mr-2"
      ]}
      title={@state.who && "Saved by #{@state.who}"}
    >
      <span
        :if={@state.who}
        class="grid size-5 place-items-center rounded-full bg-white text-[9px] font-bold text-zinc-700 ring-1 ring-black/5"
      >
        {initials(@state.who)}
      </span>
      <span :if={!@state.who} class="pl-1"><.state_icon state={@state.id} /></span>
      <span>
        {@state.word}
        <span :if={@state.when} class="opacity-70">· {@state.when}</span>
      </span>
    </span>
    """
  end

  # Under the buttons: in the header this draws nothing beside them -
  # `save_under/1` draws the line - so the buttons stand alone on their row
  defp save_state(%{direction: :under, placement: :header} = assigns) do
    ~H"""
    <span class="hidden" />
    """
  end

  defp save_state(%{direction: :under} = assigns) do
    ~H"""
    <div class="flex flex-col items-end gap-1">
      <span class="flex gap-2">
        <span class="btn btn-ghost btn-xs">Save draft</span>
        <span class="btn btn-primary btn-xs">Submit</span>
      </span>
      <span class={["text-[11px]", tone(@state.id)]}>
        {@state.word}
        <span :if={@state.when} class="text-zinc-400">· {@state.when}</span>
        <span :if={@state.who} class="text-zinc-400">· {@state.who}</span>
      </span>
    </div>
    """
  end

  defp save_state(%{direction: :two_line} = assigns) do
    ~H"""
    <span class={["flex items-center gap-2 leading-tight", @placement == :header && "mr-2"]}>
      <.state_dot state={@state.id} />
      <span>
        <span class={["block text-sm font-semibold", tone(@state.id)]}>{@state.word}</span>
        <span :if={@state.when || @state.who} class="block text-xs text-zinc-500">
          {Enum.join(Enum.reject([@state.when, @state.who], &is_nil/1), " · ")}
        </span>
      </span>
    </span>
    """
  end

  # S2d in the header: the line under the buttons, right-aligned
  attr :state, :map, required: true

  defp save_under(assigns) do
    ~H"""
    <p class={["-mt-3 mb-4 text-right text-[11px]", tone(@state.id)]}>
      {@state.word} <span class="text-zinc-400">· {@state.when} · {@state.who}</span>
    </p>
    """
  end

  attr :state, :atom, required: true

  defp state_dot(%{state: :saving} = assigns) do
    ~H"""
    <span class="loading loading-spinner loading-xs text-zinc-400" />
    """
  end

  defp state_dot(assigns) do
    ~H"""
    <span class={["size-2 shrink-0 rounded-full", dot_tone(@state)]} />
    """
  end

  defp dot_tone(:saved), do: "bg-zinc-400"
  defp dot_tone(:unsaved), do: "bg-amber-500"
  defp dot_tone(:failed), do: "bg-error"

  attr :state, :atom, required: true

  defp state_icon(%{state: :saved} = assigns) do
    ~H"""
    <.icon name="hero-check" class="size-4 text-zinc-500" />
    """
  end

  defp state_icon(%{state: :unsaved} = assigns) do
    ~H"""
    <.icon name="hero-pencil" class="size-4 text-amber-600" />
    """
  end

  defp state_icon(%{state: :saving} = assigns) do
    ~H"""
    <span class="loading loading-spinner loading-xs text-zinc-400" />
    """
  end

  defp state_icon(%{state: :failed} = assigns) do
    ~H"""
    <.icon name="hero-exclamation-triangle" class="size-4 text-error" />
    """
  end

  defp tone(:saved), do: "text-zinc-600"
  defp tone(:unsaved), do: "text-amber-700"
  defp tone(:saving), do: "text-zinc-500"
  defp tone(:failed), do: "text-error"

  defp chip_tone(:saved), do: "bg-zinc-100 text-zinc-700"
  defp chip_tone(:unsaved), do: "bg-amber-100 text-amber-800"
  defp chip_tone(:saving), do: "bg-zinc-100 text-zinc-500"
  defp chip_tone(:failed), do: "bg-red-100 text-red-800"

  defp initials(user_id) do
    user_id
    |> String.split(~r/[_\-\s]+/)
    |> Enum.map(&String.first/1)
    |> Enum.take(2)
    |> Enum.join()
    |> String.upcase()
  end

  # -- The form under it all --------------------------------------------------

  # Owner Information's fields, drawn as DynamicForm draws them, inert.
  # `long` adds enough of them that a frame has to scroll.
  attr :long, :boolean, default: false

  defp mock_form(assigns) do
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

  defp field(assigns) do
    ~H"""
    <label class="block">
      <span class="text-sm font-medium">{@label}</span>
      <input type="text" class="input input-bordered mt-1 w-full" value={@value} readonly />
    </label>
    """
  end
end
