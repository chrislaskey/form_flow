defmodule DemoWeb.IntroductionComponents do
  @moduledoc """
  The README's introduction, as components: the tagline, why FormFlow models
  forms as data, how far an app can customize it, what it takes to use it, and
  where its licensing stands.

  Two pages open with this prose — the demo index at `/` and
  `/docs/introduction` — so it is written once here and headed by each of
  them in its own way: the index with plain headings, the docs page with the
  anchored sections its nav links to. Neither owns the words.

  The README is the canonical copy. When it changes, this module changes with
  it, and both pages follow.
  """

  use DemoWeb, :html

  import DemoWeb.PageComponents

  # The README's GIFs. GitHub reads them out of examples/; the demo serves the
  # same files from priv/static, copied in by examples/regenerate.sh. Named
  # here once so a page asks for a screenshot by what it shows.
  @screenshots %{
    overview: %{
      file: "screenshot-overview-v0.26.0.gif",
      alt: "Building a flow in the FormFlow admin UI, from the flow overview to the form editor"
    },
    health: %{
      file: "screenshot-health-v0.26.0.gif",
      alt: "The health page listing the problems found in a flow, and the flow being fixed"
    }
  }

  @doc """
  One of the README's screenshots, held to the width of the prose beside it.

  The GIFs are wide and long-running, so they are decoded lazily and left to
  scale rather than cropped.
  """
  attr :name, :atom, required: true, values: Map.keys(@screenshots)
  attr :class, :string, default: nil

  def screenshot(assigns) do
    assigns = assign(assigns, :screenshot, Map.fetch!(@screenshots, assigns.name))

    ~H"""
    <img
      src={~p"/images/#{@screenshot.file}"}
      alt={@screenshot.alt}
      loading="lazy"
      class={["w-full max-w-5xl rounded-lg border border-gray-300", @class]}
    />
    """
  end

  @doc """
  The one-line description of the library, set off the way the README's
  blockquote sets it off.
  """
  attr :class, :string, default: nil

  def tagline(assigns) do
    ~H"""
    <p class={[
      "mt-6 max-w-5xl border-l-4 border-gray-300 pl-4 text-xl text-base-content/70",
      @class
    ]}>
      Batteries included library for creating dynamic form-based user flows in
      Phoenix. Use drag-and-drop UIs to build complex user journeys. Reliable,
      verifiable, and deterministic results.
    </p>
    """
  end

  @doc "Why forms as data, rather than forms as code."
  def why_form_flow(assigns) do
    ~H"""
    <.p>
      Web apps are great for building forms. Creating an individual form in code is
      easier than ever, especially using LLM based tools. <strong>But there's a problem</strong>. The more complex the flow gets, the
      harder and harder it is to maintain and ensure things are working correctly
      for users as they move from one flow to the next.
    </.p>

    <.p>
      FormFlow solves this problem by approaching things differently. Rather than
      creating forms as code, it writes <strong>forms as data</strong>. In fact,
      the library stores the entire journey (which we call the flow) in data.
    </.p>

    <.p>
      Using data also means it is easy to change. With drag-and-drop functionality,
      FormFlow makes it fast to get started building flows. But more importantly, it
      <strong>stays easy to manage even as the complexity grows</strong>
      across multiple forms, multiple user types, and beyond.
    </.p>

    <.p>
      The best part about data is it's much easier to check for potential issues
      that cause problems for users. And by using data, we can be certain all the
      forms and flows work consistently using the same rules no matter how complex
      the business case is you're tackling.
    </.p>

    <.p>
      FormFlow has a built-in health check that makes it easy to spot potential
      issues before it reaches users:
    </.p>

    <.screenshot name={:health} />
    """
  end

  @doc "What a data-driven library gives back when an app needs to depart from it."
  def how_easy_is_it_to_customize(assigns) do
    ~H"""
    <.p>
      Storing flows and forms in data means everything is stable and consistent.
      It's great for things to be uniform, but what if you need to customize
      something? This is a common problem, and often times data-driven systems are
      rigid.
    </.p>

    <.p>
      When creating FormFlow, true, easy to use, flexible <strong>customization is built into the core of its design</strong>,
      and not an afterthought.
    </.p>

    <.p>
      Almost everything is customizable, from the flow logic to the detailed
      rendering. All of it is customized using standard Elixir and Phoenix code.
      No macro DSL language to learn. Simple changes can be done with
      well-documented component attributes. More complex customization can be done
      by passing Elixir modules with custom callback implementations.
    </.p>

    <.p>
      Nothing's worse than a library that doesn't feel like a part of the existing
      app. So when it comes to UI/UX, it supports your existing application's
      CoreComponents, so everything from icons to error states in field inputs is
      native to your app.
    </.p>
    """
  end

  @doc "What FormFlow is built on, and how an application takes it on."
  def how_do_i_use_it(assigns) do
    ~H"""
    <.p>
      FormFlow is built as an Elixir library. It's compatible with any modern
      Phoenix LiveView application. It supports both <strong>SQLite and PostgreSQL</strong>
      for the database layer. While not required, it also has <strong>optional Neo4J</strong>
      graph database support that makes it even more efficient, especially for
      complex workflows.
    </.p>

    <.p>
      If you have an existing Phoenix LiveView application, it's easy to install the
      library as a mix.exs dependency and fits into the existing application.
    </.p>

    <.p>
      If you don't use Phoenix for your main app, don't worry! FormFlow can be
      deployed as a standalone app by wrapping it in Phoenix.
    </.p>
    """
  end

  @doc "Where the library's licensing stands while it is being built."
  def licensing(assigns) do
    ~H"""
    <.p>
      Licensing is still to be determined, as the library is actively being built.
      For now it's all rights reserved. So I would not recommend building a business
      on top of it without talking to me first. For now code is available to
      reference, but not for reuse. See LICENSE.md for specifics.
    </.p>
    """
  end
end
