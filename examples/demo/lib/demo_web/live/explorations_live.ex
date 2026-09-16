defmodule DemoWeb.ExplorationsLive do
  @moduledoc """
  Index of the demo's design explorations: scratch pages where a piece of UI
  is drawn several ways side by side, so a direction can be picked by looking
  at it rather than by describing it.

  Each exploration is one page under `/explorations`, listed in
  `@explorations` here. Nothing on any of them is wired up — the data is
  hardcoded and the components are scratch copies, so picking a direction is
  a separate job from building it.

  Mounted on `live "/explorations", ExplorationsLive`.
  """

  use DemoWeb, :live_view

  @explorations [
    %{
      path: "/explorations/logo",
      title: "Logo marks",
      note: """
      `Layouts.logo_mark` as an actual logo — solid vs. gradient strokes,
      each variation on white and on black.
      """
    },
    %{
      path: "/explorations/user-switchers",
      title: "User switchers",
      note: """
      The control that picks which hardcoded perspective the demo is viewed
      from, in a mock header and again in page content.
      """
    },
    %{
      path: "/explorations/health-checks",
      title: "Health checks",
      note: """
      The trigger an admin sees for a flow's health, in four states, and the
      modal it opens.
      """
    },
    %{
      path: "/explorations/build-with-ai",
      title: "Build with AI",
      note: """
      The form editor's Build with AI panel in the twenty to sixty seconds
      between pressing Build and a form appearing.
      """
    },
    %{
      path: "/explorations/template-layout",
      title: "Template page layouts",
      note: """
      The chrome around a flow's or form's canvas: the header above it and
      the fact sheet below.
      """
    }
  ]

  @doc "Every exploration, in the order the index lists them."
  def explorations, do: @explorations

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Explorations")
     |> assign(:explorations, @explorations)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="space-y-6">
        <header class="space-y-2">
          <h1 class="text-2xl font-semibold">Explorations</h1>
          <p class="text-base-content/70">
            Scratch pages where one piece of the interface is drawn several ways
            at once, so a direction can be picked by looking at it. Everything on
            them is hardcoded and nothing is wired up.
          </p>
        </header>

        <ul class="divide-y divide-gray-200 border-y border-gray-200">
          <li :for={e <- @explorations}>
            <.link
              navigate={e.path}
              class="group flex items-baseline justify-between gap-6 py-4 hover:bg-gray-50"
            >
              <div class="space-y-1">
                <h2 class="font-semibold text-gray-900 group-hover:text-indigo-600">{e.title}</h2>
                <p class="text-sm text-gray-500">{e.note}</p>
              </div>
              <span class="font-mono text-xs text-gray-400">{e.path}</span>
            </.link>
          </li>
        </ul>
      </div>
    </Layouts.app>
    """
  end
end
