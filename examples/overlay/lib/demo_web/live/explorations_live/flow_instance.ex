defmodule DemoWeb.ExplorationsLive.FlowInstance do
  @moduledoc """
  The flow instance page - what a user sees at `/users/<flow instance id>`:
  every form in the flow and where it stands - drawn several ways, in the
  UX the form pages settled on (X3b on
  `DemoWeb.ExplorationsLive.FormInstanceContinued`): the T2 header, the F1
  card's ring and vocabulary, the N2 segmented control among the actions,
  soft status badges, the H1 timeline for history.

  Today the page is a table: the forms in flow order under their subflow's
  name, a badge each, Start / Continue / View / Reopen on the right, and a
  fact sheet under it. What this page iterates, in sections:

    * **S · the summary** - a progress summary like the form pages' card,
      for the whole flow and for each subflow. S1 is the smallest step from
      today.
    * **L · the list** - the rows themselves: the table as it is, a task
      list where the row is the link, a stepper, the next-up row raised.
    * **W · where the application stands** - the whole flow's status as a
      stage tracker, a your-part / their-part split, a banner that says
      what to do next.
    * **T · tabs and history** - Overview | History on the flow instance,
      and what the History view holds.
    * **X · combinations**, and at the end **what would need building**:
      the elements drawn here that no backend supports yet, as the form
      pages' exploration listed Save draft before it existed.

  Hardcoded: Dog License, the Applicant subflow of five forms and the
  Reviewer subflow of four, as the seeded flow has them, viewed as the dog
  owner. A scenario switch redraws every frame at four moments in the
  application's life. Nothing is wired up.

  Mounted on `live "/explorations/flow-instance", ExplorationsLive.FlowInstance`.
  """

  use DemoWeb, :live_view

  alias DemoWeb.ExplorationsLive.Shared

  # -- Data ------------------------------------------------------------------

  @scenarios [
    %{
      id: :started,
      label: "Just started",
      note: "Owner Information in progress, the rest ahead. The reviewer has nothing yet."
    },
    %{
      id: :waiting,
      label: "Your part done",
      note: "Every applicant form submitted; the reviewer has begun."
    },
    %{
      id: :reopened,
      label: "Reopened",
      note: "The reviewer sent Owner Information back with a note."
    },
    %{
      id: :decided,
      label: "Decided",
      note: "The decision is recorded; the flow instance is completed."
    }
  ]

  @applicant [
    "Owner Information",
    "Dog Information",
    "Health Information",
    "Household Information",
    "License Options"
  ]
  @reviewer ["Review Owner Info", "Review Dog Info", "Review Health Info", "License Decision"]

  # The forms of both subflows at each moment: a status each - the four
  # the library derives (`:completed`, `:in_progress`, `:available`,
  # `:pending`) plus `:reopened`, which today is `:in_progress` with a
  # `reopened` event behind it - and, where it has happened, when and by whom
  defp scenario_groups(:started) do
    [
      group("Applicant", :mine, @applicant, [
        {:in_progress, "3 minutes ago", "dog_owner"},
        :pending,
        :pending,
        :pending,
        :pending
      ]),
      group("Reviewer", :theirs, @reviewer, [:pending, :pending, :pending, :pending])
    ]
  end

  defp scenario_groups(:waiting) do
    [
      group("Applicant", :mine, @applicant, [
        {:completed, "3 days ago", "dog_owner"},
        {:completed, "3 days ago", "dog_owner"},
        {:completed, "2 days ago", "dog_owner"},
        {:completed, "2 days ago", "dog_owner"},
        {:completed, "2 days ago", "dog_owner"}
      ]),
      group("Reviewer", :theirs, @reviewer, [
        {:in_progress, "yesterday", "reviewer"},
        :pending,
        :pending,
        :pending
      ])
    ]
  end

  defp scenario_groups(:reopened) do
    [
      group("Applicant", :mine, @applicant, [
        {:reopened, "yesterday", "reviewer",
         "Phone number does not match the vaccination record."},
        {:completed, "3 days ago", "dog_owner"},
        {:completed, "2 days ago", "dog_owner"},
        {:completed, "2 days ago", "dog_owner"},
        {:completed, "2 days ago", "dog_owner"}
      ]),
      group("Reviewer", :theirs, @reviewer, [
        {:in_progress, "yesterday", "reviewer"},
        :pending,
        :pending,
        :pending
      ])
    ]
  end

  defp scenario_groups(:decided) do
    [
      group("Applicant", :mine, @applicant, [
        {:completed, "8 days ago", "dog_owner"},
        {:completed, "8 days ago", "dog_owner"},
        {:completed, "7 days ago", "dog_owner"},
        {:completed, "7 days ago", "dog_owner"},
        {:completed, "7 days ago", "dog_owner"}
      ]),
      group("Reviewer", :theirs, @reviewer, [
        {:completed, "5 days ago", "reviewer"},
        {:completed, "5 days ago", "reviewer"},
        {:completed, "4 days ago", "reviewer"},
        {:completed, "4 days ago", "reviewer"}
      ])
    ]
  end

  defp group(name, whose, labels, states) do
    forms =
      labels
      |> Enum.zip(states)
      |> Enum.with_index(1)
      |> Enum.map(fn {{label, state}, n} ->
        {status, when_, who, note} =
          case state do
            {s, w, u, note} -> {s, w, u, note}
            {s, w, u} -> {s, w, u, nil}
            s -> {s, nil, nil, nil}
          end

        %{n: n, label: label, group: name, status: status, when: when_, who: who, note: note}
      end)

    %{name: name, whose: whose, forms: forms}
  end

  # The flow instance's own facts at each moment
  defp flow(:decided),
    do: %{status: "Completed", started: "8 days ago", updated: "4 days ago", decision: "Approved"}

  defp flow(:started),
    do: %{
      status: "In progress",
      started: "3 minutes ago",
      updated: "3 minutes ago",
      decision: nil
    }

  defp flow(:waiting),
    do: %{status: "In progress", started: "3 days ago", updated: "yesterday", decision: nil}

  defp flow(:reopened),
    do: %{status: "In progress", started: "3 days ago", updated: "yesterday", decision: nil}

  # What the whole flow says of itself to this viewer, beyond In progress /
  # Completed - derived here from the forms; nothing stores it today
  defp standing(:started), do: {"Your turn", "badge-info"}
  defp standing(:waiting), do: {"With the reviewer", "badge-neutral"}
  defp standing(:reopened), do: {"Needs your attention", "badge-warning"}
  defp standing(:decided), do: {"Approved", "badge-success"}

  # Every form's events across the flow instance, merged, newest first -
  # the History view. Today each form has its own trail; nothing merges them.
  defp events(:started),
    do: [
      %{
        what: "Saved",
        form: "Owner Information",
        who: "dog_owner",
        when: "3 minutes ago",
        at: "2026-09-17 09:42 UTC"
      },
      %{
        what: "Started",
        form: "Owner Information",
        who: "dog_owner",
        when: "6 minutes ago",
        at: "2026-09-17 09:39 UTC"
      },
      %{
        what: "Started",
        form: nil,
        who: "dog_owner",
        when: "6 minutes ago",
        at: "2026-09-17 09:39 UTC"
      }
    ]

  defp events(:waiting),
    do: [
      %{
        what: "Started",
        form: "Review Owner Info",
        who: "reviewer",
        when: "yesterday",
        at: "2026-09-16 14:05 UTC"
      },
      %{
        what: "Submitted",
        form: "License Options",
        who: "dog_owner",
        when: "2 days ago",
        at: "2026-09-15 16:31 UTC"
      },
      %{
        what: "Submitted",
        form: "Household Information",
        who: "dog_owner",
        when: "2 days ago",
        at: "2026-09-15 16:20 UTC"
      },
      %{
        what: "Submitted",
        form: "Health Information",
        who: "dog_owner",
        when: "2 days ago",
        at: "2026-09-15 16:02 UTC"
      },
      %{
        what: "Submitted",
        form: "Dog Information",
        who: "dog_owner",
        when: "3 days ago",
        at: "2026-09-14 10:48 UTC"
      },
      %{
        what: "Submitted",
        form: "Owner Information",
        who: "dog_owner",
        when: "3 days ago",
        at: "2026-09-14 10:30 UTC"
      },
      %{
        what: "Started",
        form: nil,
        who: "dog_owner",
        when: "3 days ago",
        at: "2026-09-14 10:12 UTC"
      }
    ]

  defp events(:reopened),
    do: [
      %{
        what: "Reopened",
        form: "Owner Information",
        who: "reviewer",
        when: "yesterday",
        at: "2026-09-16 14:12 UTC",
        note: "Phone number does not match the vaccination record."
      }
      | events(:waiting)
    ]

  defp events(:decided),
    do: [
      %{
        what: "Submitted",
        form: "License Decision",
        who: "reviewer",
        when: "4 days ago",
        at: "2026-09-13 11:02 UTC"
      },
      %{
        what: "Submitted",
        form: "Review Health Info",
        who: "reviewer",
        when: "4 days ago",
        at: "2026-09-13 10:40 UTC"
      },
      %{
        what: "Submitted",
        form: "Review Dog Info",
        who: "reviewer",
        when: "5 days ago",
        at: "2026-09-12 15:20 UTC"
      },
      %{
        what: "Submitted",
        form: "Review Owner Info",
        who: "reviewer",
        when: "5 days ago",
        at: "2026-09-12 15:04 UTC"
      },
      %{
        what: "Submitted",
        form: "License Options",
        who: "dog_owner",
        when: "7 days ago",
        at: "2026-09-10 16:31 UTC"
      },
      %{
        what: "Started",
        form: nil,
        who: "dog_owner",
        when: "8 days ago",
        at: "2026-09-09 10:12 UTC"
      }
    ]

  # -- Directions ----------------------------------------------------------------

  @summaries [
    %{
      id: :card_counts,
      title: "S1 · Card above the table, counts in the subflow headings",
      note:
        "Closest to today. The F1 card - ring, flow name, \"2 of 9 forms done · next Dog Information\", Continue - above the table as it is; each subflow heading gains \"1 of 5 done\" at its right. Rows drop the \"Applicant /\" prefix the heading already says."
    },
    %{
      id: :rings,
      title: "S2 · Mini rings in the subflow headings, the overall in the header",
      note:
        "The whole flow's ring as an F3 rectangle at the header's right, where the form pages carry the flow badge; each subflow heading gets a small ring and its count, so the three rings read as one system."
    },
    %{
      id: :segments,
      title: "S3 · Segment bars under the headings",
      note:
        "Each subflow heading carries F1c's segment bar - one segment per form, done in the brand colour, the one in progress tinted, ahead grey - so the count is a shape and the position shows. The overall card stays above."
    },
    %{
      id: :cards,
      title: "S4 · A card per subflow",
      note:
        "No table. Each subflow is its own rounded card with a ring in its head and its forms as rows inside; the whole flow's summary is the header's rectangle. Reads as chapters."
    }
  ]

  @lists [
    %{
      id: :today,
      title: "L1 · Today's rows",
      note:
        "Name, badge, actions right: Start, Continue, View, Reopen as the buttons and links they are now. The baseline the others are measured against."
    },
    %{
      id: :tasklist,
      title: "L2 · Task list",
      note:
        "GOV.UK's pattern: the whole row is the link, the status a tag on the right, Completed as plain text so the eye goes to what needs doing, and a row that cannot start yet is grey and unlinked with a hint saying why. No buttons."
    },
    %{
      id: :stepper,
      title: "L3 · Stepper",
      note:
        "A vertical line down the left with a marker per form - a check, a filled dot, a hollow one - and the current form's row opened to show its last event and its Continue button. Says the order is the order."
    },
    %{
      id: :nextup,
      title: "L4 · Next up raised",
      note:
        "Today's rows with one difference: the single row that wants the user is tinted and carries the only primary button; done rows say when and by whom with a quiet View; rows ahead are grey text."
    },
    %{
      id: :table,
      title: "L5 · Columns",
      note:
        "A real table - Form, Status, Last activity, Action - with a header row. Scans best past a dozen forms, and the reviewer's listing will want the same columns."
    }
  ]

  @wholes [
    %{
      id: :stages,
      title: "W1 · Stage tracker",
      note:
        "Application → Review → Decision as three stages along the top, one per subflow and one for the outcome; the current one bold, the ones behind filled, with a line each: \"Submitted 3 days ago\", \"Usually within 5 business days\". The flow's shape, not its forms."
    },
    %{
      id: :split,
      title: "W2 · Your part, then what happens after",
      note:
        "Two blocks: Your part - the applicant's forms with their rows - and What happens after - the reviewer's subflow as one card saying \"Waiting on the reviewer\" or \"In review since yesterday\", its forms unnamed. Honest about whose turn it is."
    },
    %{
      id: :banner,
      title: "W3 · A banner that says what to do",
      note:
        "One sentence at the top in the scenario's colour with the one action: \"Next: Owner Information\" and Continue; \"Your part is done\"; \"Owner Information needs your attention\" with the reviewer's note and Open; \"Approved\" with Download license. Pick a scenario above to see each."
    }
  ]

  @tab_dirs [
    %{
      id: :overview,
      title: "T1 · Overview | History among the actions",
      note:
        "The N2 capsule at the header's right as the form pages have it, with Download all beside it. Overview is this page; History is the flow's whole trail."
    },
    %{
      id: :history,
      title: "T2 · The History view",
      note:
        "Every form's events merged newest first down the H1 timeline, each line naming its form: \"Submitted · Owner Information by dog_owner\". A reviewer's note quoted under the reopen."
    }
  ]

  @combos [
    %{
      id: :evolve,
      title: "X1 · S1 + S4 + L4 + T1 - picked, built 2026-09-17",
      note:
        "The smallest step from today that carries the whole idea: the standing badge after the title, tabs and Download all right, the F1 card with Continue, a card per subflow with its ring and count, the next-up row raised. Built as drawn on the real page, with S4's cards in place of S3's segment bars."
    },
    %{
      id: :tasklist,
      title: "X2 · W3 + W1 + L2 + T1",
      note:
        "The service pattern: the banner says what to do, the stage tracker says where the application is, the task list is the work, each row a link. Completed rows are quiet text."
    },
    %{
      id: :cards,
      title: "X3 · S2 + S4 + L3 + W2",
      note:
        "The rectangle in the header, the applicant's subflow as a card with stepper rows, and the reviewer's part as the What happens after card - the user never sees the reviewer's form names."
    }
  ]

  # What the frames above draw that nothing in the library supports yet,
  # each with what exists today and what it would take
  @needs [
    %{
      title: "A standing beyond In progress / Completed",
      today:
        "The flow instance row has `status`, in_progress or completed; the forms' statuses are derived per position.",
      needs:
        "A derived reading per viewer - Your turn, With the reviewer, Needs your attention, Approved - from the forms the viewer owns and the events on them. A function beside `page_state/1`, no column."
    },
    %{
      title: "Progress counts for the whole flow and per subflow",
      today:
        "`FlowProgress.forms/2` gives every form's status; the card on a form page counts one subflow.",
      needs:
        "The same arithmetic over all forms and over each group - done, in progress, total - in one place both pages call."
    },
    %{
      title: "Next up",
      today:
        "Each row asks its flow type `editable?/2`; the page draws Start or Continue per row.",
      needs:
        "One answer: the first form the viewer can work on now, for the card's Continue and the banner. The in-order type knows it; the any-order type has several."
    },
    %{
      title: "Needs your attention, and the reviewer's note",
      today:
        "Reopen writes a `reopened` event with no note; the applicant sees In progress again.",
      needs:
        "A note in the reopen event's snapshot (form pages plan §7), a reason field on the Reopen control, and the applicant's row and banner reading `reopened` as attention rather than as work resumed."
    },
    %{
      title: "Cannot start yet, with a reason",
      today: "`editable?/2` says no; the row shows Pending with no button.",
      needs:
        "A reason from the flow type - \"after Owner Information\", \"once the reviewer decides\" - so the row can say why. A second callback, or `editable?/2` returning `{false, reason}`."
    },
    %{
      title: "Stages and the outcome",
      today:
        "Subflows are the stages by construction; the decision is an answer inside the reviewer's License Decision form.",
      needs:
        "Reading a form's answer as the flow's outcome - a `related_form` walk the Renewal type already makes, or a flow type callback naming the decision form and field. Then the Approved badge, the Decision stage, and Download license have something to show."
    },
    %{
      title: "Flow-level history",
      today:
        "Each form has its own event trail and History page; the flow instance has `inserted_at` and `updated_at`.",
      needs:
        "A query merging every form's events for one flow instance newest first, a `started` event for the instance itself, and a `/:id/history` page. Then the Overview | History tabs mean something."
    },
    %{
      title: "Download all",
      today:
        "Each form's page offers Download / Print of its own answers when `download_path` is set.",
      needs:
        "One PDF of every completed form in flow order. The renderer exists per form; this is a loop and a cover page."
    },
    %{
      title: "Last activity per row",
      today:
        "The newest event's user and time are read on the form pages (`Status.badge/1`).",
      needs:
        "The same on the listing rows without an N+1: one query for the newest event per position."
    },
    %{
      title: "Saved drafts and last saved",
      today:
        "Answers are written on submit only; Save draft is drawn disabled (form pages plan §7).",
      needs:
        "The draft write and its `saved` event. Until then \"Saved 3 minutes ago\" on a row cannot be true."
    },
    %{
      title: "Time estimates and hints",
      today: "A form has a description on its template; nothing says how long it takes.",
      needs:
        "Hint text under a row is the form's description, available now. \"About 5 minutes\" and \"Usually within 5 business days\" need a property on the node or the flow type - or stay off the page."
    },
    %{
      title: "Withdraw, and the reviewer's listing",
      today:
        "Nothing removes an application the applicant started; the reviewer's listing shows every instance with nothing to distinguish them.",
      needs:
        "A withdraw action with an event, if the host wants it. And the per-viewer standing above is the \"Your part\" column the reviewer's listing needs (instances refresh plan §2.6)."
    }
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Flow instance page")
     |> assign(:scenario, :started)
     |> assign(:scenarios, @scenarios)
     |> assign(:summaries, @summaries)
     |> assign(:lists, @lists)
     |> assign(:wholes, @wholes)
     |> assign(:tab_dirs, @tab_dirs)
     |> assign(:combos, @combos)
     |> assign(:needs, @needs)
     |> assign_scenario()}
  end

  @impl true
  def handle_event("scenario", %{"scenario" => id}, socket) do
    scenario = Enum.find(@scenarios, &(Atom.to_string(&1.id) == id))
    {:noreply, socket |> assign(:scenario, (scenario || hd(@scenarios)).id) |> assign_scenario()}
  end

  defp assign_scenario(socket) do
    scenario = socket.assigns.scenario

    assign(socket,
      groups: scenario_groups(scenario),
      flow: flow(scenario),
      events: events(scenario),
      standing: standing(scenario)
    )
  end

  # -- Arithmetic --------------------------------------------------------------

  defp all_forms(groups), do: Enum.flat_map(groups, & &1.forms)
  defp done(forms), do: Enum.count(forms, &(&1.status == :completed))
  defp active(forms), do: Enum.count(forms, &(&1.status in [:in_progress, :reopened]))
  defp percent(forms), do: round(done(forms) / length(forms) * 100)

  # The form that wants the viewer now: one reopened, else one in progress,
  # else one available - among the viewer's own
  defp next_up(groups) do
    mine = groups |> Enum.filter(&(&1.whose == :mine)) |> all_forms()

    Enum.find(mine, &(&1.status == :reopened)) ||
      Enum.find(mine, &(&1.status == :in_progress)) ||
      Enum.find(mine, &(&1.status == :available))
  end

  defp mine(groups), do: Enum.filter(groups, &(&1.whose == :mine))
  defp theirs(groups), do: Enum.filter(groups, &(&1.whose == :theirs))

  defp badge_class(:completed), do: "badge-success"
  defp badge_class(:in_progress), do: "badge-warning"
  defp badge_class(:reopened), do: "badge-warning"
  defp badge_class(:available), do: "badge-info"
  defp badge_class(_pending), do: "badge-neutral"

  defp badge_text(:completed), do: "Done"
  defp badge_text(:in_progress), do: "In progress"
  defp badge_text(:reopened), do: "Needs attention"
  defp badge_text(:available), do: "Available"
  defp badge_text(_pending), do: "Pending"

  # -- Render --------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="space-y-6">
        <header class="space-y-2">
          <Shared.back_link />
          <h1 class="text-2xl font-semibold">Flow instance page</h1>
          <p class="text-base-content/70">
            The page a user lands on for one application - every form and where
            it stands - drawn several ways in the UX
            <.link
              navigate="/explorations/form-instance-continued"
              class="text-indigo-600 hover:underline"
            >X3b</.link>
            set for the form pages: the T2 header, the F1 ring and its
            words, the N2 capsule among the actions, soft badges, the H1 timeline.
            Dog License, viewed as the dog owner, with the Reviewer subflow drawn
            as an admin sees it where a direction shows every form. Hardcoded;
            nothing is wired up.
          </p>
          <fieldset class="flex flex-wrap items-center gap-x-5 gap-y-2 pt-1 text-sm text-gray-700">
            <legend class="sr-only">Scenario</legend>
            <label :for={s <- @scenarios} class="inline-flex items-center gap-2" title={s.note}>
              <input
                type="radio"
                name="scenario"
                value={s.id}
                class="radio radio-sm radio-primary"
                checked={@scenario == s.id}
                phx-click="scenario"
                phx-value-scenario={s.id}
              />
              {s.label}
            </label>
            <span class="text-gray-500">
              {Enum.find(@scenarios, &(&1.id == @scenario)).note}
            </span>
          </fieldset>
        </header>

        <.section
          id="summaries"
          title="S · the summary"
          intro="A progress summary for the whole flow and for each subflow, in the card's vocabulary. Under the T2 header, over today's rows."
        >
          <div :for={d <- @summaries} class="space-y-3">
            <.direction_title d={d} />
            <.frame label={frame_label(@groups)}>
              <.summary variant={d.id} groups={@groups} flow={@flow} standing={@standing} />
            </.frame>
          </div>
        </.section>

        <.section
          id="lists"
          title="L · the list"
          intro="The rows themselves, five ways, under S1's headings with counts so the list is the only thing that changes."
        >
          <div :for={d <- @lists} class="space-y-3">
            <.direction_title d={d} />
            <.frame label={frame_label(@groups)}>
              <.flow_header standing={@standing} />
              <.groups groups={@groups} heading={:counts} rows={d.id} />
            </.frame>
          </div>
        </.section>

        <.section
          id="wholes"
          title="W · where the application stands"
          intro="The whole flow's state as the user thinks of it - whose turn, what stage, what next - rather than as nine statuses."
        >
          <div :for={d <- @wholes} class="space-y-3">
            <.direction_title d={d} />
            <.frame label={frame_label(@groups)}>
              <.whole
                variant={d.id}
                groups={@groups}
                flow={@flow}
                standing={@standing}
                scenario={@scenario}
              />
            </.frame>
          </div>
        </.section>

        <.section
          id="tabs"
          title="T · tabs and history"
          intro="Overview | History as the form pages' Edit | View | History: two paths of one flow instance, in the N2 capsule."
        >
          <div :for={d <- @tab_dirs} class="space-y-3">
            <.direction_title d={d} />
            <.frame label={frame_label(@groups)}>
              <.flow_header standing={@standing}>
                <:actions>
                  <.flow_tabs active={d.id} class="mr-2" />
                  <button type="button" class="btn btn-ghost">Download all</button>
                </:actions>
              </.flow_header>
              <%= if d.id == :history do %>
                <.history events={@events} />
              <% else %>
                <.overall_card groups={@groups} />
                <.groups groups={@groups} heading={:counts} rows={:today} />
              <% end %>
            </.frame>
          </div>
        </.section>

        <.section
          id="combos"
          title="X · combinations"
          intro="The pieces put together on one page each. The scenario switch above redraws them."
        >
          <div :for={d <- @combos} class="space-y-3">
            <.direction_title d={d} />
            <.frame label={frame_label(@groups)}>
              <.combo
                variant={d.id}
                groups={@groups}
                flow={@flow}
                standing={@standing}
                scenario={@scenario}
              />
            </.frame>
          </div>
        </.section>

        <.section
          id="needs"
          title="What would need building"
          intro="Everything drawn above that the library has no backend for, with what exists today and what it would take - as the form pages' exploration listed Save draft before it existed. None of it blocks the S1 or L directions; W, T and the badges lean on it."
        >
          <dl class="divide-y divide-gray-200 border-y border-gray-200">
            <div :for={n <- @needs} class="grid gap-2 py-4 lg:grid-cols-3 lg:gap-6">
              <dt class="font-semibold text-gray-900">{n.title}</dt>
              <dd class="text-sm text-gray-600 lg:col-span-2">
                <p><span class="font-medium text-gray-700">Today:</span> {n.today}</p>
                <p class="mt-1"><span class="font-medium text-gray-700">Needs:</span> {n.needs}</p>
              </dd>
            </div>
          </dl>
          <div class="space-y-2 text-sm text-gray-600">
            <p class="font-semibold text-gray-900">Where the ideas came from</p>
            <ul class="list-disc space-y-1 pl-5">
              <li>
                GOV.UK's
                <a
                  href="https://design-system.service.gov.uk/components/task-list/"
                  class="text-indigo-600 hover:underline"
                >task list</a>
                and
                <a
                  href="https://design-system.service.gov.uk/patterns/complete-multiple-tasks/"
                  class="text-indigo-600 hover:underline"
                >complete multiple tasks</a>
                pattern: the row is the link; Completed is plain text so attention goes to what is left; Cannot start yet is grey, unlinked, with a hint saying why; start with the fewest statuses; group tasks under short headings; a final check-your-answers step before sending.
              </li>
              <li>
                Step indicators (USWDS, Material) for W1: stages, not steps, when there are more than about seven forms; the current stage named, the count under it.
              </li>
              <li>
                Case trackers (USCIS, DMV, insurance claims): one sentence of status, the date it changed, and what happens next with a typical duration - the W3 banner and W1's lines.
              </li>
              <li>
                The form pages' own exploration: whatever the flow page adds, its ring, words, badges, and tabs must be the same components.
              </li>
            </ul>
          </div>
        </.section>
      </div>
    </Layouts.app>
    """
  end

  defp frame_label(groups) do
    forms = all_forms(groups)
    "#{length(forms)} forms · #{done(forms)} done · #{percent(forms)}%"
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

  # -- The header (T2, for the flow instance) ------------------------------------

  attr :standing, :any, default: nil, doc: "{text, badge class} after the title, or nil"
  slot :actions

  defp flow_header(assigns) do
    ~H"""
    <div class="mb-4 flex flex-col gap-3 xl:flex-row xl:items-center xl:justify-between">
      <div class="min-w-0">
        <nav
          aria-label="Breadcrumb"
          class="flex flex-wrap items-center gap-x-1.5 text-xs text-zinc-500"
        >
          <span class="hover:underline">Flows</span>
          <span class="text-zinc-400">/</span>
          <span class="text-zinc-700">Dog License</span>
        </nav>
        <h2 class="mt-1 flex flex-wrap items-center gap-x-2 text-2xl font-semibold leading-tight">
          <span>Dog License</span>
          <.standing_badge :if={@standing} standing={@standing} />
        </h2>
      </div>
      <div :if={@actions != []} class="flex flex-wrap items-center gap-2 xl:shrink-0 xl:flex-nowrap">
        {render_slot(@actions)}
      </div>
    </div>
    """
  end

  attr :standing, :any, required: true
  attr :class, :any, default: nil

  defp standing_badge(assigns) do
    {text, class} = assigns.standing
    assigns = assign(assigns, text: text, kind: class)

    ~H"""
    <span class={["badge badge-soft", @kind, @class]}>{@text}</span>
    """
  end

  attr :active, :atom, required: true
  attr :class, :any, default: nil

  defp flow_tabs(assigns) do
    ~H"""
    <nav class={["inline-flex rounded-lg bg-zinc-100 p-0.5 text-sm", @class]} aria-label="Views">
      <span
        :for={{key, label} <- [overview: "Overview", history: "History"]}
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
    """
  end

  # -- Rings and bars -------------------------------------------------------------

  # The two-tone ring of the form pages, counting forms done rather than
  # the step the user is on: done in the brand colour, in progress tinted,
  # ahead grey, the percentage done inside
  attr :forms, :list, required: true
  attr :size, :atom, default: :lg

  defp ring(assigns) do
    total = length(assigns.forms)
    behind = round(done(assigns.forms) / total * 100)
    each = round(active(assigns.forms) / total * 100)
    assigns = assign(assigns, behind: behind, each: each, percent: behind)

    ~H"""
    <span class={[
      "relative grid shrink-0 place-items-center",
      case @size do
        :lg -> "size-16"
        :sm -> "size-9"
        :xs -> "size-7"
      end
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
          :if={@each > 0}
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
        "relative tabular-nums font-semibold",
        case @size do
          :lg -> "text-base"
          :sm -> "text-[10px]"
          :xs -> "text-[9px]"
        end
      ]}>
        {@percent}<span :if={@size == :lg} class="text-xs text-zinc-400">%</span>
      </span>
    </span>
    """
  end

  attr :forms, :list, required: true
  attr :class, :any, default: nil

  defp segments(assigns) do
    ~H"""
    <div class={["flex gap-px", @class]} role="list">
      <div
        :for={form <- @forms}
        role="listitem"
        title={"#{form.n}. #{form.label} - #{badge_text(form.status)}"}
        class={[
          "h-1.5 flex-1 first:rounded-l-full last:rounded-r-full",
          case form.status do
            :completed -> "bg-primary"
            s when s in [:in_progress, :reopened] -> "bg-primary/40"
            _ahead -> "bg-zinc-200"
          end
        ]}
      />
    </div>
    """
  end

  # -- S · summaries ---------------------------------------------------------------

  attr :variant, :atom, required: true
  attr :groups, :list, required: true
  attr :flow, :map, required: true
  attr :standing, :any, required: true

  defp summary(%{variant: :card_counts} = assigns) do
    ~H"""
    <.flow_header standing={@standing} />
    <.overall_card groups={@groups} />
    <.groups groups={@groups} heading={:counts} rows={:today} />
    """
  end

  defp summary(%{variant: :rings} = assigns) do
    ~H"""
    <.flow_header standing={@standing}>
      <:actions><.overall_rect groups={@groups} /></:actions>
    </.flow_header>
    <.groups groups={@groups} heading={:rings} rows={:today} />
    """
  end

  defp summary(%{variant: :segments} = assigns) do
    ~H"""
    <.flow_header standing={@standing} />
    <.overall_card groups={@groups} />
    <.groups groups={@groups} heading={:segments} rows={:today} />
    """
  end

  defp summary(%{variant: :cards} = assigns) do
    ~H"""
    <.flow_header standing={@standing}>
      <:actions><.overall_rect groups={@groups} /></:actions>
    </.flow_header>
    <div class="space-y-4">
      <.subflow_card :for={group <- @groups} group={group} rows={:today} />
    </div>
    """
  end

  # The F1 card for the whole flow: the ring of forms done, the flow's name,
  # the count and what is next, and the one Continue
  attr :groups, :list, required: true
  attr :class, :any, default: nil

  defp overall_card(assigns) do
    forms = all_forms(assigns.groups)
    assigns = assign(assigns, forms: forms, next: next_up(assigns.groups))

    ~H"""
    <div class={[
      "mb-6 flex flex-wrap items-center gap-5 rounded-2xl border border-zinc-300 px-5 py-4",
      @class
    ]}>
      <.ring forms={@forms} />
      <div class="min-w-0 flex-1">
        <p class="truncate text-lg font-semibold leading-tight">Dog License</p>
        <p class="text-sm text-zinc-500">
          {done(@forms)} of {length(@forms)} forms done <span :if={@next}>· next {@next.label}</span>
          <span :if={!@next && done(@forms) < length(@forms)}>· nothing for you right now</span>
          <span :if={done(@forms) == length(@forms)}>· all done</span>
        </p>
      </div>
      <button :if={@next} type="button" class="btn btn-primary">
        {if @next.status == :available, do: "Start", else: "Continue"}
      </button>
    </div>
    """
  end

  # The F3 rectangle for the header's right: small ring, name, count
  attr :groups, :list, required: true

  defp overall_rect(assigns) do
    assigns = assign(assigns, :forms, all_forms(assigns.groups))

    ~H"""
    <span class="flex items-center gap-3 rounded-xl border border-zinc-300 bg-white py-2.5 pl-2.5 pr-5">
      <.ring forms={@forms} size={:sm} />
      <span class="leading-tight">
        <span class="block text-sm font-semibold">{done(@forms)} of {length(@forms)} forms done</span>
        <span class="block text-xs text-zinc-500">
          {Enum.map_join(@groups, " · ", &"#{&1.name} #{done(&1.forms)}/#{length(&1.forms)}")}
        </span>
      </span>
    </span>
    """
  end

  # Today's bordered box: a heading per subflow, the rows under it
  attr :groups, :list, required: true
  attr :heading, :atom, required: true, doc: ":plain, :counts, :rings, :segments"
  attr :rows, :atom, required: true

  defp groups(assigns) do
    ~H"""
    <div class="rounded-lg border border-zinc-300">
      <%= for {group, index} <- Enum.with_index(@groups) do %>
        <.group_heading
          group={group}
          variant={@heading}
          class={[index == 0 && "rounded-t-lg", index > 0 && "border-t border-zinc-300"]}
        />
        <.rows variant={@rows} group={group} />
      <% end %>
    </div>
    """
  end

  attr :group, :map, required: true
  attr :variant, :atom, required: true
  attr :class, :any, default: nil

  defp group_heading(%{variant: :plain} = assigns) do
    ~H"""
    <div class={["bg-zinc-50 px-6 py-2 text-sm font-semibold text-zinc-700", @class]}>
      {@group.name}
    </div>
    """
  end

  defp group_heading(%{variant: :counts} = assigns) do
    ~H"""
    <div class={["flex items-center justify-between bg-zinc-50 px-6 py-2 text-sm", @class]}>
      <span class="font-semibold text-zinc-700">{@group.name}</span>
      <span class="text-zinc-500 tabular-nums">{done(@group.forms)} of {length(@group.forms)} done</span>
    </div>
    """
  end

  defp group_heading(%{variant: :rings} = assigns) do
    ~H"""
    <div class={["flex items-center gap-3 bg-zinc-50 px-6 py-2 text-sm", @class]}>
      <.ring forms={@group.forms} size={:xs} />
      <span class="font-semibold text-zinc-700">{@group.name}</span>
      <span class="ml-auto text-zinc-500 tabular-nums">{done(@group.forms)} of {length(@group.forms)} done</span>
    </div>
    """
  end

  defp group_heading(%{variant: :segments} = assigns) do
    ~H"""
    <div class={["bg-zinc-50 px-6 pt-2 pb-3 text-sm", @class]}>
      <div class="flex items-center justify-between">
        <span class="font-semibold text-zinc-700">{@group.name}</span>
        <span class="text-zinc-500 tabular-nums">{done(@group.forms)} of {length(@group.forms)} done</span>
      </div>
      <.segments forms={@group.forms} class="mt-1.5" />
    </div>
    """
  end

  # S4: a subflow as its own card, the ring in its head
  attr :group, :map, required: true
  attr :rows, :atom, required: true

  defp subflow_card(assigns) do
    ~H"""
    <div class="rounded-2xl border border-zinc-300">
      <div class="flex items-center gap-4 px-5 py-4">
        <.ring forms={@group.forms} size={:sm} />
        <div class="min-w-0 flex-1 leading-tight">
          <p class="font-semibold">{@group.name}</p>
          <p class="text-xs text-zinc-500">
            {done(@group.forms)} of {length(@group.forms)} done
            <span :if={@group.whose == :theirs}>· the reviewer's</span>
          </p>
        </div>
      </div>
      <div class="border-t border-zinc-200">
        <.rows variant={@rows} group={@group} />
      </div>
    </div>
    """
  end

  # -- L · rows ------------------------------------------------------------------

  attr :variant, :atom, required: true
  attr :group, :map, required: true

  defp rows(%{variant: :today} = assigns) do
    ~H"""
    <div class="divide-y divide-zinc-200">
      <div :for={form <- @group.forms} class="flex flex-wrap items-center gap-3 px-6 py-4">
        <span class="font-medium">{form.label}</span>
        <span class={["badge badge-soft", badge_class(form.status)]}>{badge_text(form.status)}</span>
        <span class="ml-auto flex items-center gap-3">
          <.row_actions form={form} whose={@group.whose} />
        </span>
      </div>
    </div>
    """
  end

  defp rows(%{variant: :tasklist} = assigns) do
    ~H"""
    <ul class="divide-y divide-zinc-200">
      <li
        :for={form <- @group.forms}
        class={[
          "flex items-center justify-between gap-4 px-6 py-3",
          form.status in [:pending] && "text-zinc-400",
          form.status not in [:pending] && "hover:bg-zinc-50"
        ]}
      >
        <span class="min-w-0">
          <span class={[
            "block",
            form.status not in [:pending] && "font-medium text-indigo-700 hover:underline"
          ]}>
            {form.label}
          </span>
          <span :if={form.status == :pending} class="block text-xs">
            {cannot_start_hint(form, @group)}
          </span>
          <span :if={form.note} class="block text-xs text-zinc-600">“{form.note}” - reviewer</span>
        </span>
        <span :if={form.status == :completed} class="text-sm text-zinc-700">Completed</span>
        <span :if={form.status == :pending} class="text-sm">Cannot start yet</span>
        <span
          :if={form.status not in [:completed, :pending]}
          class={["badge badge-soft", badge_class(form.status)]}
        >
          {task_status(form.status)}
        </span>
      </li>
    </ul>
    """
  end

  defp rows(%{variant: :stepper} = assigns) do
    ~H"""
    <ol class="px-6 py-4">
      <li
        :for={{form, index} <- Enum.with_index(@group.forms)}
        class="relative flex gap-4 pb-5 last:pb-0"
      >
        <span
          :if={index < length(@group.forms) - 1}
          class="absolute left-[11px] top-6 bottom-0 w-px bg-zinc-200"
          aria-hidden="true"
        />
        <.marker status={form.status} />
        <div class="min-w-0 flex-1">
          <div class="flex flex-wrap items-center gap-3">
            <span class={[
              form.status in [:in_progress, :reopened] && "font-semibold",
              form.status == :pending && "text-zinc-400"
            ]}>
              {form.label}
            </span>
            <span :if={form.status == :completed} class="text-xs text-zinc-500">
              Submitted {form.when} by <code>{form.who}</code>
            </span>
            <span
              :if={form.status == :reopened}
              class={["badge badge-soft badge-xs", badge_class(form.status)]}
            >
              Needs attention
            </span>
          </div>
          <div
            :if={form.status in [:in_progress, :reopened, :available] && @group.whose == :mine}
            class="mt-2 flex flex-wrap items-center gap-3"
          >
            <p :if={form.note} class="text-sm text-zinc-600">“{form.note}” - reviewer, {form.when}</p>
            <p :if={!form.note && form.when} class="text-sm text-zinc-500">
              Last saved {form.when} by <code>{form.who}</code>
            </p>
            <button type="button" class="btn btn-primary btn-sm">{if form.status == :available,
              do: "Start",
              else: "Continue"}</button>
          </div>
          <p
            :if={form.status in [:in_progress, :reopened] && @group.whose == :theirs}
            class="mt-1 text-sm text-zinc-500"
          >
            In review since {form.when}
          </p>
        </div>
      </li>
    </ol>
    """
  end

  defp rows(%{variant: :nextup} = assigns) do
    assigns = assign(assigns, :next, next_up([%{assigns.group | whose: :mine}]))

    ~H"""
    <div class="divide-y divide-zinc-200">
      <div
        :for={form <- @group.forms}
        class={[
          "flex flex-wrap items-center gap-3 px-6 py-4",
          @group.whose == :mine && form == @next && "bg-primary/5",
          form.status == :pending && "text-zinc-400"
        ]}
      >
        <span class={[
          @group.whose == :mine && form == @next && "font-semibold",
          form.status != :pending && "font-medium"
        ]}>
          {form.label}
        </span>
        <span :if={form.status == :reopened} class={["badge badge-soft", badge_class(form.status)]}>Needs attention</span>
        <span :if={form.status == :completed} class="text-sm text-zinc-500">
          Submitted {form.when} by <code class="text-xs">{form.who}</code>
        </span>
        <span
          :if={form.status == :in_progress && @group.whose == :theirs}
          class="text-sm text-zinc-500"
        >
          In review since {form.when}
        </span>
        <span class="ml-auto flex items-center gap-3">
          <button :if={@group.whose == :mine && form == @next} type="button" class="btn btn-primary">
            {if form.status == :available, do: "Start", else: "Continue"}
          </button>
          <span
            :if={form.status == :completed && @group.whose == :mine}
            class="text-sm text-indigo-600 hover:underline"
          >View</span>
          <span :if={form.status == :pending} class="text-xs">Not yet</span>
        </span>
      </div>
    </div>
    """
  end

  defp rows(%{variant: :table} = assigns) do
    ~H"""
    <table class="w-full text-sm">
      <thead class="text-left text-xs font-medium text-zinc-500">
        <tr class="border-b border-zinc-200">
          <th class="px-6 py-2">Form</th>
          <th class="px-3 py-2">Status</th>
          <th class="px-3 py-2">Last activity</th>
          <th class="px-6 py-2 text-right">Action</th>
        </tr>
      </thead>
      <tbody class="divide-y divide-zinc-200">
        <tr :for={form <- @group.forms}>
          <td class={["px-6 py-3 font-medium", form.status == :pending && "text-zinc-400"]}>
            {form.label}
          </td>
          <td class="px-3 py-3">
            <span class={["badge badge-soft badge-sm", badge_class(form.status)]}>{badge_text(
              form.status
            )}</span>
          </td>
          <td class="px-3 py-3 text-zinc-500">
            <span :if={form.when}>{activity_word(form.status)} {form.when} ·
            <code class="text-xs">{form.who}</code></span>
            <span :if={!form.when}>-</span>
          </td>
          <td class="px-6 py-3">
            <span class="flex items-center justify-end gap-3"><.row_actions
              form={form}
              whose={@group.whose}
              small
            /></span>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  attr :form, :map, required: true
  attr :whose, :atom, required: true
  attr :small, :boolean, default: false

  # Today's buttons and links, per row: the viewer's own forms offer work,
  # the reviewer's offer nothing to the applicant but View once done
  defp row_actions(assigns) do
    ~H"""
    <button
      :if={@whose == :mine && @form.status == :available}
      type="button"
      class={["btn btn-primary", @small && "btn-sm"]}
    >
      Start
    </button>
    <button
      :if={@whose == :mine && @form.status in [:in_progress, :reopened]}
      type="button"
      class={["btn", @small && "btn-sm"]}
    >
      Continue
    </button>
    <span :if={@form.status == :completed} class="text-sm text-indigo-600 hover:underline">View</span>
    <span
      :if={@whose == :mine && @form.status == :completed}
      class="text-sm text-indigo-600 hover:underline"
    >
      Reopen
    </span>
    """
  end

  attr :status, :atom, required: true

  defp marker(assigns) do
    ~H"""
    <span class={[
      "relative z-10 mt-0.5 grid size-6 shrink-0 place-items-center rounded-full border-2 text-xs",
      case @status do
        :completed -> "border-primary bg-primary text-white"
        :in_progress -> "border-primary bg-primary/20 text-primary"
        :reopened -> "border-warning bg-warning/20 text-warning"
        :available -> "border-primary bg-white text-primary"
        _pending -> "border-zinc-300 bg-white text-zinc-300"
      end
    ]}>
      <span :if={@status == :completed}>✓</span>
      <span :if={@status != :completed} class="size-2 rounded-full bg-current" />
    </span>
    """
  end

  defp task_status(:in_progress), do: "In progress"
  defp task_status(:reopened), do: "Needs attention"
  defp task_status(:available), do: "Not yet started"

  # L2's hint under a row that cannot start: why - from the flow type,
  # which today only says no. Hardcoded here as the in-order wizard would
  defp cannot_start_hint(form, %{whose: :mine} = group) do
    before = Enum.find(group.forms, &(&1.n == form.n - 1))
    if before, do: "After #{before.label}", else: "Not yet"
  end

  defp cannot_start_hint(_form, %{whose: :theirs}), do: "Once your part is submitted"

  defp activity_word(:completed), do: "Submitted"
  defp activity_word(:reopened), do: "Reopened"
  defp activity_word(_status), do: "Saved"

  # -- W · where the application stands ----------------------------------------------

  attr :variant, :atom, required: true
  attr :groups, :list, required: true
  attr :flow, :map, required: true
  attr :standing, :any, required: true
  attr :scenario, :atom, required: true

  defp whole(%{variant: :stages} = assigns) do
    ~H"""
    <.flow_header standing={@standing} />
    <.stage_tracker groups={@groups} flow={@flow} class="mb-6" />
    <.groups groups={@groups} heading={:counts} rows={:today} />
    """
  end

  defp whole(%{variant: :split} = assigns) do
    ~H"""
    <.flow_header standing={@standing} />
    <.split groups={@groups} flow={@flow} rows={:nextup} />
    """
  end

  defp whole(%{variant: :banner} = assigns) do
    ~H"""
    <.flow_header standing={@standing} />
    <.banner scenario={@scenario} groups={@groups} class="mb-6" />
    <.groups groups={@groups} heading={:counts} rows={:today} />
    """
  end

  # W1: one stage per subflow, and Decision for the outcome; a line each
  attr :groups, :list, required: true
  attr :flow, :map, required: true
  attr :class, :any, default: nil

  defp stage_tracker(assigns) do
    assigns = assign(assigns, :stages, stages(assigns.groups, assigns.flow))

    ~H"""
    <ol class={["grid gap-3 sm:grid-cols-3", @class]}>
      <li :for={stage <- @stages} class="min-w-0">
        <div class={[
          "h-1.5 rounded-full",
          case stage.state do
            :done -> "bg-primary"
            :current -> "bg-primary/40"
            :ahead -> "bg-zinc-200"
          end
        ]} />
        <p class={[
          "mt-2 text-sm",
          stage.state == :current && "font-semibold",
          stage.state == :ahead && "text-zinc-400",
          stage.state == :done && "text-zinc-700"
        ]}>
          {stage.name}
        </p>
        <p class="text-xs text-zinc-500">{stage.line}</p>
      </li>
    </ol>
    """
  end

  defp stages(groups, flow) do
    [applicant, reviewer] = groups

    app_state =
      cond do
        done(applicant.forms) == length(applicant.forms) and
            active(reviewer.forms) + done(reviewer.forms) > 0 ->
          :done

        Enum.any?(applicant.forms, &(&1.status == :reopened)) ->
          :current

        done(applicant.forms) == length(applicant.forms) ->
          :done

        true ->
          :current
      end

    rev_state =
      cond do
        flow.decision -> :done
        active(reviewer.forms) + done(reviewer.forms) > 0 -> :current
        true -> :ahead
      end

    [
      %{
        name: "Application",
        state: app_state,
        line:
          case app_state do
            :done -> "Submitted #{List.last(applicant.forms).when}"
            :current -> "#{done(applicant.forms)} of #{length(applicant.forms)} forms done"
          end
      },
      %{
        name: "Review",
        state: rev_state,
        line:
          case rev_state do
            :ahead ->
              "Usually within 5 business days of submitting"

            :current ->
              "In review since #{(Enum.find(reviewer.forms, &(&1.status == :in_progress)) || hd(reviewer.forms)).when}"

            :done ->
              "Reviewed #{List.last(reviewer.forms).when}"
          end
      },
      %{
        name: "Decision",
        state: if(flow.decision, do: :done, else: :ahead),
        line:
          if(flow.decision, do: "#{flow.decision} · license issued", else: "You will be notified")
      }
    ]
  end

  # W2: the viewer's own subflows as rows; the others as one card each
  attr :groups, :list, required: true
  attr :flow, :map, required: true
  attr :rows, :atom, required: true

  defp split(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <p class="mb-2 text-sm font-semibold text-zinc-700">Your part</p>
        <.groups groups={mine(@groups)} heading={:counts} rows={@rows} />
      </div>
      <div>
        <p class="mb-2 text-sm font-semibold text-zinc-700">What happens after</p>
        <div
          :for={group <- theirs(@groups)}
          class="flex flex-wrap items-center gap-4 rounded-lg border border-zinc-300 px-6 py-4"
        >
          <.ring forms={group.forms} size={:sm} />
          <div class="min-w-0 flex-1">
            <p class="font-medium">Review by the licensing office</p>
            <p class="text-sm text-zinc-500">
              <%= cond do %>
                <% @flow.decision -> %>
                  Reviewed · {@flow.decision}
                <% active(group.forms) > 0 -> %>
                  In review since {Enum.find(group.forms, &(&1.status == :in_progress)).when} · {done(
                    group.forms
                  )} of {length(group.forms)} checks done
                <% done(mine(@groups) |> all_forms()) == length(mine(@groups) |> all_forms()) -> %>
                  Waiting on the reviewer
                <% true -> %>
                  Starts once your part is submitted · usually within 5 business days
              <% end %>
            </p>
          </div>
          <span :if={@flow.decision} class="badge badge-soft badge-success">{@flow.decision}</span>
        </div>
      </div>
    </div>
    """
  end

  # W3: the one sentence and the one action, by scenario
  attr :scenario, :atom, required: true
  attr :groups, :list, required: true
  attr :class, :any, default: nil

  defp banner(assigns) do
    assigns = assign(assigns, :next, next_up(assigns.groups))
    reopened = assigns.groups |> all_forms() |> Enum.find(&(&1.status == :reopened))
    assigns = assign(assigns, :reopened, reopened)

    ~H"""
    <div
      role="status"
      class={[
        "flex flex-wrap items-center gap-4 rounded-xl border px-5 py-4",
        case @scenario do
          :started -> "border-primary/30 bg-primary/5"
          :waiting -> "border-zinc-200 bg-zinc-50"
          :reopened -> "border-warning/40 bg-warning/10"
          :decided -> "border-success/40 bg-success/10"
        end,
        @class
      ]}
    >
      <div class="min-w-0 flex-1">
        <%= case @scenario do %>
          <% :started -> %>
            <p class="font-semibold">You are filling out this application.</p>
            <p class="text-sm text-zinc-600">Next: {@next.label}. Your answers are kept as you go.</p>
          <% :waiting -> %>
            <p class="font-semibold">Your part is done.</p>
            <p class="text-sm text-zinc-600">
              The licensing office is reviewing your application. Reviews usually take 5 business days; you will be notified.
            </p>
          <% :reopened -> %>
            <p class="font-semibold">{@reopened.label} needs your attention.</p>
            <p class="text-sm text-zinc-600">
              The reviewer wrote: “{@reopened.note}” Update the form and submit it again.
            </p>
          <% :decided -> %>
            <p class="font-semibold">Approved.</p>
            <p class="text-sm text-zinc-600">
              Your dog license was issued 4 days ago. Renewal is due in one year.
            </p>
        <% end %>
      </div>
      <button :if={@scenario == :started} type="button" class="btn btn-primary">Continue</button>
      <button :if={@scenario == :reopened} type="button" class="btn btn-warning">Open {@reopened.label}</button>
      <button :if={@scenario == :decided} type="button" class="btn btn-success">Download license</button>
    </div>
    """
  end

  # -- T · history ---------------------------------------------------------------

  attr :events, :list, required: true

  defp history(assigns) do
    ~H"""
    <ol class="relative ml-2 border-l border-zinc-200 pl-6">
      <li :for={event <- @events} class="relative pb-6 last:pb-0">
        <span class={[
          "absolute -left-[31px] top-1.5 size-2.5 rounded-full ring-4 ring-white",
          event_dot(event.what)
        ]} />
        <p class="text-sm">
          <span class="font-semibold">{event.what}</span>
          <span :if={event.form} class="text-zinc-700">· {event.form}</span>
          <span :if={!event.form} class="text-zinc-700">· Dog License</span>
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

  defp event_dot("Submitted"), do: "bg-success"
  defp event_dot("Reopened"), do: "bg-warning"
  defp event_dot("Started"), do: "bg-primary"
  defp event_dot(_saved), do: "bg-zinc-300"

  # -- X · combinations ------------------------------------------------------------

  attr :variant, :atom, required: true
  attr :groups, :list, required: true
  attr :flow, :map, required: true
  attr :standing, :any, required: true
  attr :scenario, :atom, required: true

  defp combo(%{variant: :evolve} = assigns) do
    ~H"""
    <.flow_header standing={@standing}>
      <:actions>
        <.flow_tabs active={:overview} class="mr-2" />
        <button type="button" class="btn btn-ghost">Download all</button>
      </:actions>
    </.flow_header>
    <.overall_card groups={@groups} />
    <div class="space-y-4">
      <.subflow_card :for={group <- @groups} group={group} rows={:nextup} />
    </div>
    <.fact_sheet flow={@flow} class="mt-8" />
    """
  end

  defp combo(%{variant: :tasklist} = assigns) do
    ~H"""
    <.flow_header standing={@standing}>
      <:actions>
        <.flow_tabs active={:overview} class="mr-2" />
        <button type="button" class="btn btn-ghost">Download all</button>
      </:actions>
    </.flow_header>
    <.banner scenario={@scenario} groups={@groups} class="mb-6" />
    <.stage_tracker groups={@groups} flow={@flow} class="mb-6" />
    <.groups groups={mine(@groups)} heading={:counts} rows={:tasklist} />
    <.fact_sheet flow={@flow} class="mt-8" />
    """
  end

  defp combo(%{variant: :cards} = assigns) do
    ~H"""
    <.flow_header standing={@standing}>
      <:actions>
        <.overall_rect groups={@groups} />
        <.flow_tabs active={:overview} class="ml-2" />
      </:actions>
    </.flow_header>
    <div class="space-y-6">
      <div>
        <p class="mb-2 text-sm font-semibold text-zinc-700">Your part</p>
        <.subflow_card :for={group <- mine(@groups)} group={group} rows={:stepper} />
      </div>
      <div>
        <p class="mb-2 text-sm font-semibold text-zinc-700">What happens after</p>
        <div
          :for={group <- theirs(@groups)}
          class="flex flex-wrap items-center gap-4 rounded-2xl border border-zinc-300 px-5 py-4"
        >
          <.ring forms={group.forms} size={:sm} />
          <div class="min-w-0 flex-1">
            <p class="font-medium">Review by the licensing office</p>
            <p class="text-sm text-zinc-500">
              <%= cond do %>
                <% @flow.decision -> %>
                  Reviewed · {@flow.decision}
                <% active(group.forms) > 0 -> %>
                  In review since {Enum.find(group.forms, &(&1.status == :in_progress)).when}
                <% true -> %>
                  Starts once your part is submitted
              <% end %>
            </p>
          </div>
          <span :if={@flow.decision} class="badge badge-soft badge-success">{@flow.decision}</span>
        </div>
      </div>
    </div>
    <.fact_sheet flow={@flow} class="mt-8" />
    """
  end

  # Today's Details fact sheet, kept under every combination
  attr :flow, :map, required: true
  attr :class, :any, default: nil

  defp fact_sheet(assigns) do
    ~H"""
    <div class={@class}>
      <p class="mb-2 text-sm font-semibold text-zinc-700">Details</p>
      <dl class="grid gap-x-8 gap-y-3 rounded-lg border border-zinc-300 px-6 py-4 text-sm sm:grid-cols-2 lg:grid-cols-4">
        <div>
          <dt class="text-xs text-zinc-500">Flow</dt>
          <dd class="font-medium">Dog License</dd>
        </div>
        <div>
          <dt class="text-xs text-zinc-500">Status</dt>
          <dd>
            <span class={[
              "badge badge-soft badge-sm",
              if(@flow.status == "Completed", do: "badge-success", else: "badge-warning")
            ]}>
              {@flow.status}
            </span>
          </dd>
        </div>
        <div>
          <dt class="text-xs text-zinc-500">Started</dt>
          <dd class="font-medium">{@flow.started}</dd>
        </div>
        <div>
          <dt class="text-xs text-zinc-500">Last updated</dt>
          <dd class="font-medium">{@flow.updated}</dd>
        </div>
      </dl>
    </div>
    """
  end
end
