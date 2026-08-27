defmodule FormFlow.Web.Instances.Forms.Show do
  @moduledoc """
  `FormFlow.Web.Instances.Forms.Show` LiveComponent renders one form instance as
  the real, fillable form — the pinned version's definition through
  `DynamicForm`, prefilled with any answers already in `data`.

  Above it sits the progress of the "forms" flow this form belongs to — its
  sibling forms and their state — unless there is only one, which is no
  sequence worth drawing. The flow's `FormFlow.Flows.Types` module decides
  both that and which of those forms the filler may jump to: none, for an
  in-order wizard; every form of its own that isn't done, for an any-order
  one.

  Submitting writes the answers and marks the instance completed
  (`FormFlow.Data.Instances.Forms.update_status/4`), then asks the same type
  where to go: the next form of this flow, or — when it has none left — the
  next actionable position anywhere in the journey, which is what carries a
  filler out of a finished subflow and into the next. Either way the
  destination is opened (create-on-open) and the user lands on it; with
  nothing actionable left, back to the journey page. A completed instance
  renders read-only with a Reopen button.

  DynamicForm's default success message targets the parent LiveView's
  `handle_info/2` — the host's process, not ours — so `on_success` routes
  the payload back into this component via `send_update`, and the redirect
  happens in `handle_async` (redirects are forbidden inside `update/2`).
  """

  use Phoenix.LiveComponent

  alias FormFlow.Config.Context
  alias FormFlow.Data.Instances
  alias FormFlow.Data.Instances.FlowProgress
  alias FormFlow.Data.Instances.FormProgress
  alias FormFlow.Data.Templates
  alias FormFlow.Flows.Types
  alias FormFlow.Web.Instances.Components
  alias FormFlow.Web.Instances.Positions

  @impl true
  def update(%{event: "submitted", payload: payload}, socket) do
    %{journey: journey, form_instance: form_instance} = socket.assigns

    case Instances.Forms.update_status(journey, form_instance.path, :completed,
           data: payload.data,
           user_id: socket.assigns.user_id
         ) do
      {:ok, _completed} ->
        to = next_destination(journey, socket.assigns)
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

  def handle_event("reopen", _params, socket) do
    %{journey: journey, form_instance: form_instance} = socket.assigns

    case Instances.Forms.update_status(journey, form_instance.path, :in_progress,
           user_id: socket.assigns.user_id
         ) do
      {:ok, _reopened} -> {:noreply, load(socket)}
      {:error, _changeset} -> {:noreply, assign(socket, :error, "Could not reopen the form.")}
    end
  end

  @impl true
  def handle_async(:navigate, {:ok, to}, socket) do
    {:noreply, push_navigate(socket, to: to)}
  end

  defp load(%{assigns: %{journey_id: journey_id, instance_id: instance_id}} = socket) do
    journey = Instances.Flows.get(journey_id)
    form_instance = Instances.Forms.get(instance_id)

    if is_nil(journey) or is_nil(form_instance) or form_instance.instance_flow_id != journey.id do
      assign(socket, journey: journey, form_instance: nil, parsed: nil, parse_error: nil)
    else
      version = Templates.Forms.get_version(form_instance.template_form_version_id)

      socket
      |> assign(journey: journey, form_instance: form_instance)
      |> assign_flow_progress(journey, form_instance)
      |> parse(version.definition)
    end
  end

  # The forms of the flow this one belongs to, and what its type makes of
  # them. Navigating to the form being filled would do nothing, so it is
  # never among the clickable ones — which is what leaves an in-order
  # wizard's progress entirely inert, the only form it opens being that one.
  defp assign_flow_progress(socket, journey, form_instance) do
    tree = Templates.Flows.resolve_tree(journey.flow_id)
    forms = FlowProgress.forms(tree, Instances.Flows.form_instances(journey))
    in_flow = FlowProgress.forms_in_flow(forms, form_instance.path)
    type = type_module(socket.assigns, tree, FlowProgress.find_form(forms, form_instance.path))

    clickable =
      for form <- in_flow,
          form.path != form_instance.path,
          type.openable?(form, in_flow),
          into: MapSet.new(),
          do: form.path

    assign(socket,
      forms: in_flow,
      show_progress?: type.show_progress?(in_flow),
      clickable: clickable
    )
  end

  # The form's flow type: its "forms" flow's stored form_flow_type, resolved
  # through the host's FormFlow.Config (or the library's defaults). A
  # stranded instance is no longer one of the tree's forms, so the journey's
  # own flow answers for it.
  defp type_module(assigns, tree, form) do
    flow = (form && form.flow) || (tree && tree.flow)

    context = %Context{
      user_id: assigns.user_id,
      flow: tree && tree.flow,
      subflow: flow,
      subflow_node: form && List.last(form.ancestors)
    }

    Types.for_flow(flow, context, assigns.config, assigns.config_data)
  end

  # A definition is admin-authored input — a malformed one becomes an
  # inline error, never a crash loop (the same posture as the preview).
  defp parse(socket, definition) do
    assign(socket, parsed: DynamicForm.Parser.JSON.parse!(definition), parse_error: nil)
  rescue
    error -> assign(socket, parsed: nil, parse_error: Exception.message(error))
  end

  # After submit: the next position, opened so the user lands straight on it
  # — or the journey page when nothing is actionable or opening fails (e.g.
  # the next form was never published).
  defp next_destination(journey, assigns) do
    journey_to = "#{assigns.base}/journeys/#{journey.id}"

    with path when is_list(path) <- next_path(journey, assigns),
         {:ok, next_instance} <- Positions.open(journey, path, assigns.user_id) do
      "#{journey_to}/instances/#{next_instance.id}"
    else
      _nothing_actionable -> journey_to
    end
  end

  # The flow's type answers first — statuses derived fresh, so the form just
  # submitted counts as done — and the journey answers when that flow has
  # nothing left, carrying the filler on to whatever follows it.
  defp next_path(journey, assigns) do
    tree = Templates.Flows.resolve_tree(journey.flow_id)
    forms = FlowProgress.forms(tree, Instances.Flows.form_instances(journey))
    path = assigns.form_instance.path
    type = type_module(assigns, tree, FlowProgress.find_form(forms, path))

    case type.next_form(FlowProgress.forms_in_flow(forms, path), path) do
      %FormProgress{path: next} -> next
      nil -> Instances.Flows.next_path_position(journey)
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
  def render(%{form_instance: nil} = assigns) do
    ~H"""
    <p class="text-sm text-zinc-500">This form no longer exists.</p>
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
      <div class="mb-2 text-sm font-semibold">
        <.link navigate={"#{@base}/journeys"} class="hover:underline">Journeys</.link>
        <span class="text-zinc-400">/</span>
        <.link navigate={"#{@base}/journeys/#{@journey.id}"} class="hover:underline">
          Journey
        </.link>
      </div>

      <Components.FlowProgress.flow_progress
        :if={@show_progress?}
        id={"#{@id}-flow-progress"}
        forms={@forms}
        current_path={@form_instance.path}
        clickable={@clickable}
        target={@myself}
      />

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

      <%!-- A completed instance shows its answers read-only: the disabled
            fieldset switches off every control inside (a native HTML
            behavior), and the submit button is hidden. DynamicForm's
            render_only is NOT this — it is a parent-owns-the-form mode
            requiring a Phoenix.HTML.Form. --%>
      <fieldset disabled={@form_instance.status == "completed"} class="max-w-md">
        <DynamicForm.form
          id={"#{@id}-#{@form_instance.id}-#{@form_instance.status}"}
          instance={@parsed}
          data={@form_instance.data}
          hide_submit={@form_instance.status == "completed"}
          on_success={&submitted(&1, @id)}
        />
      </fieldset>
    </div>
    """
  end
end
