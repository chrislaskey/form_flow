defmodule DemoWeb.DocsLive.IntroductionLive do
  @moduledoc """
  `/docs/introduction` — the README's introduction, for a reader who reached
  the docs first.

  The prose is `DemoWeb.IntroductionComponents`', shared with the demo index,
  which opens with the same words. What this page adds is the docs' shape:
  each part is a `docs_section/1` the left nav jumps to, and the page hands
  the reader on to the rest of the documentation at the end.
  """

  use DemoWeb, :live_view

  import DemoWeb.DocsComponents
  import DemoWeb.IntroductionComponents
  import DemoWeb.PageComponents

  alias DemoWeb.DocsComponents

  # This page's table of contents, in page order. The docs nav lists these
  # under the page's entry and `docs_section/1` heads each one, so the nav
  # and the heading it jumps to cannot say different things.
  @sections [
    %{id: "why-form-flow", title: "Why FormFlow?"},
    %{id: "how-easy-is-it-to-customize", title: "How easy is it to customize?"},
    %{id: "how-do-i-use-it", title: "How do I use it?"},
    %{id: "how-is-form-flow-built", title: "How is FormFlow built?"},
    %{id: "licensing", title: "Licensing"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Introduction")
     |> assign(:current_nav, :docs)
     |> assign(:sections, @sections)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_nav={@current_nav} current_user={@current_user}>
      <.docs_layout current={:introduction} sections={@sections}>
        <.h1>Introduction</.h1>

        <.tagline />

        <.screenshot name={:overview} />

        <.docs_section {section("why-form-flow")}>
          <.why_form_flow />
        </.docs_section>

        <.docs_section {section("how-easy-is-it-to-customize")}>
          <.how_easy_is_it_to_customize />
        </.docs_section>

        <.docs_section {section("how-do-i-use-it")}>
          <.how_do_i_use_it />

          <.p>
            This demo is one of those applications. Its
            <.link navigate={~p"/"} class="link">index</.link>
            opens with these same words, and
            <.link navigate={~p"/docs/data-modeling"} class="link">Data modeling</.link>
            picks up where this page leaves off: the tables the flows are stored
            in, and the three ways they can be queried.
          </.p>
        </.docs_section>

        <.docs_section {section("how-is-form-flow-built")}>
          <.how_is_form_flow_built />
        </.docs_section>

        <.docs_section {section("licensing")}>
          <.licensing />
        </.docs_section>
      </.docs_layout>
    </Layouts.app>
    """
  end

  defp section(id), do: DocsComponents.fetch_section(@sections, id)
end
