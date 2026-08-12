defmodule DemoWeb.InstallCheckLive do
  @moduledoc """
  Renders one component from each library FormFlow depends on, so the
  installation steps are verifiable end to end rather than invisible config.

  What each section proves:

  - `PhoenixSelect.select` — the phoenix_select colocated hook is registered
    (without it the dropdown never opens) and its Tailwind source is scanned
  - `DynamicForm.form` — dynamic_form's Tailwind source is scanned and daisyUI
    is present, since its built-in components render daisyUI classes
  - `Slab.table` — the slab colocated hooks are registered (the Share tab's
    copy-to-clipboard button) and its Tailwind source is scanned

  Nothing here calls FormFlow itself; the index page does that.
  """

  use DemoWeb, :live_view

  @flows [
    %{id: 1, name: "Enrollment", status: "Published", updated_at: "2026-08-01"},
    %{id: 2, name: "Health check", status: "Draft", updated_at: "2026-08-04"},
    %{id: 3, name: "Tour request", status: "Published", updated_at: "2026-08-09"}
  ]

  @status_options [{"Published", "published"}, {"Draft", "draft"}, {"Archived", "archived"}]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Install check")
     |> assign(:flows, @flows)
     |> assign(:status_options, @status_options)
     |> assign(:form, to_form(%{"status" => "published"}, as: :install_check))}
  end

  @impl true
  def handle_params(params, uri, socket) do
    {:noreply, socket |> assign(:uri, uri) |> assign(:params, params)}
  end

  @impl true
  def handle_event("status_changed", %{"install_check" => params}, socket) do
    {:noreply, assign(socket, :form, to_form(params, as: :install_check))}
  end

  # DynamicForm messages the parent LiveView on every valid submission
  @impl true
  def handle_info({:dynamic_form, payload}, socket) do
    {:noreply, put_flash(socket, :info, "Submitted: #{inspect(payload.data)}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-10">
        <header class="space-y-2">
          <h1 class="text-2xl font-semibold">Install check</h1>
          <p class="text-base-content/70">
            One component from each library FormFlow depends on. If the hooks,
            Tailwind sources, and daisyUI are wired up correctly, everything
            below is styled and interactive.
          </p>
          <p class="text-sm">
            <.link navigate={~p"/"} class="link">Back to the index</.link>
          </p>
        </header>

        <section id="phoenix-select-check" class="space-y-3">
          <h2 class="text-lg font-semibold">phoenix_select</h2>
          <p class="text-sm text-base-content/70">
            The dropdown opens and filters through a colocated hook. Selected:
            <span id="selected-status" class="font-mono">
              {@form[:status].value}
            </span>
          </p>
          <.form for={@form} id="status-form" phx-change="status_changed">
            <PhoenixSelect.select
              id="status-select"
              field={@form[:status]}
              options={@status_options}
              label="Status"
            />
          </.form>
        </section>

        <section id="dynamic-form-check" class="space-y-3">
          <h2 class="text-lg font-semibold">dynamic_form</h2>
          <p class="text-sm text-base-content/70">
            Built-in components rendering daisyUI classes. Submitting a valid
            form messages this LiveView, which flashes the payload.
          </p>
          <DynamicForm.form id="contact-form" submit_text="Submit">
            <:field type="text" name="name" label="Name" required />
            <:field
              type="text"
              name="email"
              label="Email"
              input_type="email"
              format="email"
              required
            />
            <:field
              type="dropdown"
              name="reason"
              label="Reason"
              options={["Enrollment", "Tour", "Other"]}
            />
          </DynamicForm.form>
        </section>

        <section id="slab-check" class="space-y-3">
          <h2 class="text-lg font-semibold">slab</h2>
          <p class="text-sm text-base-content/70">
            Data mode over a hardcoded list. The Share tab's copy button runs
            through a colocated hook.
          </p>
          <Slab.table id="flows-table" data={@flows} uri={@uri} params={@params}>
            <:tab name="share" />
            <:column field={:name} />
            <:column field={:status} />
            <:column field={:updated_at} label="Updated" />
          </Slab.table>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
