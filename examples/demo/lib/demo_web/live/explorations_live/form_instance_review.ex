defmodule DemoWeb.ExplorationsLive.FormInstanceReview do
  @moduledoc """
  Scratch page for the reviewer's form page: a review-type form - checks
  against an applicant's answers and a note - drawn beside, over, or among
  the answers it reviews. The reviewer opens Review Owner Info, step one of
  the four in their part of Dog License; the applicant's Owner Information
  was submitted three days ago by dog_owner.

  Today `FormFlow.Web.Components.Forms.TypesReview` draws the answers in a
  disabled fieldset on the left and the review form on the right, two
  columns of equal weight. The first section varies which of the two the
  page is about, and where the other one goes (V1 to V5). The second takes
  V2 - the answers as a card on the form editor's dotted canvas, the review
  form in its own column - and puts the UI components picked on the continued
  page around it: X1b's flush toolbar, X3a's sticky header, X3b's segmented tabs.

  The header, badge, card, tabs, toolbar, and save state are
  `DemoWeb.ExplorationsLive.FormInstanceParts`, the same pieces the
  continued page draws. Hardcoded; nothing is wired up.

  Mounted on `live "/explorations/form-instance-review", ExplorationsLive.FormInstanceReview`.
  """

  use DemoWeb, :live_view

  import DemoWeb.ExplorationsLive.FormInstanceParts

  alias DemoWeb.ExplorationsLive.Shared

  # -- Data ------------------------------------------------------------------

  # The reviewer's four forms; they are on the first
  @steps [
    %{n: 1, label: "Review Owner Info", status: :current},
    %{n: 2, label: "Review Dog Info", status: :pending},
    %{n: 3, label: "Review Health Info", status: :pending},
    %{n: 4, label: "License Decision", status: :pending}
  ]

  # The applicant's Owner Information, as submitted
  @answers [
    {"Full name", "Grace Hopper"},
    {"Phone", "(555) 010-2244"},
    {"Email", "grace@example.com"},
    {"Street address", "12 Harbor Lane"},
    {"City", "Portsmouth"},
    {"Postal code", "03801"},
    {"Emergency contact", "Ada Lovelace"},
    {"Emergency contact phone", "(555) 010-9876"}
  ]

  # The same form with more asked of it, so a frame has something to scroll
  @long_answers @answers ++
                  [
                    {"Co-owner name", "-"},
                    {"Co-owner phone", "-"},
                    {"Mailing address, if different", "-"},
                    {"Preferred contact method", "Email"},
                    {"Years at this address", "6"},
                    {"Previous address", "4 Quay Street, Portsmouth"},
                    {"Landlord or owner", "Owner"},
                    {"Anything else we should know",
                     "Second dog in the household; first licensed 2019."}
                  ]

  # The review form: a check per thing to verify, then a note
  @checks [
    %{label: "Name matches the vaccination record", answer: :yes},
    %{label: "Address is inside the licensing area", answer: :yes},
    %{label: "Phone reachable", answer: :follow_up}
  ]

  @layouts [
    %{
      id: :current,
      title: "V1 · Current: two equal columns",
      note:
        "For reference. \"Reviewing: Owner Information\" over the answers in a disabled fieldset on the left, the review form on the right, both on the page's white."
    },
    %{
      id: :canvas_answers,
      title: "V2 · Answers on the canvas, review in a column",
      note:
        "The applicant's form as a card on the dotted canvas the form editor uses - read, not edited, and visibly someone else's - with the review form in its own bordered column on the right. The form-in-a-column-on-a-background of the templates page."
    },
    %{
      id: :canvas_review,
      title: "V3 · Review on the canvas, answers in a column",
      note:
        "The reverse: the review form is the card on the canvas, the thing being worked on; the applicant's answers are a quiet grey column on the left, a sheet to look things up in."
    },
    %{
      id: :interleaved,
      title: "V4 · Interleaved",
      note:
        "One column. Each of the applicant's answers is followed by the check that concerns it, indented, so the reviewer reads answer, verdict, answer, verdict. The note closes the form."
    },
    %{
      id: :sheet_rail,
      title: "V5 · Fact sheet and a narrow review rail",
      note:
        "The answers as a fact sheet - label over value, four to a row, as the instance page's Details - taking the width; the review form a narrow column on the right whose heading stays at the top as the sheet scrolls."
    }
  ]

  @variations [
    %{
      id: :x1b,
      title: "V2a · V2 under X1b",
      note:
        "The F3b rectangle in the header's right, the flush toolbar sticky under it - Edit / View / History, the save state, Draft, Save draft, Submit review - and V2 below: the answers scroll on their canvas while the review column stays put beneath the bar."
    },
    %{
      id: :x3a,
      title: "V2b · V2 under X3a",
      note:
        "The whole header is sticky: title, Draft, the buttons, then the tab line with the save state at its right. The F1b card for the reviewer's four steps scrolls away with the answers; the review column stays."
    },
    %{
      id: :x3b,
      title: "V2c · V2 under X3b",
      note:
        "The header is sticky, with the segmented Edit / View / History among the actions, Draft after the title. The F1b card and the canvas scroll; the review column stays."
    }
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Review form page")
     |> assign(:layouts, @layouts)
     |> assign(:variations, @variations)
     |> assign(:steps, @steps)
     |> assign(:answers, @answers)
     |> assign(:long_answers, @long_answers)
     |> assign(:checks, @checks)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="space-y-6">
        <header class="space-y-2">
          <Shared.back_link />
          <h1 class="text-2xl font-semibold">Review form page</h1>
          <p class="text-base-content/70">
            The reviewer's form page: checks against an applicant's answers,
            drawn beside, over, or among the answers they review. Today the two
            are equal columns on the page's white. Hardcoded: the reviewer on
            Review Owner Info, step one of four in Dog License; the applicant's
            Owner Information submitted three days ago by dog_owner. Nothing is
            wired up.
          </p>
        </header>

        <section id="layouts" class="space-y-10 border-t border-gray-200 pt-10">
          <header class="space-y-2">
            <h2 class="text-2xl font-semibold">Layouts</h2>
            <p class="text-base-content/70">
              Which of the two forms the page is about, and where the other goes.
              Each under the T2 header with the F3a rectangle and C3's actions.
            </p>
          </header>
          <div :for={d <- @layouts} class="space-y-3">
            <.direction_title d={d} />
            <.frame label="Review Owner Info · step 1 of 4 · reviewing Owner Information">
              <.page_header forms={@steps}>
                <:actions>
                  <.pill id={"pill-#{d.id}"} variant={:rect} forms={@steps} />
                  <.save_state who="reviewer" />
                  <button type="button" class="btn btn-ghost">Save draft</button>
                  <button type="button" class="btn btn-primary">Submit review</button>
                </:actions>
              </.page_header>
              <.layout variant={d.id} answers={@answers} checks={@checks} />
            </.frame>
          </div>
        </section>

        <section id="variations" class="space-y-10 border-t border-gray-200 pt-10">
          <header class="space-y-2">
            <h2 class="text-2xl font-semibold">V2, with the page's UI components</h2>
            <p class="text-base-content/70">
              V2 under the header, badge, tabs, and actions picked on the <.link
                navigate="/explorations/form-instance-continued"
                class="text-indigo-600 hover:underline"
              >
                continued page
              </.link>. Each frame scrolls; the answers are the longer form so
              there is something to scroll.
            </p>
          </header>
          <div :for={d <- @variations} class="space-y-3">
            <.direction_title d={d} />
            <.frame label="Review Owner Info · scroll the frame" flush>
              <.variation variant={d.id} steps={@steps} answers={@long_answers} checks={@checks} />
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

  # -- Layouts -------------------------------------------------------------------

  attr :variant, :atom, required: true
  attr :answers, :list, required: true
  attr :checks, :list, required: true

  attr :sticky, :boolean,
    default: false,
    doc: "the review column stays put while the answers scroll"

  defp layout(%{variant: :current} = assigns) do
    ~H"""
    <div class="flex flex-wrap gap-6">
      <section class="min-w-0 flex-1">
        <h3 class="mb-2 text-sm font-medium text-zinc-500">Reviewing: Owner Information</h3>
        <fieldset disabled class="max-w-md space-y-3">
          <.answer_field :for={{label, value} <- @answers} label={label} value={value} />
        </fieldset>
      </section>
      <section class="min-w-0 flex-1">
        <.review_form checks={@checks} />
      </section>
    </div>
    """
  end

  defp layout(%{variant: :canvas_answers} = assigns) do
    ~H"""
    <div class="grid gap-6 lg:grid-cols-5">
      <div class={["lg:col-span-3", canvas()]}>
        <div class="mx-auto max-w-xl rounded-lg border border-zinc-200 bg-white p-6 shadow-sm">
          <.source_heading />
          <div class="space-y-3">
            <.answer_field :for={{label, value} <- @answers} label={label} value={value} />
          </div>
        </div>
      </div>
      <div class={[
        "self-start rounded-lg border border-zinc-300 p-6 lg:col-span-2",
        @sticky && "lg:sticky lg:top-24"
      ]}>
        <.review_form checks={@checks} />
      </div>
    </div>
    """
  end

  defp layout(%{variant: :canvas_review} = assigns) do
    ~H"""
    <div class="grid gap-6 lg:grid-cols-5">
      <div class="rounded-lg bg-zinc-50 p-6 lg:col-span-2">
        <.source_heading />
        <dl class="divide-y divide-zinc-200 text-sm">
          <div :for={{label, value} <- @answers} class="flex justify-between gap-4 py-2">
            <dt class="text-zinc-500">{label}</dt>
            <dd class="text-right font-medium">{value}</dd>
          </div>
        </dl>
      </div>
      <div class={["lg:col-span-3", canvas()]}>
        <div class="mx-auto max-w-xl rounded-lg border border-zinc-200 bg-white p-6 shadow-sm">
          <.review_form checks={@checks} />
        </div>
      </div>
    </div>
    """
  end

  defp layout(%{variant: :interleaved} = assigns) do
    # Which check follows which answer
    pairs = %{
      "Full name" => Enum.at(assigns.checks, 0),
      "Phone" => Enum.at(assigns.checks, 2),
      "Postal code" => Enum.at(assigns.checks, 1)
    }

    assigns = assign(assigns, :pairs, pairs)

    ~H"""
    <div class="mx-auto max-w-2xl">
      <.source_heading />
      <form class="space-y-4" onsubmit="return false">
        <%= for {label, value} <- @answers do %>
          <div class="flex items-baseline justify-between gap-4 text-sm">
            <span class="text-zinc-500">{label}</span>
            <span class="font-medium">{value}</span>
          </div>
          <div :if={@pairs[label]} class="ml-4 rounded-lg border border-zinc-200 bg-zinc-50 px-4 py-3">
            <.check check={@pairs[label]} />
          </div>
        <% end %>
        <label class="block pt-2">
          <span class="text-sm font-medium">Notes for the applicant</span>
          <textarea class="textarea textarea-bordered mt-1 w-full" rows="3" readonly>Please confirm the phone number; the vaccination record lists a different one.</textarea>
        </label>
      </form>
    </div>
    """
  end

  defp layout(%{variant: :sheet_rail} = assigns) do
    ~H"""
    <div class="grid gap-6 lg:grid-cols-4">
      <div class="lg:col-span-3">
        <.source_heading />
        <div class="rounded-lg border border-zinc-300 p-6">
          <dl class="grid grid-cols-1 gap-4 md:grid-cols-4">
            <div :for={{label, value} <- @answers} class="min-w-0">
              <dt class="text-sm font-medium text-zinc-500">{label}</dt>
              <dd class="mt-0.5 text-sm">{value}</dd>
            </div>
          </dl>
        </div>
      </div>
      <div class="lg:col-span-1">
        <div class="sticky top-4 rounded-lg border border-zinc-300 p-5">
          <.review_form checks={@checks} compact />
        </div>
      </div>
    </div>
    """
  end

  defp canvas,
    do:
      "rounded-md border border-zinc-200 bg-white p-6 bg-[radial-gradient(#d4d4d8_1px,transparent_1px)] [background-size:16px_16px]"

  # -- V2 with the page's UI components ------------------------------------------

  attr :variant, :atom, required: true
  attr :steps, :list, required: true
  attr :answers, :list, required: true
  attr :checks, :list, required: true

  defp variation(%{variant: :x1b} = assigns) do
    ~H"""
    <div class="max-h-[34rem] overflow-y-auto">
      <div class="px-6 pt-5">
        <.page_header forms={@steps} class="mb-0">
          <:actions><.pill id="v2a-pill" variant={:caret} forms={@steps} /></:actions>
        </.page_header>
      </div>
      <.toolbar active={:edit} editing status="Draft" flush who="reviewer" />
      <div class="px-6 py-5">
        <.layout variant={:canvas_answers} answers={@answers} checks={@checks} sticky />
      </div>
    </div>
    """
  end

  defp variation(%{variant: :x3a} = assigns) do
    ~H"""
    <div class="max-h-[34rem] overflow-y-auto">
      <div class="sticky top-0 z-10 bg-white/95 px-6 pt-4 backdrop-blur">
        <.page_header forms={@steps} class="mb-3">
          <:actions>
            <.status_badge status="Draft" class="mr-2" />
            <button type="button" class="btn btn-ghost">Save draft</button>
            <button type="button" class="btn btn-primary">Submit review</button>
          </:actions>
        </.page_header>
        <.tabs variant={:underline} active={:edit}>
          <:aside><.save_state who="reviewer" /></:aside>
        </.tabs>
      </div>
      <div class="px-6 py-5">
        <.card variant={:toggle} forms={@steps} />
        <.layout variant={:canvas_answers} answers={@answers} checks={@checks} sticky />
      </div>
    </div>
    """
  end

  defp variation(%{variant: :x3b} = assigns) do
    ~H"""
    <div class="max-h-[34rem] overflow-y-auto">
      <div class="sticky top-0 z-10 border-b border-zinc-200 bg-white/95 px-6 pt-4 backdrop-blur">
        <.page_header forms={@steps} status="Draft">
          <:actions>
            <.tabs variant={:segmented} active={:edit} class="mr-2" />
            <.save_state who="reviewer" />
            <button type="button" class="btn btn-ghost">Save draft</button>
            <button type="button" class="btn btn-primary">Submit review</button>
          </:actions>
        </.page_header>
      </div>
      <div class="px-6 py-5">
        <.card variant={:toggle} forms={@steps} />
        <.layout variant={:canvas_answers} answers={@answers} checks={@checks} sticky />
      </div>
    </div>
    """
  end

  # -- Pieces ----------------------------------------------------------------------

  defp source_heading(assigns) do
    ~H"""
    <div class="mb-3">
      <h3 class="text-sm font-semibold">Owner Information</h3>
      <p class="text-xs text-zinc-500">
        Submitted 3 days ago by <code>dog_owner</code> · 2026-09-13 16:05 UTC
      </p>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp answer_field(assigns) do
    ~H"""
    <label class="block">
      <span class="text-sm font-medium">{@label}</span>
      <input type="text" class="input input-bordered mt-1 w-full" value={@value} readonly />
    </label>
    """
  end

  attr :checks, :list, required: true
  attr :compact, :boolean, default: false

  defp review_form(assigns) do
    ~H"""
    <div class="mb-3">
      <h3 class="text-sm font-semibold">Your review</h3>
      <p :if={!@compact} class="text-xs text-zinc-500">
        Three checks and a note. Submit when every check has an answer.
      </p>
    </div>
    <form class="space-y-4" onsubmit="return false">
      <.check :for={check <- @checks} check={check} compact={@compact} />
      <label class="block pt-1">
        <span class="text-sm font-medium">Notes for the applicant</span>
        <textarea class="textarea textarea-bordered mt-1 w-full" rows="3" readonly>Please confirm the phone number; the vaccination record lists a different one.</textarea>
      </label>
    </form>
    """
  end

  attr :check, :map, required: true
  attr :compact, :boolean, default: false

  defp check(assigns) do
    ~H"""
    <fieldset>
      <legend class="text-sm font-medium">{@check.label}</legend>
      <div class={["mt-1.5 flex gap-4 text-sm", @compact && "flex-col gap-1"]}>
        <label class="flex items-center gap-2">
          <input
            type="radio"
            class="radio radio-sm radio-primary"
            checked={@check.answer == :yes}
            readonly
          /> Matches
        </label>
        <label class="flex items-center gap-2">
          <input
            type="radio"
            class="radio radio-sm radio-primary"
            checked={@check.answer == :follow_up}
            readonly
          /> Needs follow-up
        </label>
      </div>
    </fieldset>
    """
  end
end
