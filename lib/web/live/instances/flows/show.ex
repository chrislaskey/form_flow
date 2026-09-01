defmodule FormFlow.Web.Instances.Flows.Show do
  @moduledoc """
  `FormFlow.Web.Instances.Flows.Show` LiveComponent is one flow instance's
  detail page: every form in flow order with its derived state — Available /
  In progress / Done / Pending — plus any stranded answers (filled at a
  position the flow no longer has).

  A form offers to open where the flow allows work — its predecessors done,
  or itself already started
  (`FormFlow.Data.Instances.Flows.Progress.actionable?/1`).

  Every action here is an ordinary link, because a form's URL addresses its
  *position* and so exists before its instance row does — opening happens on
  the form page itself (see `FormFlow.Web.Instances.Forms.Show`). Reopen is
  the exception, since it changes state: it is a button, and it lives beside
  the answers it reopens.
  """

  use Phoenix.LiveComponent

  alias FormFlow.Data.Instances
  alias FormFlow.Data.Instances.Flows.Progress
  alias FormFlow.Data.Templates
  alias FormFlow.Web.Instances.Components
  alias FormFlow.Web.Instances.Paths

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:base, fn -> "" end)
      |> assign_new(:error, fn -> nil end)

    {:ok, load(socket)}
  end

  @impl true
  def handle_event("reopen", %{"path" => joined}, socket) do
    path = String.split(joined, ",")

    case Instances.Forms.update_status(socket.assigns.flow_instance, path, :in_progress,
           user_id: socket.assigns.user_id
         ) do
      {:ok, _reopened} -> {:noreply, load(socket)}
      {:error, _reason} -> {:noreply, assign(socket, :error, "Could not reopen the form.")}
    end
  end

  defp load(%{assigns: %{flow_instance_id: flow_instance_id}} = socket) do
    case Instances.Flows.get(flow_instance_id) do
      nil ->
        assign(socket, flow_instance: nil, rows: [], stranded: [], flow_name: nil)

      flow_instance ->
        tree = Templates.Flows.resolve_tree(flow_instance.flow_id)
        forms = Progress.forms(tree, Instances.Flows.form_instances(flow_instance))

        assign(socket,
          flow_instance: flow_instance,
          rows: rows(forms),
          stranded: Instances.Flows.list_stranded(flow_instance),
          flow_name: (tree && tree.flow.name) || "Untitled flow"
        )
    end
  end

  defp rows(forms) do
    for form <- forms, do: %{form: form, openable?: Progress.actionable?(form)}
  end

  @impl true
  def render(%{flow_instance: nil} = assigns) do
    ~H"""
    <p class="text-sm text-zinc-500">This flow no longer exists.</p>
    """
  end

  def render(assigns) do
    ~H"""
    <div>
      <div class="mb-2 text-sm font-semibold">
        <.link navigate={Paths.flows_path(@base)} class="hover:underline">Flows</.link>
        <span class="text-zinc-400">/</span>
        {@flow_name}
        <span
          :if={@flow_instance.status == "completed"}
          class="ml-2 rounded-full border border-emerald-200 bg-emerald-50 px-2 py-0.5 text-xs text-emerald-700"
        >
          Completed
        </span>
      </div>

      <p :if={@error} class="mb-2 text-xs text-red-600">{@error}</p>

      <ul class="space-y-1.5 text-sm">
        <li :for={row <- @rows} class="flex items-center gap-3">
          <% {text, classes} = Components.Flows.Progress.badge(row.form.status) %>
          <span class={"rounded-full border px-2 py-0.5 text-xs #{classes}"}>{text}</span>
          <span>{Progress.qualified_label(row.form)}</span>
          <span class="ml-auto flex items-center gap-2">
            <%!-- Open is the offer to start work here. A form already
                  started continues instead; both land on the same page,
                  which is the one that opens the position. --%>
            <.link
              :if={row.openable? && is_nil(row.form.instance)}
              navigate={Paths.form_edit_path(@base, @flow_instance.id, row.form.path)}
              class="rounded-md border border-zinc-300 px-2 py-0.5 text-xs hover:border-zinc-400"
            >
              Open
            </.link>
            <.link
              :if={row.form.status == :in_progress && row.form.instance}
              navigate={Paths.form_edit_path(@base, @flow_instance.id, row.form.path)}
              class="text-cyan-600 hover:underline"
            >
              Continue →
            </.link>
            <.link
              :if={row.form.status == :completed && row.form.instance}
              navigate={Paths.form_path(@base, @flow_instance.id, row.form.path)}
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
