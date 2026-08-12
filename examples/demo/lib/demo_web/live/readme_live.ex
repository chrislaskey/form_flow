defmodule DemoWeb.ReadmeLive do
  @moduledoc """
  The demo index: confirms the FormFlow path dependency is wired up and lists
  the demos as they land.

  Right now this page only *references* FormFlow — it reads the compiled
  library's version and module structure. The next iteration renders
  `FormFlow.Web.router/1` on its own route.
  """

  use DemoWeb, :live_view

  @modules [
    {FormFlow, "Top-level module and shared documentation"},
    {FormFlow.Data, "Backend and data code: templates and instances"},
    {FormFlow.Data.Repo, "Wrapper around the parent app's Ecto repo"},
    {FormFlow.Web, "UI, UX, presentation, and web code"},
    {FormFlow.Web.Router, "Optional path-based router for `*path` catch-all routes"}
  ]

  @next_up ~S"""
  scope "/", DemoWeb do
    pipe_through :browser

    live "/templates/*path", TemplatesLive
  end

  # in TemplatesLive's template
  <FormFlow.Web.router type="templates" path={@path} app="demo" />
  """

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "FormFlow demo")
     |> assign(:version, to_string(Application.spec(:form_flow, :vsn)))
     |> assign(:params, params)
     |> assign(:modules, Enum.map(@modules, fn {mod, doc} -> {inspect(mod), doc} end))
     |> assign(:next_up, @next_up)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <FormFlow.Web.router type="templates" path={@params["path"]} />

      <div class="space-y-10">
        <header class="space-y-2">
          <h1 class="text-2xl font-semibold">FormFlow demo</h1>
          <p class="text-base-content/70">
            Batteries included library for creating dynamic form-based user flows
            in Phoenix. This app depends on FormFlow as a path dependency, so
            edits to <code>../../lib</code> show up here on reload.
          </p>
          <p class="text-sm text-base-content/70">
            Compiled version: <span id="form-flow-version" class="font-mono">{@version}</span>
          </p>
        </header>

        <section class="space-y-3">
          <h2 class="text-lg font-semibold">Library modules</h2>
          <ul id="form-flow-modules" class="space-y-1">
            <li :for={{name, doc} <- @modules} class="text-sm">
              <span class="font-mono">{name}</span>
              <span class="text-base-content/70">— {doc}</span>
            </li>
          </ul>
        </section>

        <section class="space-y-3">
          <h2 class="text-lg font-semibold">Demos</h2>
          <p class="text-sm text-base-content/70">
            None yet. Each demo gets its own route and a LiveView in <code>examples/overlay/lib/demo_web/live/</code>.
          </p>
        </section>

        <section class="space-y-3">
          <h2 class="text-lg font-semibold">Next up</h2>
          <p class="text-sm text-base-content/70">
            Mounting the optional router, which dispatches to FormFlow's
            LiveComponents based on the path:
          </p>
          <pre
            phx-no-curly-interpolation
            class="overflow-x-auto rounded-lg bg-base-200 p-4 text-xs"
          ><code>{@next_up}</code></pre>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
