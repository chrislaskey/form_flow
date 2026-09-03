defmodule FormFlow.Web.Instances.Forms.Edit do
  @moduledoc """
  `FormFlow.Web.Instances.Forms.Edit` LiveComponent renders one position of a
  flow instance as the real, editable form — the pinned version's definition
  through `DynamicForm`, with the data the form's `FormFlow.Config.Forms.Type`
  supplies (`initial_data/2`: the stored answers by default, plus whatever a
  host's type prefills).

  It is the counterpart of `FormFlow.Web.Instances.Forms.Show`, which renders
  the same answers read-only: `/flows/:id/forms/*path/edit` is this page,
  `/flows/:id/forms/*path` is that one. Both are addressed by position and
  resolve it the same way (`FormFlow.Web.Instances.Forms.Shared`).

  What is only true here: **this is the page that starts a form.** A
  position with no instance yet gets one created on mount — which is the
  moment the form version is pinned — gated by the flow type's `editable?/2`
  the flow instance's page asks before offering the link, and by the host
  config's `handle_mount/2`, asked first: a refused or redirected visitor
  starts nothing. Starting is idempotent afterwards, so this URL is an
  ordinary link from everywhere and survives a refresh or a Back — and a form
  either gate can't be started by typing its URL.

  An already-submitted position renders no form at all: its answers live at
  Show, which is also where Reopen is, so there is exactly one place that
  renders answers read-only and exactly one that reopens them.

  Submitting asks the form's type what to record (`snapshot_data/2`),
  writes the answers and marks the instance completed with that record on
  its event (`FormFlow.Data.Instances.Forms.update_status/4`), then derives
  the flow instance's progress once more — the form just submitted now
  counts as done — into the one context both types' `handle_complete/2`
  receive. The form's type reacts to the completion; the flow's type says
  where to go: the next form of this flow, or — when it has none left — the
  next actionable position anywhere in the flow instance, which is what
  carries a user out of a finished subflow and into the next. It navigates to
  that position's own URL here, which does the starting; with nothing
  actionable left, back to the flow instance's page.

  Both callbacks are host code and neither crashes the page: a snapshot that
  raises refuses the submit with the page's error, the way a malformed
  definition is an inline error rather than a crash loop, and a reaction that
  raises is logged after a completion that stands.

  DynamicForm's default success message targets the parent LiveView's
  `handle_info/2` — the host's process, not ours — so `on_success` routes the
  payload back into this component via `send_update`, and the redirect happens
  in `handle_async` (redirects are forbidden inside `update/2`).
  """

  use Phoenix.LiveComponent

  require Logger

  alias FormFlow.Context
  alias FormFlow.Data.Instances
  alias FormFlow.Data.Instances.FlowProgress
  alias FormFlow.Data.Instances.FormProgress
  alias FormFlow.Data.Templates
  alias FormFlow.Web.Instances.Components
  alias FormFlow.Web.Instances.Forms.Shared
  alias FormFlow.Web.Instances.Paths

  @impl true
  def update(%{event: "submitted", payload: payload}, socket) do
    %{
      flow_instance: flow_instance,
      form_instance: form_instance,
      context: context,
      form_type: form_type,
      config_data: config_data
    } = socket.assigns

    with {:ok, snapshot} <- snapshot(form_type, context, config_data),
         {:ok, completed} <-
           Instances.Forms.update_status(flow_instance, form_instance.path, :completed,
             data: payload.data,
             user_id: socket.assigns.user_id,
             snapshot_data: snapshot
           ) do
      fresh = fresh_context(socket.assigns, completed)
      notify(form_type, fresh, config_data)
      to = next_destination(fresh, socket.assigns)
      {:ok, start_async(socket, :navigate, fn -> to end)}
    else
      {:error, _reason} ->
        {:ok, assign(socket, :error, "Could not save the form. Please try again.")}
    end
  end

  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:base, fn -> "" end)
      |> assign_new(:tenant_id, fn -> nil end)
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
        socket = socket |> assign(:flow_instance, flow_instance) |> Shared.assigns()

        Shared.handle_mount(socket, &Shared.start/1)
    end
  end

  # The form type's record of what it saw, taken before the write so a form
  # is never completed without it. Host code: an exception becomes the page's
  # error, never a crashed LiveView that loses what the user typed.
  defp snapshot(form_type, context, config_data) do
    case form_type.module.snapshot_data(context, config_data) do
      snapshot when is_map(snapshot) -> {:ok, snapshot}
      other -> {:error, {:not_a_map, other}}
    end
  rescue
    error -> {:error, error}
  end

  # The context after the write, derived once for both types' handle_complete/2:
  # the progress is fresh, so the form just submitted counts as done, and
  # `:form_instance` is the completed row. The template side is as at mount.
  defp fresh_context(%{flow_instance: flow_instance, context: context} = assigns, completed) do
    tree = Templates.Flows.resolve_tree(flow_instance.flow_id)
    forms = FlowProgress.forms(tree, Instances.Flows.form_instances(flow_instance))

    %Context{
      Shared.context(assigns, tree, forms)
      | form: context.form,
        form_version: context.form_version,
        form_type_property_values: context.form_type_property_values,
        form_instance: completed
    }
  end

  # The form type reacts after the fact. The completion is already written,
  # so an exception here is logged and the user carries on.
  defp notify(form_type, context, config_data) do
    form_type.module.handle_complete(context, config_data)
    :ok
  rescue
    error ->
      Logger.error(
        "#{inspect(form_type.module)}.handle_complete/2 raised after a completion: " <>
          Exception.format(:error, error, __STACKTRACE__)
      )

      :ok
  end

  # After submit: where the user goes, as a URL. Nothing is started here —
  # the page that addresses a position is the one that starts it.
  defp next_destination(%Context{flow_instance: flow_instance} = context, assigns) do
    case next_path(context, assigns) do
      path when is_list(path) -> Paths.form_edit_path(assigns.base, flow_instance.id, path)
      nil -> Paths.flow_path(assigns.base, flow_instance.id)
    end
  end

  # The flow's type answers first, and the flow instance answers when that
  # flow has nothing left, carrying the user on to whatever follows it.
  defp next_path(context, assigns) do
    case assigns.type.module.handle_complete(context, assigns.config_data) do
      %FormProgress{path: next} -> next
      nil -> Instances.Flows.next_path_position(context.flow_instance)
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
      <Components.FormPage.breadcrumb
        base={@base}
        flow_instance={@flow_instance}
        flow_name={@flow_name}
        label={@form_label}
      />

      <Components.FormPage.notice message={@mount_error}>
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

      <%!-- The form itself is the form type's to draw (edit_component/1) —
            the default is the DynamicForm form alone; a review draws an
            earlier form's answers beside it --%>
      {@form_type.module.edit_component(%{
        id: "#{@id}-#{@form_instance.id}",
        instance: @parsed,
        data: @initial_data,
        on_success: &submitted(&1, @id),
        context: @context,
        config_data: @config_data
      })}
    </div>
    """
  end

  defp blocked_message(%{start_error: message}) when is_binary(message), do: message
  defp blocked_message(%{form: nil}), do: "This form is not part of this flow."

  defp blocked_message(_assigns),
    do: "This form isn't available yet — it comes later in the flow."
end
