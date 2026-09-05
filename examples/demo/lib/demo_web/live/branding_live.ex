defmodule DemoWeb.BrandingLive do
  @moduledoc """
  Scratch page for trying `Layouts.logo_mark` as an actual logo — solid vs.
  gradient strokes, on light and dark — before settling on one look.

  Mounted on `live "/branding", BrandingLive`.
  """

  use DemoWeb, :live_view

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
     |> assign(:logo_variations_dark, @logo_variations_dark)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
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
      </div>
    </Layouts.app>
    """
  end
end
