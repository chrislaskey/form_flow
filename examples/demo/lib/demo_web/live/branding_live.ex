defmodule DemoWeb.BrandingLive do
  @moduledoc """
  Scratch page for trying `Layouts.logo_mark` as an actual logo — solid vs.
  gradient strokes, on light and dark — and, below that, directions for the
  demo's user switcher (see `DemoWeb.BrandingLive.UserSwitchers`).

  Mounted on `live "/branding", BrandingLive`.
  """

  use DemoWeb, :live_view

  alias DemoWeb.BrandingLive.UserSwitchers

  # The two lists are kept in matching order so the light/dark columns line
  # up row for row.
  @logo_variations_light [
    %{label: "Solid black, on white", box1: "#111827", box2: "#111827"},
    %{
      label: "Brand gradient (both boxes), on white",
      box1: "url(#grad-brand)",
      box2: "url(#grad-brand)"
    },
    %{
      label: "Black + fuchsia/purple gradient (gradient in front), on white",
      box1: "#111827",
      box2: "url(#grad-fuchsia-purple)"
    },
    %{
      label: "Black + fuchsia/purple gradient (gradient behind), on white",
      box1: "#111827",
      box2: "url(#grad-fuchsia-purple)",
      front: :box1
    },
    %{
      label: "Fuchsia/purple gradient + black, reversed (black in front), on white",
      box1: "url(#grad-fuchsia-purple)",
      box2: "#111827"
    },
    %{
      label: "Fuchsia/purple gradient + black, reversed (gradient in front), on white",
      box1: "url(#grad-fuchsia-purple)",
      box2: "#111827",
      front: :box1
    },
    %{
      label: "Black + brand gradient (gradient in front), on white",
      box1: "#111827",
      box2: "url(#grad-brand)"
    },
    %{
      label: "Black + brand gradient (gradient behind), on white",
      box1: "#111827",
      box2: "url(#grad-brand)",
      front: :box1
    },
    %{
      label: "Brand gradient + black, reversed (black in front), on white",
      box1: "url(#grad-brand)",
      box2: "#111827"
    },
    %{
      label: "Brand gradient + black, reversed (gradient in front), on white",
      box1: "url(#grad-brand)",
      box2: "#111827",
      front: :box1
    },
    %{
      label: "Fuchsia/purple gradient (both boxes), on white",
      box1: "url(#grad-fuchsia-purple)",
      box2: "url(#grad-fuchsia-purple)"
    }
  ]

  @logo_variations_dark [
    %{label: "Solid white, on black", box1: "#ffffff", box2: "#ffffff"},
    %{
      label: "Brand gradient (both boxes), on black",
      box1: "url(#grad-brand)",
      box2: "url(#grad-brand)"
    },
    %{
      label: "White + fuchsia/purple gradient (gradient in front), on black",
      box1: "#ffffff",
      box2: "url(#grad-fuchsia-purple)"
    },
    %{
      label: "White + fuchsia/purple gradient (gradient behind), on black",
      box1: "#ffffff",
      box2: "url(#grad-fuchsia-purple)",
      front: :box1
    },
    %{
      label: "Fuchsia/purple gradient + white, reversed (white in front), on black",
      box1: "url(#grad-fuchsia-purple)",
      box2: "#ffffff"
    },
    %{
      label: "Fuchsia/purple gradient + white, reversed (gradient in front), on black",
      box1: "url(#grad-fuchsia-purple)",
      box2: "#ffffff",
      front: :box1
    },
    %{
      label: "White + brand gradient (gradient in front), on black",
      box1: "#ffffff",
      box2: "url(#grad-brand)"
    },
    %{
      label: "White + brand gradient (gradient behind), on black",
      box1: "#ffffff",
      box2: "url(#grad-brand)",
      front: :box1
    },
    %{
      label: "Brand gradient + white, reversed (white in front), on black",
      box1: "url(#grad-brand)",
      box2: "#ffffff"
    },
    %{
      label: "Brand gradient + white, reversed (gradient in front), on black",
      box1: "url(#grad-brand)",
      box2: "#ffffff",
      front: :box1
    },
    %{
      label: "Fuchsia/purple gradient (both boxes), on black",
      box1: "url(#grad-fuchsia-purple)",
      box2: "url(#grad-fuchsia-purple)"
    }
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Branding")
     |> assign(:logo_variations_light, @logo_variations_light)
     |> assign(:logo_variations_dark, @logo_variations_dark)
     |> assign(:directions, UserSwitchers.directions())
     |> assign(:selected, %{})
     |> assign(:menus_open, false)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :menus_open, params["menus"] == "open")}
  end

  @impl true
  def handle_event("toggle_menus", _params, socket) do
    {:noreply, update(socket, :menus_open, &(!&1))}
  end

  @impl true
  def handle_event("select", %{"direction" => direction, "user" => user}, socket) do
    {:noreply, update(socket, :selected, &Map.put(&1, direction, user))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="space-y-6">
        <header class="space-y-2">
          <h1 class="text-2xl font-semibold">Logo experiments</h1>
          <p class="text-base-content/70">
            Trying <code>Layouts.logo_mark</code>
            as an actual logo — solid vs. gradient strokes, on light and dark.
          </p>
        </header>

        <svg width="0" height="0" style="position: absolute" aria-hidden="true">
          <defs>
            <linearGradient id="grad-brand" x1="0" y1="0" x2="1" y2="1">
              <stop offset="0%" stop-color="#4f46e5" />
              <stop offset="50%" stop-color="#7c3aed" />
              <stop offset="100%" stop-color="#c026d3" />
            </linearGradient>
            <linearGradient id="grad-fuchsia-purple" x1="0" y1="0" x2="1" y2="1">
              <stop offset="0%" stop-color="#c026d3" />
              <stop offset="100%" stop-color="#7e22ce" />
            </linearGradient>
          </defs>
        </svg>

        <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <div class="flex flex-col gap-3">
            <div :for={v <- @logo_variations_dark} class="flex flex-col gap-3 bg-black p-6">
              <div class="flex items-center gap-2">
                <Layouts.logo_mark
                  class="size-8"
                  box1={v.box1}
                  box2={v.box2}
                  front={Map.get(v, :front, :box2)}
                />
                <span class="text-lg font-semibold text-white">FormFlow</span>
              </div>
              <p class="text-xs text-white/50">{v.label}</p>
            </div>
          </div>

          <div class="flex flex-col gap-3">
            <div
              :for={v <- @logo_variations_light}
              class="flex flex-col gap-3 border border-gray-200 bg-white p-6"
            >
              <div class="flex items-center gap-2">
                <Layouts.logo_mark
                  class="size-8"
                  box1={v.box1}
                  box2={v.box2}
                  front={Map.get(v, :front, :box2)}
                />
                <span class="text-lg font-semibold text-gray-900">FormFlow</span>
              </div>
              <p class="text-xs text-gray-500">{v.label}</p>
            </div>
          </div>
        </div>

        <section class="space-y-8 border-t border-gray-200 pt-10">
          <header class="space-y-2">
            <h2 class="text-2xl font-semibold">User switcher directions</h2>
            <p class="text-base-content/70">
              The control that picks which hardcoded perspective the demo is viewed
              from. Each direction is shown in a mock header and again in page
              content. Selecting only updates the mock; the real one sets a session
              cookie and reloads.
            </p>
            <label class="inline-flex items-center gap-2 text-sm text-gray-700">
              <input
                type="checkbox"
                class="checkbox checkbox-sm checkbox-primary"
                checked={@menus_open}
                phx-click="toggle_menus"
              /> Show the header menus open
            </label>
          </header>

          <div :for={d <- @directions} class={["space-y-3", @menus_open && "pb-72"]}>
            <div class="flex flex-wrap items-baseline gap-x-3 gap-y-1">
              <h3 class="font-semibold text-gray-900">{d.title}</h3>
              <p class="text-sm text-gray-500">{d.note}</p>
            </div>

            <.mock_header>
              <:right :if={d.id != :banner_strip}>
                <UserSwitchers.switcher
                  direction={d.id}
                  id={"#{d.id}-header"}
                  current={current(@selected, d.id, @current_user)}
                  open={@menus_open}
                />
              </:right>
              <:strip :if={d.id == :banner_strip}>
                <UserSwitchers.switcher
                  direction={d.id}
                  id={"#{d.id}-header"}
                  current={current(@selected, d.id, @current_user)}
                  open={@menus_open}
                />
              </:strip>
            </.mock_header>

            <div class="rounded-xl border border-dashed border-gray-300 bg-gray-50/60 px-6 py-5">
              <div class="flex flex-wrap items-center justify-between gap-4">
                <div>
                  <h4 class="font-semibold text-gray-900">Pet licenses</h4>
                  <p class="text-sm text-gray-500">
                    In page content, the same component next to what it changes.
                  </p>
                </div>
                <UserSwitchers.switcher
                  direction={d.id}
                  id={"#{d.id}-content"}
                  current={current(@selected, d.id, @current_user)}
                  align={:end}
                />
              </div>
            </div>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end

  # The real header from `Layouts.app`, with a `:right` slot after the nav
  # and a `:strip` slot for a full-width row beneath it.
  slot :right
  slot :strip

  defp mock_header(assigns) do
    ~H"""
    <div class="overflow-visible rounded-xl border border-gray-200 bg-gray-100 p-4">
      <header class="w-full rounded-lg bg-white shadow-sm">
        <div class="h-1 w-full rounded-t-lg bg-gradient-to-r from-indigo-600 via-violet-600 to-fuchsia-600 opacity-50" />
        <div class="flex items-center justify-between gap-6 p-6 px-8">
          <span class="flex items-center gap-2 text-lg font-semibold text-gray-900">
            <Layouts.logo_mark class="size-8" box1="#111827" box2="url(#grad-brand)" front={:box1} />
            FormFlow
          </span>
          <div class="flex items-center gap-4">
            <nav class="flex items-center gap-1 text-sm font-medium">
              <span class="rounded-lg bg-gray-100 px-3 py-2 font-semibold text-indigo-600">Home</span>
              <span class="rounded-lg px-3 py-2 text-gray-600">Install Check</span>
              <span class="rounded-lg px-3 py-2 text-gray-600">Admin</span>
              <span class="rounded-lg px-3 py-2 text-gray-600">Users</span>
            </nav>
            <div :if={@right != []} class="flex items-center border-l border-gray-200 pl-4">
              {render_slot(@right)}
            </div>
          </div>
        </div>
        {render_slot(@strip)}
        <div class="h-3 rounded-b-lg" />
      </header>
    </div>
    """
  end

  # Direction 20 is the real component, so it shows the real current user.
  defp current(_selected, :built, current_user), do: current_user

  defp current(selected, direction, _current_user) do
    UserSwitchers.user(Map.get(selected, to_string(direction), "dog_owner"))
  end
end
