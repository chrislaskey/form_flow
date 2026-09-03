defmodule FormFlow.Web.Instances.Flows.Show do
  @moduledoc """
  `FormFlow.Web.Instances.Flows.Show` LiveComponent is one flow instance's
  detail page: every form in flow order with its derived state — Available /
  In progress / Done / Pending — plus any stranded answers (filled at a
  position the flow no longer has).

  Which forms appear, and which offer to start, is not this page's decision:
  each form belongs to a "forms" flow, and that flow's `FormFlow.Config.Flows.Type`
  answers `visible?/2` and `editable?/2` for it. A flow for another
  perspective is not listed at all; an in-order wizard offers only where the
  flow allows work; an any-order one offers every form of its own that isn't
  done, which is how a user jumps ahead. One instance can hold several
  "forms" flows with different types, so the questions are asked per form.
  When every form the viewer can see is done but the instance is not, the
  page says so: their part is finished, the rest is someone else's.

  Whether the page renders at all is the host config's to say
  (`FormFlow.Config.handle_instance_mount/2`, with the flow instance's context):
  refused, only its message is drawn; redirected, nothing is until the
  navigation lands.

  Every action here is an ordinary link, because a form's URL addresses its
  *position* and so exists before its instance row does — starting happens on
  the form page itself (see `FormFlow.Web.Instances.Forms.Show`). Reopen is
  the exception, since it changes state: it is a button, and it lives beside
  the answers it reopens.
  """

  use Phoenix.LiveComponent

  alias FormFlow.Config.Flows.Perspective
  alias FormFlow.Context
  alias FormFlow.Data.Instances
  alias FormFlow.Data.Instances.FlowProgress
  alias FormFlow.Data.Templates
  alias FormFlow.Web.Instances.Components
  alias FormFlow.Web.Instances.Forms.Shared
  alias FormFlow.Web.Instances.Paths

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:base, fn -> "" end)
      |> assign_new(:tenant_id, fn -> nil end)
      |> assign_new(:perspectives, fn -> [] end)
      |> assign_new(:config, fn -> nil end)
      |> assign_new(:config_data, fn -> %{} end)
      |> assign_new(:uri, fn -> nil end)
      |> assign_new(:params, fn -> %{} end)
      |> assign_new(:error, fn -> nil end)

    {:ok, load(socket)}
  end

  @impl true
  def handle_event("reopen", %{"path" => joined}, socket) do
    path = String.split(joined, ",")

    case Instances.Forms.update_status(socket.assigns.flow_instance, path, :in_progress,
           user_id: socket.assigns.user_id,
           tenant_id: socket.assigns.tenant_id
         ) do
      {:ok, _reopened} -> {:noreply, load(socket)}
      {:error, _reason} -> {:noreply, assign(socket, :error, "Could not reopen the form.")}
    end
  end

  @impl true
  def handle_async(:navigate, {:ok, to}, socket) do
    {:noreply, push_navigate(socket, to: to)}
  end

  defp load(%{assigns: %{flow_instance_id: flow_instance_id}} = socket) do
    case Instances.Flows.get(flow_instance_id) do
      nil ->
        assign(socket, flow_instance: nil, rows: [], stranded: [], flow_name: nil)

      flow_instance ->
        tree = Templates.Flows.resolve_tree(flow_instance.flow_id)
        forms = FlowProgress.forms(tree, Instances.Flows.form_instances(flow_instance))
        flow = tree && tree.flow

        # The page's own context — the flow instance as a whole, no form in
        # scope — for the host's config to answer handle_instance_mount/2 with
        context = %Context{
          user_id: socket.assigns.user_id,
          tenant_id: socket.assigns.tenant_id,
          perspectives: Perspective.normalize(socket.assigns.perspectives),
          flow: flow,
          subflow: flow,
          flow_type_property_values: FormFlow.Config.Flows.Type.property_values(flow),
          flow_instance: flow_instance,
          flow_instance_progress: forms
        }

        rows = rows(forms, tree, flow_instance, socket.assigns)

        socket =
          assign(socket,
            flow_instance: flow_instance,
            context: context,
            rows: rows,
            part_done?: part_done?(rows, flow_instance),
            stranded: Instances.Flows.list_stranded(flow_instance),
            flow_name: (flow && flow.name) || "Untitled flow",
            mount_error: nil,
            navigate_to: nil
          )

        Shared.handle_instance_mount(socket)
    end
  end

  # Every form the viewer's perspectives are for, with the one question its
  # own flow's type answers here — forms of a flow that is not for the viewer
  # are not rows at all.
  defp rows(forms, tree, flow_instance, assigns) do
    for form <- forms,
        context = form_context(form, forms, tree, flow_instance, assigns),
        type = Shared.flow_type(context, assigns),
        Shared.visible?(type, context, assigns) do
      %{form: form, editable?: type.module.editable?(context, assigns.config_data)}
    end
  end

  defp form_context(form, forms, tree, flow_instance, assigns) do
    context = %Context{
      user_id: assigns.user_id,
      tenant_id: assigns.tenant_id,
      perspectives: Perspective.normalize(assigns.perspectives),
      flow: tree.flow,
      subflow: form.flow,
      subflow_node: List.last(form.ancestors),
      flow_type_property_values: FormFlow.Config.Flows.Type.property_values(form.flow),
      flow_instance: flow_instance,
      form_progress: form,
      flow_progress: FlowProgress.forms_in_flow(forms, form.path),
      flow_instance_progress: forms
    }

    %Context{context | flow_perspectives: Shared.flow_perspectives(context, assigns)}
  end

  # The viewer's part is done when every form they can see is completed and
  # the instance as a whole is not — what remains is someone else's
  defp part_done?(rows, flow_instance) do
    rows != [] and flow_instance.status != "completed" and
      Enum.all?(rows, &(&1.form.status == :completed))
  end

  @impl true
  def render(%{flow_instance: nil} = assigns) do
    ~H"""
    <p class="text-sm text-zinc-500">This flow no longer exists.</p>
    """
  end

  # The host's config is sending the user elsewhere: nothing to draw meanwhile
  def render(%{navigate_to: to} = assigns) when is_binary(to) do
    ~H"""
    <div></div>
    """
  end

  # The host's config refused the page; its message is all there is to draw
  def render(%{mount_error: message} = assigns) when is_binary(message) do
    ~H"""
    <div>
      <div class="mb-2 text-sm font-semibold">
        <.link navigate={Paths.flows_path(@base)} class="hover:underline">Flows</.link>
        <span class="text-zinc-400">/</span>
        {@flow_name}
      </div>

      <Components.FormPage.notice message={@mount_error}>
        <.link navigate={Paths.flows_path(@base)} class="text-cyan-600 hover:underline">
          Back to flows
        </.link>
      </Components.FormPage.notice>
    </div>
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

      <p :if={@rows == []} class="mb-4 text-sm text-zinc-500">
        Nothing in this flow is for you to fill out.
      </p>

      <div
        :if={@part_done?}
        class="mb-4 rounded-md border border-emerald-200 bg-emerald-50 px-3 py-2 text-xs text-emerald-800"
      >
        Your part is done. The rest of this flow is being worked on by others.
      </div>

      <ul class="space-y-1.5 text-sm">
        <li :for={row <- @rows} class="flex items-center gap-3">
          <% {text, classes} = Components.Flows.Progress.badge(row.form.status) %>
          <span class={"rounded-full border px-2 py-0.5 text-xs #{classes}"}>{text}</span>
          <span>{FlowProgress.qualified_label(row.form)}</span>
          <span class="ml-auto flex items-center gap-2">
            <%!-- Start is the offer to begin work here — an any-order wizard
                  makes it on forms an in-order one keeps closed. A form
                  already started continues instead; both land on the same
                  page, which is the one that starts the form. --%>
            <.link
              :if={row.editable? && is_nil(row.form.instance)}
              navigate={Paths.form_edit_path(@base, @flow_instance.id, row.form.path)}
              class="rounded-md border border-zinc-300 px-2 py-0.5 text-xs hover:border-zinc-400"
            >
              Start
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
