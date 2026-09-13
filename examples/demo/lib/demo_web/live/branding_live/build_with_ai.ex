defmodule DemoWeb.BrandingLive.BuildWithAI do
  @moduledoc """
  Scratch directions for the form editor's **Build with AI** panel while a
  model is answering.

  The panel itself is built (`FormFlow.Web.Templates.Forms.Edit`): a heading,
  a line saying what it does, and a prompt. What is not decided is what it
  looks like for the twenty to sixty seconds between pressing Build and a
  form appearing — long enough that a disabled button is not an answer, and
  the one part of the feature every user sees every time.

  Each direction is one `panel/1` clause, drawn in the waiting state with the
  same hardcoded prompt, so they can be read side by side. `reference/1`
  draws the two settled states for comparison: ready (with the model select a
  host offering several models gets) and not configured. Nothing here is
  wired to the real page, and none of it animates anything real — the CSS in
  `styles/1` is scoped to this page.

  `steps_variations/0` and `steps_panel/1` are the second pass, and **6f is
  the one picked**: direction 6 (the steps it works through) on an ordinary
  white panel, with direction 12's moving gradient border around the steps
  box rather than the panel, **each step carrying its own elapsed time**, and
  Cancel as the only thing under it. The total elapsed time went away with
  the choice — the running step's clock is that number, and a panel that
  showed both showed it twice.

  The directions differ along three axes worth naming when picking one:

    * **Where the motion is** — in the button, in the panel, in the preview
      column, or at the top of the page.
    * **Whether the prompt stays readable.** An admin re-reads what they
      asked for while they wait; a skeleton or an overlay takes that away.
    * **Whether it claims to know progress.** Nothing here knows: there is no
      percentage, no token count, no step the model reports. A direction that
      looks like a progress bar is making a promise the request cannot keep,
      and that is a cost, not a bug to fix.
  """

  use DemoWeb, :html

  @prompt "Let's create a form with fields for the dog's name, breed, date of birth, and whether it is microchipped."

  @directions [
    %{
      id: :button_spinner,
      title: "1. Spinner in the button",
      note: "The smallest thing that could work: the button says what it is doing."
    },
    %{
      id: :inline_status,
      title: "2. A status line under the button",
      note: "Room for a sentence the button has no space for."
    },
    %{
      id: :progress_bar,
      title: "3. An indeterminate bar",
      note: "Familiar, and the one shape that hints at a percentage nobody has."
    },
    %{
      id: :typing_dots,
      title: "4. Dots where the form will be",
      note: "The chat idiom, put where the answer will land."
    },
    %{
      id: :elapsed_timer,
      title: "5. Elapsed time, and a way out",
      note: "Says how long it has been and offers to stop — the honest version."
    },
    %{
      id: :status_steps,
      title: "6. The steps it works through",
      note: "Reads as progress; the steps are the page's own, not the model's."
    },
    %{
      id: :rotating_lines,
      title: "7. One line at a time",
      note: "Cycling status text. Charming once, grating on the fifth build."
    },
    %{
      id: :skeleton_form,
      title: "8. A skeleton of the form",
      note: "Shows what is coming rather than that something is happening."
    },
    %{
      id: :ghost_elements,
      title: "9. Elements arriving one by one",
      note: "Looks like streaming. Nothing streams — this is a loop on a timer."
    },
    %{
      id: :prompt_sweep,
      title: "10. A sweep across the prompt",
      note: "The prompt stays readable and is visibly being worked on."
    },
    %{
      id: :cursor_blink,
      title: "11. A cursor, as if it were writing",
      note: "Borrows the terminal's idiom for \"busy but alive\"."
    },
    %{
      id: :gradient_border,
      title: "12. The border, alive",
      note: "The brand gradient moving around the panel. Nothing else changes."
    },
    %{
      id: :sparkle_pulse,
      title: "13. A pulsing mark",
      note: "One icon doing the work, beside the text."
    },
    %{
      id: :progress_ring,
      title: "14. A ring around the mark",
      note: "The same idea, closed — reads calmer than a bar."
    },
    %{
      id: :equalizer_bars,
      title: "15. Bars, like a level meter",
      note: "Motion without a shape that implies completion."
    },
    %{
      id: :dotted_wave,
      title: "16. A field of dots, waving",
      note: "The most decorative. Fills the panel's empty space with texture."
    },
    %{
      id: :overlay_blur,
      title: "17. The panel behind a blur",
      note: "Unmistakably busy, and the prompt is no longer readable."
    },
    %{
      id: :quiet_lock,
      title: "18. Quiet: dim everything, say one word",
      note: "The opposite direction — almost no motion at all."
    },
    %{
      id: :preview_takeover,
      title: "19. The preview builds instead",
      note: "The editor stays still; the column that will show the form does the waiting.",
      wide: true
    },
    %{
      id: :page_banner,
      title: "20. A strip at the top of the page",
      note: "Leaves the panel alone, so the admin can keep working elsewhere.",
      wide: true
    }
  ]

  @doc "Every waiting-state direction, in the order the page draws them."
  def directions, do: @directions

  @doc "The prompt every mock shows, so the directions differ only in their waiting state."
  def prompt, do: @prompt

  # -- Reference states ------------------------------------------------------

  attr(:variant, :atom, required: true, doc: ":idle or :not_configured")

  def reference(%{variant: :idle} = assigns) do
    assigns = assign(assigns, :prompt, @prompt)

    ~H"""
    <.chrome>
      <.prompt_box text={@prompt} />
      <div class="mt-3 flex items-end justify-between gap-3">
        <label class="text-sm">
          <span class="mb-1 block text-gray-600">Model</span>
          <select class="select select-sm w-64">
            <option>Claude Opus 5 — the careful one</option>
            <option>Claude Sonnet 5 — the quick one</option>
          </select>
        </label>
        <span class="btn btn-primary">Build</span>
      </div>
    </.chrome>
    """
  end

  def reference(%{variant: :not_configured} = assigns) do
    ~H"""
    <.chrome>
      <div class="rounded-md border border-zinc-200 bg-zinc-50 p-3 text-sm text-zinc-700">
        Build with AI isn't set up for this application yet. It needs a model and an API key,
        which an administrator configures where FormFlow is mounted.
      </div>
    </.chrome>
    """
  end

  # -- Waiting states --------------------------------------------------------

  attr(:direction, :atom, required: true)

  def panel(%{direction: :button_spinner} = assigns) do
    ~H"""
    <.chrome>
      <.prompt_box text={prompt()} dim />
      <div class="mt-3">
        <span class="btn btn-primary btn-disabled">
          <span class="loading loading-spinner loading-sm" /> Building…
        </span>
      </div>
    </.chrome>
    """
  end

  def panel(%{direction: :inline_status} = assigns) do
    ~H"""
    <.chrome>
      <.prompt_box text={prompt()} dim />
      <div class="mt-3 flex items-center gap-3">
        <span class="btn btn-primary btn-disabled">
          <span class="loading loading-spinner loading-sm" /> Building…
        </span>
        <span class="text-sm text-gray-500">
          Writing the form. This usually takes half a minute.
        </span>
      </div>
    </.chrome>
    """
  end

  def panel(%{direction: :progress_bar} = assigns) do
    ~H"""
    <.chrome>
      <div class="mb-3 h-1 w-full overflow-hidden rounded-full bg-zinc-200">
        <span class="bwa-indeterminate block h-full w-1/3 rounded-full bg-primary" />
      </div>
      <.prompt_box text={prompt()} dim />
      <div class="mt-3">
        <span class="btn btn-primary btn-disabled">Building…</span>
      </div>
    </.chrome>
    """
  end

  def panel(%{direction: :typing_dots} = assigns) do
    ~H"""
    <.chrome>
      <.prompt_box text={prompt()} dim />
      <div class="mt-3 flex items-center gap-3 rounded-md border border-dashed border-zinc-300 px-4 py-6">
        <span class="loading loading-dots loading-md text-primary" />
        <span class="text-sm text-gray-600">Building your form</span>
      </div>
    </.chrome>
    """
  end

  def panel(%{direction: :elapsed_timer} = assigns) do
    ~H"""
    <.chrome>
      <.prompt_box text={prompt()} dim />
      <div class="mt-3 flex flex-wrap items-center gap-3">
        <span class="btn btn-primary btn-disabled">
          <span class="loading loading-spinner loading-sm" /> Building…
        </span>
        <span class="font-mono text-sm tabular-nums text-gray-500">0:14</span>
        <button type="button" class="link link-primary text-sm">Stop</button>
      </div>
    </.chrome>
    """
  end

  def panel(%{direction: :status_steps} = assigns) do
    ~H"""
    <.chrome>
      <.prompt_box text={prompt()} dim />
      <ol class="mt-3 space-y-2 rounded-md border border-zinc-200 bg-zinc-50 p-3 text-sm">
        <li class="flex items-center gap-2 text-gray-500">
          <.check /> Read the form as it stands
        </li>
        <li class="flex items-center gap-2 text-gray-500">
          <.check /> Sent your description
        </li>
        <li class="flex items-center gap-2 font-medium text-gray-900">
          <span class="loading loading-spinner loading-xs text-primary" /> Writing the elements
        </li>
        <li class="flex items-center gap-2 text-gray-400">
          <span class="size-4 rounded-full border border-zinc-300" />
          Checking the builder can show them
        </li>
      </ol>
    </.chrome>
    """
  end

  def panel(%{direction: :rotating_lines} = assigns) do
    ~H"""
    <.chrome>
      <.prompt_box text={prompt()} dim />
      <div class="mt-3 flex items-center gap-3 rounded-md border border-zinc-200 px-4 py-5">
        <span class="loading loading-ring loading-md text-primary" />
        <span class="relative block h-5 grow text-sm text-gray-600">
          <span class="bwa-cycle absolute inset-0" style="animation-delay: 0s">
            Reading the form as it stands…
          </span>
          <span class="bwa-cycle absolute inset-0" style="animation-delay: 2s">
            Deciding which questions to ask…
          </span>
          <span class="bwa-cycle absolute inset-0" style="animation-delay: 4s">
            Writing them out…
          </span>
        </span>
      </div>
    </.chrome>
    """
  end

  def panel(%{direction: :skeleton_form} = assigns) do
    ~H"""
    <.chrome>
      <p class="mb-3 flex items-center gap-2 text-sm text-gray-600">
        <span class="loading loading-spinner loading-xs text-primary" /> Building your form…
      </p>
      <div class="space-y-4 rounded-md border border-zinc-200 p-4">
        <div :for={width <- ~w(w-24 w-32 w-20 w-28)} class="space-y-2">
          <div class={["h-3 rounded bwa-shimmer", width]} />
          <div class="h-9 w-full rounded bwa-shimmer" />
        </div>
      </div>
    </.chrome>
    """
  end

  def panel(%{direction: :ghost_elements} = assigns) do
    ~H"""
    <.chrome>
      <p class="mb-3 flex items-center gap-2 text-sm text-gray-600">
        <span class="loading loading-spinner loading-xs text-primary" /> Building your form…
      </p>
      <div class="space-y-2">
        <div
          :for={
            {label, delay} <- [{"Dog's name", "0s"}, {"Breed", "0.7s"}, {"Date of birth", "1.4s"}]
          }
          class="bwa-arrive flex items-center gap-3 rounded-md border border-zinc-200 bg-white p-3"
          style={"animation-delay: #{delay}"}
        >
          <span class="rounded bg-zinc-100 px-2 py-0.5 text-[10px] font-medium text-zinc-500">text</span>
          <span class="text-sm text-gray-700">{label}</span>
        </div>
        <div
          class="bwa-arrive flex items-center gap-2 px-3 py-2 text-sm text-gray-400"
          style="animation-delay: 2.1s"
        >
          <span class="loading loading-dots loading-xs" /> and more
        </div>
      </div>
    </.chrome>
    """
  end

  def panel(%{direction: :prompt_sweep} = assigns) do
    ~H"""
    <.chrome>
      <div class="bwa-sweep rounded-md border border-primary/40 bg-white p-3 text-sm text-gray-700">
        {prompt()}
      </div>
      <div class="mt-3 flex items-center gap-3">
        <span class="btn btn-primary btn-disabled">Building…</span>
        <span class="text-sm text-gray-500">Working from what you wrote</span>
      </div>
    </.chrome>
    """
  end

  def panel(%{direction: :cursor_blink} = assigns) do
    ~H"""
    <.chrome>
      <.prompt_box text={prompt()} dim />
      <div class="mt-3 rounded-md border border-zinc-200 bg-zinc-900 p-3 font-mono text-sm text-zinc-100">
        <span class="text-zinc-400">building</span>
        <span class="bwa-blink ml-0.5 inline-block h-4 w-2 translate-y-0.5 bg-zinc-100" />
      </div>
    </.chrome>
    """
  end

  def panel(%{direction: :gradient_border} = assigns) do
    ~H"""
    <div class="bwa-border rounded-xl p-[2px]">
      <div class="rounded-[10px] bg-white p-4">
        <.chrome_head />
        <.prompt_box text={prompt()} dim />
        <div class="mt-3">
          <span class="btn btn-primary btn-disabled">Building…</span>
        </div>
      </div>
    </div>
    """
  end

  def panel(%{direction: :sparkle_pulse} = assigns) do
    ~H"""
    <.chrome>
      <.prompt_box text={prompt()} dim />
      <div class="mt-3 flex items-center gap-4 rounded-md border border-zinc-200 px-4 py-5">
        <span class="relative flex size-8 items-center justify-center">
          <span class="absolute inline-flex size-8 animate-ping rounded-full bg-primary/30" />
          <.sparkle class="relative size-6 text-primary" />
        </span>
        <span class="text-sm text-gray-600">Building your form…</span>
      </div>
    </.chrome>
    """
  end

  def panel(%{direction: :progress_ring} = assigns) do
    ~H"""
    <.chrome>
      <.prompt_box text={prompt()} dim />
      <div class="mt-3 flex items-center gap-4 rounded-md border border-zinc-200 px-4 py-5">
        <span class="relative flex size-9 items-center justify-center">
          <span class="absolute size-9 animate-spin rounded-full border-2 border-primary/20 border-t-primary" />
          <.sparkle class="size-4 text-primary" />
        </span>
        <span class="text-sm text-gray-600">Building your form…</span>
      </div>
    </.chrome>
    """
  end

  def panel(%{direction: :equalizer_bars} = assigns) do
    ~H"""
    <.chrome>
      <.prompt_box text={prompt()} dim />
      <div class="mt-3 flex items-center gap-4 rounded-md border border-zinc-200 px-4 py-5">
        <span class="flex h-6 items-end gap-1">
          <span
            :for={delay <- ~w(0s 0.15s 0.3s 0.45s 0.6s)}
            class="bwa-bar w-1.5 rounded-sm bg-primary"
            style={"animation-delay: #{delay}"}
          />
        </span>
        <span class="text-sm text-gray-600">Building your form…</span>
      </div>
    </.chrome>
    """
  end

  def panel(%{direction: :dotted_wave} = assigns) do
    ~H"""
    <.chrome>
      <.prompt_box text={prompt()} dim />
      <div class="mt-3 flex flex-col items-center gap-3 rounded-md border border-zinc-200 px-4 py-6">
        <span class="flex gap-1.5">
          <span
            :for={i <- 0..11}
            class="bwa-dot size-1.5 rounded-full bg-primary"
            style={"animation-delay: #{i * 0.1}s"}
          />
        </span>
        <span class="text-sm text-gray-600">Building your form…</span>
      </div>
    </.chrome>
    """
  end

  def panel(%{direction: :overlay_blur} = assigns) do
    ~H"""
    <div class="relative overflow-hidden rounded-lg border border-zinc-200 bg-white">
      <div class="p-4 blur-[2px]">
        <.chrome_head />
        <.prompt_box text={prompt()} />
        <div class="mt-3"><span class="btn btn-primary">Build</span></div>
      </div>
      <div class="absolute inset-0 flex items-center justify-center bg-white/60">
        <div class="flex items-center gap-3 rounded-lg border border-zinc-200 bg-white px-4 py-3 shadow-sm">
          <span class="loading loading-spinner loading-sm text-primary" />
          <span class="text-sm font-medium text-gray-700">Building your form…</span>
        </div>
      </div>
    </div>
    """
  end

  def panel(%{direction: :quiet_lock} = assigns) do
    ~H"""
    <.chrome>
      <div class="opacity-40">
        <.prompt_box text={prompt()} />
      </div>
      <p class="mt-3 text-sm text-gray-500">
        Building<span class="bwa-ellipsis" />
      </p>
    </.chrome>
    """
  end

  def panel(%{direction: :preview_takeover} = assigns) do
    ~H"""
    <div class="grid gap-6 md:grid-cols-2">
      <.chrome>
        <.prompt_box text={prompt()} dim />
        <div class="mt-3">
          <span class="btn btn-primary btn-disabled">
            <span class="loading loading-spinner loading-sm" /> Building…
          </span>
        </div>
      </.chrome>

      <div class="rounded-lg border border-zinc-200 bg-white p-4">
        <h4 class="mb-1 text-lg font-bold text-gray-900">Preview</h4>
        <p class="mb-3 text-sm text-gray-500">The form as a user will see it.</p>
        <div class="space-y-4 rounded-md border border-dashed border-zinc-300 p-4">
          <div :for={width <- ~w(w-24 w-32 w-20)} class="space-y-2">
            <div class={["h-3 rounded bwa-shimmer", width]} />
            <div class="h-9 w-full rounded bwa-shimmer" />
          </div>
          <p class="flex items-center gap-2 pt-1 text-xs text-gray-500">
            <span class="loading loading-spinner loading-xs text-primary" /> Building your form…
          </p>
        </div>
      </div>
    </div>
    """
  end

  def panel(%{direction: :page_banner} = assigns) do
    ~H"""
    <div class="space-y-3 rounded-xl border border-dashed border-gray-300 bg-gray-50/60 p-4">
      <div class="flex items-center gap-3 rounded-md border border-primary/30 bg-primary/5 px-4 py-2.5">
        <span class="loading loading-spinner loading-sm text-primary" />
        <span class="text-sm text-gray-700">
          <span class="font-medium">Building your form.</span>
          You can keep editing the details above — the form will land in the editor when it is ready.
        </span>
        <button type="button" class="link link-primary ml-auto text-sm">Stop</button>
      </div>
      <.chrome>
        <.prompt_box text={prompt()} />
        <div class="mt-3"><span class="btn btn-primary btn-disabled">Build</span></div>
      </.chrome>
    </div>
    """
  end

  # -- Direction 6, refined --------------------------------------------------

  @steps_variations [
    %{
      id: :pick,
      title: "6a. The steps, untimed",
      note: "The shape without the clocks: white panel, moving border on the steps box, Cancel."
    },
    %{
      id: :numbered,
      title: "6b. Numbered, not ticked",
      note: "The same rows counting up rather than checking off."
    },
    %{
      id: :horizontal,
      title: "6c. Across, not down",
      note: "A stepper. Takes a quarter of the height and loses the wording."
    },
    %{
      id: :current_only,
      title: "6d. Only the step it is on",
      note: "\"Step 3 of 4\" and a segmented bar — the steps without the list."
    },
    %{
      id: :sub_line,
      title: "6e. A second line on the step it is on",
      note: "Room to say the slow one is slow, so the wait is expected."
    },
    %{
      id: :timings,
      title: "6f. The pick — each step's own time",
      note:
        "The clock lives on the row that is running, so the panel needs no total in the corner."
    },
    %{
      id: :instead_of_prompt,
      title: "6g. In place of the prompt",
      note: "The prompt goes away while it builds; the steps get the whole panel."
    },
    %{
      id: :beside_skeleton,
      title: "6h. Steps beside what is coming",
      note: "A left rail against a skeleton of the form — #6 married to #8."
    },
    %{
      id: :plain_border,
      title: "6i. The same, without the gradient",
      note: "For comparison: the same box with a still border."
    },
    %{
      id: :quiet_steps,
      title: "6j. Quiet steps",
      note: "No spinner. The current row is simply the dark one, and it shimmers."
    },
    %{
      id: :done,
      title: "6k. The moment it lands",
      note: "Every step ticked, the border still, and what happened next."
    },
    %{
      id: :failed,
      title: "6l. The moment it doesn't",
      note: "The step that failed says so, and the prompt is still there to fix."
    }
  ]

  @doc "The second pass: direction 6 as picked, and the shapes it could take."
  def steps_variations, do: @steps_variations

  attr(:variant, :atom, required: true)

  def steps_panel(%{variant: :pick} = assigns) do
    ~H"""
    <.card>
      <.chrome_head />
      <.prompt_box text={prompt()} dim />
      <.bordered_box class="mt-3"><.steps /></.bordered_box>
      <.waiting_footer />
    </.card>
    """
  end

  def steps_panel(%{variant: :numbered} = assigns) do
    ~H"""
    <.card>
      <.chrome_head />
      <.prompt_box text={prompt()} dim />
      <.bordered_box class="mt-3">
        <ol class="space-y-2 text-sm">
          <li
            :for={{label, index, state} <- numbered_steps()}
            class={["flex items-center gap-3", step_text(state)]}
          >
            <span class={[
              "flex size-5 shrink-0 items-center justify-center rounded-full text-[11px] font-semibold",
              state == :done && "bg-primary/10 text-primary",
              state == :running && "bg-primary text-primary-content",
              state == :pending && "border border-zinc-300 text-zinc-400"
            ]}>
              {index}
            </span>
            {label}
          </li>
        </ol>
      </.bordered_box>
      <.waiting_footer />
    </.card>
    """
  end

  def steps_panel(%{variant: :horizontal} = assigns) do
    ~H"""
    <.card>
      <.chrome_head />
      <.prompt_box text={prompt()} dim />
      <.bordered_box class="mt-3">
        <div class="flex items-center px-1 py-1">
          <div
            :for={{short, _index, state} <- numbered_steps()}
            class="flex flex-1 items-center last:flex-none"
          >
            <div class="flex flex-col items-center gap-1">
              <span class={[
                "flex size-6 items-center justify-center rounded-full",
                state == :done && "bg-primary/10 text-primary",
                state == :running && "bg-primary text-primary-content",
                state == :pending && "border border-zinc-300"
              ]}>
                <.check :if={state == :done} />
                <span :if={state == :running} class="loading loading-spinner loading-xs" />
              </span>
              <span class={["text-[11px] leading-tight", step_text(state)]}>{short}</span>
            </div>
            <span class={[
              "mx-1 mb-4 h-px flex-1",
              state == :done && "bg-primary/40",
              state != :done && "bg-zinc-200"
            ]} />
          </div>
        </div>
      </.bordered_box>
      <.waiting_footer />
    </.card>
    """
  end

  def steps_panel(%{variant: :current_only} = assigns) do
    ~H"""
    <.card>
      <.chrome_head />
      <.prompt_box text={prompt()} dim />
      <.bordered_box class="mt-3">
        <div class="space-y-2">
          <div class="flex items-center gap-2 text-sm">
            <span class="loading loading-spinner loading-xs text-primary" />
            <span class="font-medium text-gray-900">Writing the elements</span>
            <span class="text-gray-400">· step 3 of 4</span>
          </div>
          <div class="flex gap-1">
            <span
              :for={filled <- [true, true, true, false]}
              class={["h-1 flex-1 rounded-full", if(filled, do: "bg-primary", else: "bg-zinc-200")]}
            />
          </div>
        </div>
      </.bordered_box>
      <.waiting_footer />
    </.card>
    """
  end

  def steps_panel(%{variant: :sub_line} = assigns) do
    ~H"""
    <.card>
      <.chrome_head />
      <.prompt_box text={prompt()} dim />
      <.bordered_box class="mt-3">
        <ol class="space-y-2 text-sm">
          <li class="flex items-center gap-2 text-gray-500"><.check /> Read the form as it stands</li>
          <li class="flex items-center gap-2 text-gray-500"><.check /> Sent your description</li>
          <li class="flex items-start gap-2">
            <span class="loading loading-spinner loading-xs mt-0.5 text-primary" />
            <span>
              <span class="block font-medium text-gray-900">Writing the elements</span>
              <span class="block text-xs text-gray-500">
                The long part — a form of a dozen questions takes about half a minute.
              </span>
            </span>
          </li>
          <li class="flex items-center gap-2 text-gray-400">
            <span class="size-4 rounded-full border border-zinc-300" />
            Checking the builder can show them
          </li>
        </ol>
      </.bordered_box>
      <.waiting_footer />
    </.card>
    """
  end

  def steps_panel(%{variant: :timings} = assigns) do
    ~H"""
    <.card>
      <.chrome_head />
      <.prompt_box text={prompt()} dim />
      <.bordered_box class="mt-3">
        <ol class="space-y-2 text-sm">
          <li
            :for={{label, state, time} <- timed_steps()}
            class={["flex items-center gap-2", step_text(state)]}
          >
            <.check :if={state == :done} />
            <span :if={state == :running} class="loading loading-spinner loading-xs text-primary" />
            <span :if={state == :pending} class="size-4 rounded-full border border-zinc-300" />
            <span class={state == :running && "font-medium text-gray-900"}>{label}</span>
            <span class="ml-auto font-mono text-xs tabular-nums text-gray-400">{time}</span>
          </li>
        </ol>
      </.bordered_box>
      <.waiting_footer />
    </.card>
    """
  end

  def steps_panel(%{variant: :instead_of_prompt} = assigns) do
    ~H"""
    <.card>
      <.chrome_head />
      <.bordered_box>
        <p class="mb-3 px-1 text-base font-medium text-gray-900">Building your form</p>
        <.steps class="px-1 pb-1" />
      </.bordered_box>
      <.waiting_footer />
    </.card>
    """
  end

  def steps_panel(%{variant: :beside_skeleton} = assigns) do
    ~H"""
    <.card>
      <.chrome_head />
      <.bordered_box class="mt-3">
        <div class="grid gap-4 sm:grid-cols-[minmax(0,1fr)_minmax(0,1.1fr)]">
          <.steps />
          <div class="space-y-3 border-zinc-200 sm:border-l sm:pl-4">
            <div :for={width <- ~w(w-24 w-32 w-20)} class="space-y-1.5">
              <div class={["h-2.5 rounded bwa-shimmer", width]} />
              <div class="h-8 w-full rounded bwa-shimmer" />
            </div>
          </div>
        </div>
      </.bordered_box>
      <.waiting_footer />
    </.card>
    """
  end

  def steps_panel(%{variant: :plain_border} = assigns) do
    ~H"""
    <.card>
      <.chrome_head />
      <.prompt_box text={prompt()} dim />
      <.bordered_box class="mt-3" tone={:plain}><.steps /></.bordered_box>
      <.waiting_footer />
    </.card>
    """
  end

  def steps_panel(%{variant: :quiet_steps} = assigns) do
    ~H"""
    <.card>
      <.chrome_head />
      <.prompt_box text={prompt()} dim />
      <.bordered_box class="mt-3">
        <ol class="space-y-2 text-sm">
          <li class="text-gray-400">Read the form as it stands</li>
          <li class="text-gray-400">Sent your description</li>
          <li class="bwa-sweep -mx-1 rounded px-1 font-medium text-gray-900">Writing the elements</li>
          <li class="text-gray-400">Checking the builder can show them</li>
        </ol>
      </.bordered_box>
      <.waiting_footer />
    </.card>
    """
  end

  def steps_panel(%{variant: :done} = assigns) do
    ~H"""
    <.card>
      <.chrome_head />
      <.prompt_box text={prompt()} />
      <.bordered_box class="mt-3" tone={:done}>
        <ol class="space-y-2 text-sm text-gray-500">
          <li :for={label <- step_labels()} class="flex items-center gap-2">
            <.check /> {label}
          </li>
        </ol>
      </.bordered_box>
      <div class="mt-3 flex flex-wrap items-center justify-between gap-3">
        <p class="text-sm text-gray-600">
          <span class="font-medium text-gray-900">Built in 0:26.</span>
          Four questions, open in the form builder below — nothing is saved yet.
        </p>
        <span class="btn">Build again</span>
      </div>
    </.card>
    """
  end

  def steps_panel(%{variant: :failed} = assigns) do
    ~H"""
    <.card>
      <.chrome_head />
      <.prompt_box text={prompt()} />
      <.bordered_box class="mt-3" tone={:failed}>
        <ol class="space-y-2 text-sm">
          <li class="flex items-center gap-2 text-gray-500"><.check /> Read the form as it stands</li>
          <li class="flex items-center gap-2 text-gray-500"><.check /> Sent your description</li>
          <li class="flex items-center gap-2 font-medium text-error">
            <svg viewBox="0 0 20 20" fill="currentColor" class="size-4" aria-hidden="true">
              <path
                fill-rule="evenodd"
                d="M10 18a8 8 0 1 0 0-16 8 8 0 0 0 0 16ZM8.28 7.22a.75.75 0 1 0-1.06 1.06L8.94 10l-1.72 1.72a.75.75 0 1 0 1.06 1.06L10 11.06l1.72 1.72a.75.75 0 1 0 1.06-1.06L11.06 10l1.72-1.72a.75.75 0 0 0-1.06-1.06L10 8.94 8.28 7.22Z"
                clip-rule="evenodd"
              />
            </svg>
            Writing the elements
          </li>
        </ol>
      </.bordered_box>
      <div class="mt-3 flex flex-wrap items-center justify-between gap-3">
        <p class="text-sm text-error">
          The answer was too long to finish. Ask for a smaller change.
        </p>
        <span class="btn btn-primary">Build again</span>
      </div>
    </.card>
    """
  end

  # The panel itself is the page's ordinary white card. Direction 12's moving
  # border went around the steps rather than around the whole thing: the
  # panel is not what is working, the steps are, and a border that wraps the
  # prompt and the heading too says the whole editor is busy.
  slot(:inner_block, required: true)

  defp card(assigns) do
    ~H"""
    <div class="rounded-lg border border-zinc-200 bg-white p-4">{render_slot(@inner_block)}</div>
    """
  end

  attr(:tone, :atom, default: :building, doc: ":building, :done, :failed, or :plain")
  attr(:class, :string, default: nil)
  slot(:inner_block, required: true)

  defp bordered_box(assigns) do
    ~H"""
    <div class={[
      "rounded-xl p-[2px]",
      @class,
      @tone == :building && "bwa-border",
      @tone == :done && "bg-primary/40",
      @tone == :failed && "bg-error/50",
      @tone == :plain && "bg-zinc-200"
    ]}>
      <div class="rounded-[10px] bg-white p-3">{render_slot(@inner_block)}</div>
    </div>
    """
  end

  attr(:class, :string, default: "")

  defp steps(assigns) do
    ~H"""
    <ol class={["space-y-2 text-sm", @class]}>
      <li class="flex items-center gap-2 text-gray-500"><.check /> Read the form as it stands</li>
      <li class="flex items-center gap-2 text-gray-500"><.check /> Sent your description</li>
      <li class="flex items-center gap-2 font-medium text-gray-900">
        <span class="loading loading-spinner loading-xs text-primary" /> Writing the elements
      </li>
      <li class="flex items-center gap-2 text-gray-400">
        <span class="size-4 rounded-full border border-zinc-300" /> Checking the builder can show them
      </li>
    </ol>
    """
  end

  # The way out, and nothing else. The running step carries its own clock
  # (`timed_steps/0`), so a total in the corner would be the same number
  # twice — and the one number an admin wants while they wait is how long
  # *this* step has been going, not how long the panel has been open.
  defp waiting_footer(assigns) do
    ~H"""
    <div class="mt-3 flex">
      <span class="btn ml-auto">Cancel</span>
    </div>
    """
  end

  defp step_labels,
    do: [
      "Read the form as it stands",
      "Sent your description",
      "Wrote the elements",
      "Checked the builder can show them"
    ]

  defp numbered_steps,
    do: [
      {"Read the form", 1, :done},
      {"Sent your description", 2, :done},
      {"Writing the elements", 3, :running},
      {"Checking the builder", 4, :pending}
    ]

  defp timed_steps,
    do: [
      {"Read the form as it stands", :done, "0:00"},
      {"Sent your description", :done, "0:01"},
      {"Writing the elements", :running, "0:13"},
      {"Checking the builder can show them", :pending, "—"}
    ]

  defp step_text(:done), do: "text-gray-500"
  defp step_text(:running), do: "text-gray-900"
  defp step_text(:pending), do: "text-gray-400"

  # -- Shared pieces ---------------------------------------------------------

  slot(:inner_block, required: true)

  defp chrome(assigns) do
    ~H"""
    <div class="rounded-lg border border-zinc-200 bg-white p-4">
      <.chrome_head />
      {render_slot(@inner_block)}
    </div>
    """
  end

  defp chrome_head(assigns) do
    ~H"""
    <h4 class="text-lg font-bold text-gray-900">Build with AI</h4>
    <p class="mb-3 text-sm text-gray-500">
      Use AI to build new form elements or edit existing ones.
    </p>
    """
  end

  attr(:text, :string, required: true)
  attr(:dim, :boolean, default: false)

  defp prompt_box(assigns) do
    ~H"""
    <div class={[
      "min-h-24 w-full rounded-md border border-zinc-300 bg-white p-3 text-sm text-gray-700",
      @dim && "opacity-60"
    ]}>
      {@text}
    </div>
    """
  end

  defp check(assigns) do
    ~H"""
    <svg viewBox="0 0 20 20" fill="currentColor" class="size-4 text-primary" aria-hidden="true">
      <path
        fill-rule="evenodd"
        d="M16.704 4.153a.75.75 0 0 1 .143 1.052l-8 10.5a.75.75 0 0 1-1.127.075l-4.5-4.5a.75.75 0 0 1 1.06-1.06l3.894 3.893 7.48-9.817a.75.75 0 0 1 1.05-.143Z"
        clip-rule="evenodd"
      />
    </svg>
    """
  end

  attr(:class, :string, default: "size-5")

  defp sparkle(assigns) do
    ~H"""
    <svg viewBox="0 0 24 24" fill="currentColor" class={@class} aria-hidden="true">
      <path d="M12 2.5l1.6 4.6 4.6 1.6-4.6 1.6L12 15l-1.6-4.7L5.8 8.7l4.6-1.6L12 2.5Z" />
      <path d="M18.5 14l.9 2.6 2.6.9-2.6.9-.9 2.6-.9-2.6-2.6-.9 2.6-.9.9-2.6Z" opacity=".7" />
      <path d="M5.5 14.5l.7 2 2 .7-2 .7-.7 2-.7-2-2-.7 2-.7.7-2Z" opacity=".5" />
    </svg>
    """
  end

  @doc """
  The keyframes the directions above use, scoped to this page by a `bwa-`
  prefix. Written here rather than in `app.css` because none of it has been
  chosen yet — whatever wins moves into the library's own markup, and the
  rest goes away with this section.
  """
  def styles(assigns) do
    ~H"""
    <style>
      @keyframes bwa-indeterminate {
        0%   { transform: translateX(-110%); }
        100% { transform: translateX(410%); }
      }
      .bwa-indeterminate { animation: bwa-indeterminate 1.4s ease-in-out infinite; }

      @keyframes bwa-shimmer-bg {
        0%   { background-position: 150% 0; }
        100% { background-position: -150% 0; }
      }
      .bwa-shimmer {
        background-image: linear-gradient(90deg,
          oklch(92% 0.004 286.32) 0%,
          oklch(97% 0.002 286.32) 50%,
          oklch(92% 0.004 286.32) 100%);
        background-size: 250% 100%;
        animation: bwa-shimmer-bg 1.8s linear infinite;
      }

      @keyframes bwa-sweep {
        0%   { background-position: 150% 0; }
        100% { background-position: -150% 0; }
      }
      .bwa-sweep {
        background-image: linear-gradient(100deg,
          transparent 35%,
          color-mix(in oklch, var(--color-primary) 12%, transparent) 50%,
          transparent 65%);
        background-size: 250% 100%;
        animation: bwa-sweep 2.2s linear infinite;
      }

      @keyframes bwa-border-move {
        0%   { background-position: 0% 50%; }
        100% { background-position: 200% 50%; }
      }
      .bwa-border {
        background-image: linear-gradient(90deg, #4f46e5, #7c3aed, #c026d3, #7c3aed, #4f46e5);
        background-size: 200% 100%;
        animation: bwa-border-move 3s linear infinite;
      }

      @keyframes bwa-cycle {
        0%         { opacity: 0; transform: translateY(4px); }
        4%, 32%    { opacity: 1; transform: none; }
        36%, 100%  { opacity: 0; transform: translateY(-4px); }
      }
      /* Base opacity 1 so a still of the page — a screenshot, a browser with
         animations off — shows the first line rather than an empty box; the
         animation takes the property over the moment it runs. */
      .bwa-cycle { animation: bwa-cycle 6s ease-in-out infinite; }
      .bwa-cycle:not(:first-of-type) { opacity: 0; }

      @keyframes bwa-arrive {
        0%, 8%    { opacity: 0; transform: translateY(6px); }
        18%, 92%  { opacity: 1; transform: none; }
        100%      { opacity: 0; transform: translateY(-2px); }
      }
      .bwa-arrive { animation: bwa-arrive 3.2s ease-in-out infinite; }

      @keyframes bwa-blink { 0%, 49% { opacity: 1; } 50%, 100% { opacity: 0; } }
      .bwa-blink { animation: bwa-blink 1s step-end infinite; }

      @keyframes bwa-bar {
        0%, 100% { height: 25%; }
        50%      { height: 100%; }
      }
      .bwa-bar { height: 25%; animation: bwa-bar 1s ease-in-out infinite; }

      @keyframes bwa-dot {
        0%, 100% { opacity: .2; transform: scale(.7); }
        50%      { opacity: 1; transform: scale(1); }
      }
      .bwa-dot { animation: bwa-dot 1.4s ease-in-out infinite; }

      @keyframes bwa-ellipsis {
        0%   { content: ""; }
        25%  { content: "."; }
        50%  { content: ".."; }
        75%  { content: "..."; }
      }
      .bwa-ellipsis::after { content: "..."; animation: bwa-ellipsis 1.6s steps(1) infinite; }

      @media (prefers-reduced-motion: reduce) {
        .bwa-indeterminate, .bwa-shimmer, .bwa-sweep, .bwa-border, .bwa-cycle,
        .bwa-arrive, .bwa-blink, .bwa-bar, .bwa-dot, .bwa-ellipsis::after {
          animation: none;
        }
        .bwa-cycle:first-of-type, .bwa-arrive { opacity: 1; }
        .bwa-cycle:not(:first-of-type) { display: none; }
      }
    </style>
    """
  end
end
