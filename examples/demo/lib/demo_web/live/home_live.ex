defmodule DemoWeb.HomeLive do
  @moduledoc """
  `/` — what the demo is, which user it is being viewed as, and the version
  of FormFlow it was compiled against.
  """

  use DemoWeb, :live_view

  alias DemoWeb.UserSwitcher

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "FormFlow demo")
     |> assign(:current_nav, :home)
     |> assign(:version, to_string(Application.spec(:form_flow, :vsn)))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_nav={@current_nav} current_user={@current_user}>
      <div class="space-y-10">
        <header class="space-y-2">
          <h1 class="text-2xl font-semibold">FormFlow demo</h1>
          <p class="text-base-content/70">
            Batteries included library for creating dynamic form-based user flows in Phoenix.
          </p>
        </header>

        <section
          id="perspective"
          class="flex flex items-center justify-between gap-4 rounded-xl border border-gray-300 px-6 py-5 max-w-5xl"
        >
          <div class="space-y-1">
            <h2 class="font-semibold text-gray-900">Pick a user perspective</h2>
            <p class="text-sm text-base-content/70">
              The demo is viewed as one of four hardcoded users, with no sign-in.
              Switch here or in the header; the page reloads as that user.
            </p>
          </div>
          <UserSwitcher.user_switcher id="perspective-user-switcher" current_user={@current_user} />
        </section>

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
