defmodule FormFlow.Web.Instances.Forms.Show do
  @moduledoc """
  `FormFlow.Web.Instances.Forms.Show` LiveComponent renders the answers at one
  position of a flow instance, read-only — the pinned version's definition
  through `DynamicForm`, filled in with what is in `data`, every control
  disabled and no submit.

  It is the counterpart of `FormFlow.Web.Instances.Forms.Edit`, which is where
  work happens: `/flows/:id/forms/*path` is this page,
  `/flows/:id/forms/*path/edit` is that one. Both are addressed by position
  and resolve it the same way (`FormFlow.Web.Instances.Forms.Shared`); the
  difference is that this page never starts anything. With nothing filled in
  yet it says so and offers the link across to Edit, which does.

  The one write here is Reopen, and it lives here on purpose: reopening
  changes state, so it stays an explicit button rather than a mode of a URL,
  and it belongs beside the answers it reopens. It lands on Edit, where those
  answers can then be changed.
  """

  use Phoenix.LiveComponent

  alias FormFlow.Data.Instances
  alias FormFlow.Web.Instances.Components
  alias FormFlow.Web.Instances.Forms.Shared
  alias FormFlow.Web.Instances.Paths

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
  def handle_event("reopen", _params, socket) do
    %{flow_instance: flow_instance, form_instance: form_instance} = socket.assigns

    case Instances.Forms.update_status(flow_instance, form_instance.path, :in_progress,
           user_id: socket.assigns.user_id
         ) do
      {:ok, reopened} ->
        to = Paths.form_edit_path(socket.assigns.base, flow_instance.id, reopened.path)
        {:noreply, push_navigate(socket, to: to)}

      {:error, _changeset} ->
        {:noreply, assign(socket, :error, "Could not reopen the form.")}
    end
  end

  defp load(%{assigns: %{flow_instance_id: flow_instance_id}} = socket) do
    case Instances.Flows.get(flow_instance_id) do
      nil ->
        assign(socket, :flow_instance, nil)

      flow_instance ->
        socket
        |> assign(:flow_instance, flow_instance)
        |> Shared.assigns()
    end
  end

  @impl true
  def render(%{flow_instance: nil} = assigns) do
    ~H"""
    <p class="text-sm text-zinc-500">This flow no longer exists.</p>
    """
  end

  # Nothing filled in here yet, so there are no answers to show — only why,
  # and the way onward when there is one.
  def render(%{form_instance: nil} = assigns) do
    ~H"""
    <div>
      <Components.FormPage.breadcrumb
        base={@base}
        flow_instance={@flow_instance}
        flow_name={@flow_name}
        label={@form_label}
      />

      <Components.FormPage.notice message={unstarted_message(assigns)}>
        <.link
          :if={@editable?}
          navigate={Paths.form_edit_path(@base, @flow_instance.id, @path)}
          class="text-cyan-600 hover:underline"
        >
          Start this form →
        </.link>
        <.link
          navigate={Paths.flow_path(@base, @flow_instance.id)}
          class="text-cyan-600 hover:underline"
        >
          Back to the flow
        </.link>
      </Components.FormPage.notice>
    </div>
    """
  end

  def render(%{parse_error: error} = assigns) when is_binary(error) do
    ~H"""
    <div class="rounded-md border border-amber-300 bg-amber-50 px-3 py-2 text-xs text-amber-800">
      <p class="font-medium">This form can't be rendered.</p>
      <p class="mt-1 font-mono">{@parse_error}</p>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div>
      <Components.FormPage.breadcrumb
        base={@base}
        flow_instance={@flow_instance}
        flow_name={@flow_name}
        label={@form_label}
      />

      {@type.module.progress_component(%{
        id: "#{@id}-flow-progress",
        base: @base,
        flow_instance_id: @flow_instance.id,
        forms: @forms,
        current_path: @path,
        clickable: @clickable,
        context: @context,
        config_data: @config_data
      })}

      <p :if={@error} class="mb-2 text-xs text-red-600">{@error}</p>

      <div
        :if={@form_instance.status == "completed"}
        class="mb-3 flex items-center gap-3 rounded-md border border-emerald-300 bg-emerald-50 px-3 py-2 text-xs text-emerald-800"
      >
        <span>
          Submitted {Calendar.strftime(@form_instance.completed_at, "%Y-%m-%d %H:%M")} UTC.
        </span>
        <button
          phx-click="reopen"
          phx-target={@myself}
          class="rounded-md border border-emerald-300 px-2 py-0.5 hover:border-emerald-400"
        >
          Reopen
        </button>
      </div>

      <p :if={@form_instance.status != "completed"} class="mb-2 text-xs">
        <.link
          navigate={Paths.form_edit_path(@base, @flow_instance.id, @path)}
          class="text-cyan-600 hover:underline"
        >
          Continue filling this out →
        </.link>
      </p>

      <%!-- Read-only is the whole job of this page: the disabled fieldset
            switches off every control inside (a native HTML behavior) and the
            submit button is hidden. DynamicForm's render_only is NOT this —
            it is a parent-owns-the-form mode requiring a Phoenix.HTML.Form. --%>
      <fieldset disabled class="max-w-md">
        <DynamicForm.form
          id={"#{@id}-#{@form_instance.id}-#{@form_instance.status}"}
          instance={@parsed}
          data={@form_instance.data}
          hide_submit
        />
      </fieldset>
    </div>
    """
  end

  defp unstarted_message(%{form: nil}), do: "This form is not part of this flow."
  defp unstarted_message(%{editable?: true}), do: "You haven't started this form yet."

  defp unstarted_message(_assigns),
    do: "This form isn't available yet — it comes later in the flow."
end
