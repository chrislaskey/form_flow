defmodule DemoWeb.ReadmeLive do
  @moduledoc """
  The demo index: renders FormFlow's optional path-based router and documents
  what each of FormFlow's dependencies needs at install time.

  Mounted on the `/*path` catch-all so `FormFlow.Web.Router` receives the
  remaining path segments and dispatches on them.
  """

  use DemoWeb, :live_view

  @modules [
    {FormFlow, "Top-level module and shared documentation"},
    {FormFlow.Data, "Backend and data code: templates and instances"},
    {FormFlow.Data.Repo, "Wrapper around the parent app's Ecto repo"},
    {FormFlow.Web, "UI, UX, presentation, and web code"},
    {FormFlow.Web.Router, "Optional path-based router for `*path` catch-all routes"}
  ]

  @requirements [
    %{
      library: "form_flow",
      needs: "Colocated hooks, Tailwind @source, a repo, a migration, an asset route",
      where:
        "assets/js/app.js, assets/css/app.css, config/config.exs, priv/repo/migrations, router.ex"
    },
    %{
      library: "phoenix_select",
      needs: "Colocated hooks, Tailwind @source",
      where: "assets/js/app.js, assets/css/app.css"
    },
    %{
      library: "slab",
      needs: "Colocated hooks, Tailwind @source, a repo for query mode",
      where: "assets/js/app.js, assets/css/app.css, config/config.exs"
    },
    %{
      library: "dynamic_form",
      needs:
        "Tailwind @source, daisyUI (vendored by phx.new 1.8+), a JS uploader for file fields",
      where: "assets/css/app.css, assets/js/app.js"
    }
  ]

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "FormFlow demo")
     |> assign(:version, to_string(Application.spec(:form_flow, :vsn)))
     |> assign(:modules, Enum.map(@modules, fn {mod, doc} -> {inspect(mod), doc} end))
     |> assign(:requirements, @requirements)
     |> assign(:path, path(params))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
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
          <h2 class="text-lg font-semibold">Router</h2>
          <p class="text-sm text-base-content/70">
            This LiveView is mounted on <code>live "/*path", ReadmeLive</code>
            and hands the remaining path (<span class="font-mono">{@path}</span>)
            to FormFlow's optional router, which dispatches to the library's
            LiveComponents.
          </p>
          <div>Navigate to:</div>
          <div class="flex justify-between gap-3">
            <.link navigate="/flows">Flows Index</.link>
            <.link navigate="/flows/new">Flows New</.link>
            <.link navigate="/forms">Forms Index</.link>
            <.link navigate="/forms/new">Forms New</.link>
          </div>
          <div id="form-flow-router" class="rounded-lg border border-base-300 p-4">
            <FormFlow.Web.router type="templates" user_id="demo-admin" path={@path} />
          </div>
          <p class="text-sm text-base-content/70">
            <.link navigate={~p"/admin"} class="link">/admin</.link>
            has a dedicated page, <code>DemoWeb.FormFlowLive.Admin</code>, where the same
            FormFlow router — mounted with <code>base="/admin"</code> — serves a
            landing plus the flows and forms CRUD LiveComponents at
            <code>/admin/flows</code> and <code>/admin/forms</code>. The
            ReactFlow editor's ~390 KB bundle is fetched from the <code>form_flow_assets()</code>
            route on those pages only — it is not
            in <code>app.js</code>.
          </p>
        </section>

        <section class="space-y-3">
          <h2 class="text-lg font-semibold">Install requirements</h2>
          <p class="text-sm text-base-content/70">
            Apps declare only <code>form_flow</code>; phoenix_select,
            dynamic_form, and slab come along as dependencies. Each still needs
            its own wiring, all of it applied by <code>examples/regenerate.sh</code>:
          </p>
          <div class="overflow-x-auto">
            <table id="install-requirements" class="table table-sm">
              <thead>
                <tr>
                  <th>Library</th>
                  <th>Needs</th>
                  <th>In this app</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={requirement <- @requirements}>
                  <td class="font-mono whitespace-nowrap">{requirement.library}</td>
                  <td>{requirement.needs}</td>
                  <td class="font-mono text-xs">{requirement.where}</td>
                </tr>
              </tbody>
            </table>
          </div>
          <p class="text-sm text-base-content/70">
            <.link navigate={~p"/install-check"} class="link">
              Install check
            </.link>
            renders a component from each library, so a broken hook, missing
            Tailwind source, or absent daisyUI shows up immediately.
          </p>
        </section>

        <section class="space-y-3">
          <h2 class="text-lg font-semibold">Library modules</h2>
          <ul id="form-flow-modules" class="space-y-1">
            <li :for={{name, doc} <- @modules} class="text-sm">
              <span class="font-mono">{name}</span>
              <span class="text-base-content/70">— {doc}</span>
            </li>
          </ul>
        </section>
      </div>
    </Layouts.app>
    """
  end

  # FormFlow.Web.Router takes a path string; the `*path` glob gives segments
  defp path(%{"path" => segments}) when is_list(segments), do: "/" <> Enum.join(segments, "/")
  defp path(_params), do: "/"
end
