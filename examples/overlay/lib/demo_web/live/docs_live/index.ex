defmodule DemoWeb.DocsLive.Index do
  @moduledoc """
  `/docs` — the front door to the documentation, and what the header's Docs
  link points at.

  There is nothing to list by hand: the pages come from
  `DemoWeb.DocsComponents.pages/0`, the same list the left nav is drawn
  from, so a page added there appears here without this module changing.
  """

  use DemoWeb, :live_view

  import DemoWeb.DocsComponents
  import DemoWeb.PageComponents

  alias DemoWeb.DocsComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Docs")
     |> assign(:current_nav, :docs)
     |> assign(:pages, DocsComponents.pages())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_nav={@current_nav} current_user={@current_user}>
      <.docs_layout current={:index}>
        <.h1>Docs</.h1>

        <.p>
          How FormFlow is put together, written for someone deciding whether
          it fits their application.
        </.p>

        <ul id="docs-index" class="max-w-5xl space-y-3">
          <li :for={page <- @pages}>
            <.link
              navigate={page.path}
              class="block rounded-lg border border-base-300 p-4 hover:border-base-content/30 hover:bg-base-200"
            >
              <div class="font-semibold">{page.title}</div>
              <div class="mt-1 text-base-content/70">{page.description}</div>
            </.link>
          </li>
        </ul>
      </.docs_layout>
    </Layouts.app>
    """
  end
end
