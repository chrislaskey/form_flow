defmodule FormFlow.Web.Instances.Forms.Edit do
  @moduledoc """
  `FormFlow.Web.Instances.Forms.Edit` LiveComponent renders one position of a
  flow instance as the real, fillable form — the pinned version's definition
  through `DynamicForm`, prefilled with any answers already in `data`.

  It is the counterpart of `FormFlow.Web.Instances.Forms.Show`, which renders
  the same answers read-only: `/flows/:id/forms/*path/edit` is this page,
  `/flows/:id/forms/*path` is that one. Both are addressed by position and
  resolve it the same way (`FormFlow.Web.Instances.Forms.Shared`).

  What is only true here: **this is the page that starts a form.** A
  position with no instance yet gets one created on mount — which is the
  moment the form version is pinned — gated by the flow type's `editable?/2`
  the flow instance's page asks before offering the link. Starting is
  idempotent afterwards, so this URL is an ordinary link from everywhere and
  survives a refresh or a Back — and a form the type gates can't be started
  by typing its URL.

  An already-submitted position renders no form at all: its answers live at
  Show, which is also where Reopen is, so there is exactly one place that
  renders answers read-only and exactly one that reopens them.

  Submitting writes the answers and marks the instance completed
  (`FormFlow.Data.Instances.Forms.update_status/4`), then asks the flow's
  type where to go (`on_complete/2`): the next form of this flow, or — when
  it has none left — the next actionable position anywhere in the flow
  instance, which is what carries a user out of a finished subflow and into
  the next. It navigates to that position's own URL here, which does the
  starting; with nothing actionable left, back to the flow instance's page.

  DynamicForm's default success message targets the parent LiveView's
  `handle_info/2` — the host's process, not ours — so `on_success` routes the
  payload back into this component via `send_update`, and the redirect happens
  in `handle_async` (redirects are forbidden inside `update/2`).
  """

  use Phoenix.LiveComponent

  alias FormFlow.Data.Instances
  alias FormFlow.Data.Instances.FlowProgress
  alias FormFlow.Data.Instances.FormProgress
  alias FormFlow.Data.Templates
  alias FormFlow.Web.Instances.Components
  alias FormFlow.Web.Instances.Forms.Shared
  alias FormFlow.Web.Instances.Paths

  @impl true
  def update(%{event: "submitted", payload: payload}, socket) do
    %{flow_instance: flow_instance, form_instance: form_instance} = socket.assigns

    case Instances.Forms.update_status(flow_instance, form_instance.path, :completed,
           data: payload.data,
           user_id: socket.assigns.user_id
         ) do
      {:ok, _completed} ->
        to = next_destination(flow_instance, socket.assigns)
        {:ok, start_async(socket, :navigate, fn -> to end)}

      {:error, _changeset} ->
        {:ok, assign(socket, :error, "Could not save the form. Please try again.")}
    end
  end

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
  def handle_async(:navigate, {:ok, to}, socket) do
    {:noreply, push_navigate(socket, to: to)}
  end

  defp load(%{assigns: %{flow_instance_id: flow_instance_id}} = socket) do
    case Instances.Flows.get(flow_instance_id) do
      nil ->
        assign(socket, :flow_instance, nil)

      flow_instance ->
        socket
        |> assign(:flow_instance, flow_instance)
        |> Shared.assigns(start: true)
    end
  end

  # After submit: where the user goes, as a URL. Nothing is started here —
  # the page that addresses a position is the one that starts it.
  defp next_destination(flow_instance, assigns) do
    case next_path(flow_instance, assigns) do
      path when is_list(path) -> Paths.form_edit_path(assigns.base, flow_instance.id, path)
      nil -> Paths.flow_path(assigns.base, flow_instance.id)
    end
  end

  # The flow's type answers first — statuses derived fresh, so the form just
  # submitted counts as done — and the flow instance answers when that flow
  # has nothing left, carrying the user on to whatever follows it.
  defp next_path(flow_instance, assigns) do
    tree = Templates.Flows.resolve_tree(flow_instance.flow_id)
    forms = FlowProgress.forms(tree, Instances.Flows.form_instances(flow_instance))
    context = Shared.context(assigns, tree, forms)

    case assigns.type.module.on_complete(context, assigns.config_data) do
      %FormProgress{path: next} -> next
      nil -> Instances.Flows.next_path_position(flow_instance)
    end
  end

  defp submitted(payload, component_id) do
    Phoenix.LiveView.send_update(__MODULE__, %{
      id: component_id,
      event: "submitted",
      payload: payload
    })
  end

  @impl true
  def render(%{flow_instance: nil} = assigns) do
    ~H"""
    <p class="text-sm text-zinc-500">This flow no longer exists.</p>
    """
  end

  # Nothing to fill in: either the form could not be started, or the flow's
  # type does not allow editing here.
  def render(%{form_instance: nil} = assigns) do
    ~H"""
    <div>
      <Components.FormPage.breadcrumb
        base={@base}
        flow_instance={@flow_instance}
        flow_name={@flow_name}
        label={@form_label}
      />

      <Components.FormPage.notice message={blocked_message(assigns)}>
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

  # Already submitted, so there is nothing to edit until it is reopened —
  # which happens beside the answers, on Show.
  def render(%{form_instance: %{status: "completed"}} = assigns) do
    ~H"""
    <div>
      <Components.FormPage.breadcrumb
        base={@base}
        flow_instance={@flow_instance}
        flow_name={@flow_name}
        label={@form_label}
      />

      <Components.FormPage.notice message="This form has already been submitted.">
        <.link
          navigate={Paths.form_path(@base, @flow_instance.id, @path)}
          class="text-cyan-600 hover:underline"
        >
          View or reopen your answers →
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

      <div class="max-w-md">
        <DynamicForm.form
          id={"#{@id}-#{@form_instance.id}"}
          instance={@parsed}
          data={@form_instance.data}
          on_success={&submitted(&1, @id)}
        />
      </div>
    </div>
    """
  end

  defp blocked_message(%{start_error: message}) when is_binary(message), do: message
  defp blocked_message(%{form: nil}), do: "This form is not part of this flow."

  defp blocked_message(_assigns),
    do: "This form isn't available yet — it comes later in the flow."
end
