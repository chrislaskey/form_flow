defmodule DemoWeb.IntroductionComponents do
  @moduledoc """
  The README's introduction, as components: the tagline, why FormFlow models
  forms as data, and what it takes to use it.

  Two pages open with this prose — the demo index at `/` and
  `/docs/introduction` — so it is written once here and headed by each of
  them in its own way: the index with plain headings, the docs page with the
  anchored sections its nav links to. Neither owns the words.

  The README is the canonical copy. When it changes, this module changes with
  it, and both pages follow.
  """

  use DemoWeb, :html

  import DemoWeb.PageComponents

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
      Web apps are great for building forms. Coding an individual form is easier
      than ever, especially using LLM based tools. But the more complex the flow
      gets, the harder and harder it is to maintain and ensure things are working
      correctly for users as they move from one flow to the next.
    </.p>

    <.p>
      FormFlow solves this problem by approaching things differently. Rather than
      creating forms as code, it writes <strong>forms as data</strong>. In fact,
      the library stores the entire journey (which we call the flow) in data.
    </.p>

    <.p>
      The nice thing about data is it's much easier to check for potential issues
      that cause problems for users. And by using data, we can be certain all the
      forms and flows are rendered consistently using the same rules no matter how
      complex the business case is you're tackling.
    </.p>

    <.p>
      Another nice thing about data is it can be easily changed. With drag-and-drop
      functionality, FormFlow makes it fast to get started building flows. But more
      importantly, it stays easy to manage even as the complexity grows across
      multiple forms, multiple user types, and beyond.
    </.p>
    """
  end

  @doc "What FormFlow is built on, and how an application takes it on."
  def how_do_i_use_it(assigns) do
    ~H"""
    <.p>
      FormFlow is built as an Elixir library. It's compatible with any modern
      Phoenix LiveView application. It supports both SQLite and PostgreSQL for the
      database layer. While not required, it also has optional support for Neo4J
      that makes it even more efficient, especially for complex workflows.
    </.p>

    <.p>
      If you have an existing Phoenix LiveView application, it's easy to install as
      a dependency and click immediately into the existing application.
    </.p>

    <.p>
      If you don't use Phoenix for your main app, don't worry! FormFlow can be
      deployed as a standalone app easily.
    </.p>
    """
  end
end
