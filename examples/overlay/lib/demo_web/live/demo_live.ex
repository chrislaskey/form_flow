defmodule DemoWeb.DemoLive do
  @moduledoc """
  `/demo` — the front door to the demo application: who to read it as, the
  three sides of it, and the control that puts its data back.

  The header's Demo app menu points here. The menu opens on hover and lists
  the same three experiences, so this page is what a click gets you rather
  than a second way to reach the same links — somewhere to read what each side
  of the demo is before choosing one.

  The experiences come from `DemoWeb.Experiences`, the same list the menu is
  drawn from, so one added there appears here without this module changing.
  They are named here by kind first — "User pages", "Reviewer pages" — with
  the name they carry in the pet licensing service beside it, because this
  page explains the demo to the people trying it rather than posing as the
  service's own front door.
  """

  use DemoWeb, :live_view

  import DemoWeb.DemoDataComponents
  import DemoWeb.PageComponents
  import DemoWeb.PersonaComponents

  alias DemoWeb.Experiences

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Demo app")
     |> assign(:current_nav, :demo)
     |> assign(:experiences, Experiences.all())}
  end

  @impl true
  def handle_event("reset_demo", _params, socket) do
    {:noreply, handle_reset(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_nav={@current_nav} current_user={@current_user}>
      <div class="max-w-3xl space-y-10">
        <header class="space-y-2">
          <.h1>Demo app</.h1>

          <.p class="text-base-content/70">
            A pet licensing service built with FormFlow: the flows and forms behind
            it, the applications people file against them, and the reviews that
            decide them. Each side of it is a page of its own.
          </.p>
        </header>

        <.h3>Choose a user</.h3>

        <.pick_perspective
          id="perspective"
          current_user={@current_user}
          blurb="Each page below is for particular users, and refuses the others.
                 The demo opens as the admin, who can see every one of them;
                 switch here or in the header to read a page as someone else."
        />

        <.h3>Explore the demo app</.h3>

        <ul id="demo-experiences" class="max-w-5xl space-y-3">
          <li :for={experience <- @experiences}>
            <.link
              navigate={experience.path}
              class="block rounded-lg border border-base-300 p-4 hover:border-base-content/30 hover:bg-base-200"
            >
              <div class="font-semibold">{Experiences.overview_title(experience)}</div>
              <div class="mt-1 text-base-content/70">{experience.blurb}</div>
            </.link>
          </li>
        </ul>

        <.h2>Advanced settings</.h2>

        <.reset_demo_data current_user={@current_user} />
      </div>
    </Layouts.app>
    """
  end
end
