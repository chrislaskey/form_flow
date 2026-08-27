defmodule FormFlow.Web.Instances.Flows.Show do
  @moduledoc """
  `FormFlow.Web.Instances.Flows.Show` LiveComponent is a journey's detail page:
  every form in flow order with its derived state — Available / In progress /
  Done / Pending — plus any stranded answers (filled at a position the flow no
  longer has).

  Which forms offer to open is not this page's decision: each form belongs to
  a "forms" flow, and that flow's `FormFlow.Flows.Types` module answers
  `openable?/2` for it. An in-order wizard offers only where the flow allows
  work; an any-order one offers every form of its own that isn't done, which
  is how a filler jumps ahead. One journey can hold several "forms" flows
  with different types, so the question is asked per form.

  Opening a form is what creates its instance
  (`FormFlow.Web.Instances.Positions.open/3` — create-on-open, which is the
  moment the form version is pinned) before navigating to the fill page.
  Reopen is the same call on a Done form: `:in_progress` on a completed
  instance sends it back.
  """

  use Phoenix.LiveComponent

  alias FormFlow.Config.Context
  alias FormFlow.Data.Instances
  alias FormFlow.Data.Instances.FlowProgress
  alias FormFlow.Data.Templates
  alias FormFlow.Flows.Types
  alias FormFlow.Web.Instances.Components
  alias FormFlow.Web.Instances.Positions

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:base, fn -> "" end)
      |> assign_new(:config, fn -> nil end)
      |> assign_new(:config_data, fn -> %{} end)
      |> assign_new(:error, fn -> nil end)

    {:ok, load(socket)}
  end

  @impl true
  def handle_event("open_form", %{"path" => joined}, socket) do
    journey = socket.assigns.journey
    path = String.split(joined, ",")

    case Positions.open(journey, path, socket.assigns.user_id) do
      {:ok, instance} ->
        to = "#{socket.assigns.base}/journeys/#{journey.id}/instances/#{instance.id}"
        {:noreply, push_navigate(socket, to: to)}

      {:error, message} ->
        {:noreply, assign(socket, :error, message)}
    end
  end

  def handle_event("reopen", %{"path" => joined}, socket) do
    path = String.split(joined, ",")

    case Instances.Forms.update_status(socket.assigns.journey, path, :in_progress,
           user_id: socket.assigns.user_id
         ) do
      {:ok, _reopened} -> {:noreply, load(socket)}
      {:error, _reason} -> {:noreply, assign(socket, :error, "Could not reopen the form.")}
    end
  end

  defp load(%{assigns: %{journey_id: journey_id}} = socket) do
    case Instances.Flows.get(journey_id) do
      nil ->
        assign(socket, journey: nil, rows: [], stranded: [], flow_name: nil)

      journey ->
        tree = Templates.Flows.resolve_tree(journey.flow_id)
        forms = FlowProgress.forms(tree, Instances.Flows.form_instances(journey))

        assign(socket,
          journey: journey,
          rows: rows(forms, tree, socket.assigns),
          stranded: Instances.Flows.list_stranded(journey),
          flow_name: (tree && tree.flow.name) || "Untitled flow"
        )
    end
  end

  # Every form with the one question its own flow's type answers here.
  defp rows(forms, tree, assigns) do
    for form <- forms do
      in_flow = FlowProgress.forms_in_flow(forms, form.path)
      type = type_module(assigns, tree, form)

      %{form: form, openable?: type.openable?(form, in_flow)}
    end
  end

  # The form's flow type: its "forms" flow's stored form_flow_type, resolved
  # through the host's FormFlow.Config (or the library's defaults).
  defp type_module(assigns, tree, form) do
    context = %Context{
      user_id: assigns.user_id,
      flow: tree.flow,
      subflow: form.flow,
      subflow_node: List.last(form.ancestors)
    }

    Types.for_flow(form.flow, context, assigns.config, assigns.config_data)
  end

  @impl true
  def render(%{journey: nil} = assigns) do
    ~H"""
    <p class="text-sm text-zinc-500">This journey no longer exists.</p>
    """
  end

  def render(assigns) do
    ~H"""
    <div>
      <div class="mb-2 text-sm font-semibold">
        <.link navigate={"#{@base}/journeys"} class="hover:underline">Journeys</.link>
        <span class="text-zinc-400">/</span>
        {@flow_name}
        <span
          :if={@journey.status == "completed"}
          class="ml-2 rounded-full border border-emerald-200 bg-emerald-50 px-2 py-0.5 text-xs text-emerald-700"
        >
          Completed
        </span>
      </div>

      <p :if={@error} class="mb-2 text-xs text-red-600">{@error}</p>

      <ul class="space-y-1.5 text-sm">
        <li :for={row <- @rows} class="flex items-center gap-3">
          <% {text, classes} = Components.FlowProgress.badge(row.form.status) %>
          <span class={"rounded-full border px-2 py-0.5 text-xs #{classes}"}>{text}</span>
          <span>{FlowProgress.qualified_label(row.form)}</span>
          <span class="ml-auto flex items-center gap-2">
            <%!-- Open is the offer to start work here — an any-order wizard
                  makes it on forms an in-order one keeps closed. A form
                  already started continues instead. --%>
            <button
              :if={row.openable? && is_nil(row.form.instance)}
              phx-click="open_form"
              phx-value-path={Enum.join(row.form.path, ",")}
              phx-target={@myself}
              class="rounded-md border border-zinc-300 px-2 py-0.5 text-xs hover:border-zinc-400"
            >
              Open
            </button>
            <.link
              :if={row.form.status == :in_progress && row.form.instance}
              navigate={"#{@base}/journeys/#{@journey.id}/instances/#{row.form.instance.id}"}
              class="text-cyan-600 hover:underline"
            >
              Continue →
            </.link>
            <.link
              :if={row.form.status == :completed && row.form.instance}
              navigate={"#{@base}/journeys/#{@journey.id}/instances/#{row.form.instance.id}"}
              class="text-cyan-600 hover:underline"
            >
              View →
            </.link>
            <button
              :if={row.form.status == :completed && row.form.instance}
              phx-click="reopen"
              phx-value-path={Enum.join(row.form.path, ",")}
              phx-target={@myself}
              class="rounded-md border border-zinc-300 px-2 py-0.5 text-xs hover:border-zinc-400"
            >
              Reopen
            </button>
          </span>
        </li>
      </ul>

      <div
        :if={@stranded != []}
        class="mt-4 rounded-md border border-amber-300 bg-amber-50 px-3 py-2 text-xs text-amber-800"
      >
        {length(@stranded)} answer set(s) were filled at positions this flow no longer has.
        An administrator can resolve them.
      </div>
    </div>
    """
  end
end
