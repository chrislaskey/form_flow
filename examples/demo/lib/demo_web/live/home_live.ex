defmodule DemoWeb.HomeLive do
  @moduledoc """
  `/` — what FormFlow is and why it exists, which user the demo is being
  viewed as, the version it was compiled against, and — for the admin — the
  control that puts the demo's data back. The last two are
  `DemoWeb.DemoDataComponents`' and `DemoWeb.PersonaComponents`', shared with
  `/demo`, which offers the same pair.

  The prose is `DemoWeb.IntroductionComponents`', the README's introduction,
  shared with `/docs/introduction` so the two openings cannot drift apart.
  This page heads it with plain headings; the docs page heads it with the
  sections its nav jumps to.
  """

  use DemoWeb, :live_view

  import DemoWeb.DemoDataComponents
  import DemoWeb.IntroductionComponents
  import DemoWeb.PageComponents
  import DemoWeb.PersonaComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "FormFlow demo")
     |> assign(:current_nav, :home)
     |> assign(:version, to_string(Application.spec(:form_flow, :vsn)))}
  end

  @impl true
  def handle_event("reset_demo", _params, socket) do
    {:noreply, handle_reset(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_nav={@current_nav} current_user={@current_user}>
      <div class="space-y-10 max-w-4xl">
        <header class="space-y-2">
          <h1 class="text-2xl font-semibold">FormFlow</h1>
          <.tagline />
        </header>

        <.screenshot name={:overview} />

        <section id="why-form-flow" class="space-y-3">
          <.h2 class="mb-0">Why FormFlow?</.h2>
          <.why_form_flow />
        </section>

        <section id="how-easy-is-it-to-customize" class="space-y-3">
          <.h2 class="mb-0">How easy is it to customize?</.h2>

          <.how_easy_is_it_to_customize />
        </section>

        <section id="how-do-i-use-it" class="space-y-3">
          <.h2 class="mb-0">How do I use it?</.h2>

          <.how_do_i_use_it />

          <.p>
            This demo is one of those applications. The
            <.link navigate={~p"/docs/introduction"} class="link">docs</.link>
            cover how it is put together.
          </.p>
        </section>

        <section id="licensing" class="space-y-3">
          <.h2 class="mb-0">Licensing</.h2>

          <.licensing />
        </section>

        <.pick_perspective current_user={@current_user} />

        <.reset_demo_data current_user={@current_user} />

        <section>
          <p class="text-sm text-base-content/70">
            Compiled version: <span id="form-flow-version" class="font-mono">{@version}</span>
          </p>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
