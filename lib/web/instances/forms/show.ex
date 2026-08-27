defmodule FormFlow.Web.Instances.Forms.Show do
  @moduledoc """
  `FormFlow.Web.Instances.Forms.Show` LiveComponent renders one form of a flow
  instance as the real, fillable form — the pinned version's definition
  through `DynamicForm`, prefilled with any answers already in `data`.

  It is addressed by *position* (`path`), not by its instance row, which is
  what lets it have two modes — the same split the template side's form pages
  have, and the reason the URL exists before the row does:

    * `:show` — the answers at this position, read-only. It never writes:
      with nothing filled in yet it says so, offering the Edit link when the
      flow's type allows work here.
    * `:edit` — the fillable form, and the only page that *opens* a position.
      An absent instance is created on mount (create-on-open, which is the
      moment the form version is pinned), gated by the same `openable?/2` the
      flow instance's page asks. Opening is idempotent afterwards, so this URL
      is an ordinary link from everywhere and survives a refresh or a Back.

  Above the form sits the progress of the "forms" flow this form belongs to —
  its sibling forms and their state — unless there is only one, which is no
  sequence worth drawing. The flow's `FormFlow.Flows.Types` module decides
  both that and which of those forms the filler may jump to: none, for an
  in-order wizard; every form of its own that isn't done, for an any-order
  one.

  Submitting writes the answers and marks the instance completed
  (`FormFlow.Data.Instances.Forms.update_status/4`), then asks the same type
  where to go: the next form of this flow, or — when it has none left — the
  next actionable position anywhere in the flow instance, which is what
  carries a filler out of a finished subflow and into the next. It navigates
  to that position's `:edit` URL, which does the opening; with nothing
  actionable left, back to the flow instance's page.

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

  # Reopening is a state change, so it stays an explicit action rather than a
  # mode of a URL: it lands on the edit page, which is where the answers can
  # then be changed.
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

  @impl true
  def handle_async(:navigate, {:ok, to}, socket) do
    {:noreply, push_navigate(socket, to: to)}
  end

  defp load(%{assigns: %{flow_instance_id: flow_instance_id}} = socket) do
    case Instances.Flows.get(flow_instance_id) do
      nil ->
        assign(socket, flow_instance: nil, form_instance: nil, parsed: nil, parse_error: nil)

      flow_instance ->
        socket
        |> assign(:flow_instance, flow_instance)
        |> load_position(flow_instance)
    end
  end

  defp load_position(socket, flow_instance) do
    path = socket.assigns.path
    tree = Templates.Flows.resolve_tree(flow_instance.flow_id)
    forms = FlowProgress.forms(tree, Instances.Flows.form_instances(flow_instance))
    in_flow = FlowProgress.forms_in_flow(forms, path)
    form = FlowProgress.find_form(forms, path)
    type = type_module(socket.assigns, tree, form)

    socket
    |> assign(
      forms: in_flow,
      show_progress?: type.show_progress?(in_flow),
      clickable: clickable(in_flow, path, type),
      flow_name: (tree && tree.flow.name) || "Untitled flow",
      form_label: (form && FlowProgress.qualified_label(form)) || "Form"
    )
    |> assign_instance(flow_instance, form, form && type.openable?(form, in_flow))
  end

  # Show renders the answers that exist and says why when there are none;
  # edit is the one page that opens a position. Either way an instance that
  # is already there is simply rendered — including a stranded one, whose
  # position the tree no longer has.
  defp assign_instance(socket, flow_instance, form, openable?) do
    path = socket.assigns.path

    cond do
      form_instance = Instances.Forms.get_at(flow_instance, path) ->
        loaded(socket, form_instance)

      is_nil(form) ->
        blocked(socket, "This form is not part of this flow.")

      socket.assigns.mode == :edit and openable? ->
        open(socket, flow_instance, path)

      openable? ->
        blocked(socket, "You haven't started this form yet.", start?: true)

      true ->
        blocked(socket, "This form isn't available yet — it comes later in the flow.")
    end
  end

  defp open(socket, flow_instance, path) do
    case Instances.Forms.update_status(flow_instance, path, :in_progress,
           user_id: socket.assigns.user_id
         ) do
      {:ok, form_instance} ->
        loaded(socket, form_instance)

      {:error, :no_published_version} ->
        blocked(
          socket,
          "That form has no published version yet — ask an administrator to publish it."
        )

      {:error, _reason} ->
        blocked(socket, "Could not open this form. The flow may have changed — reload.")
    end
  end

  defp loaded(socket, form_instance) do
    version = Templates.Forms.get_version(form_instance.template_form_version_id)

    socket
    |> assign(form_instance: form_instance, notice: nil, start_to: nil)
    |> parse(version.definition)
  end

  defp blocked(socket, notice, opts \\ []) do
    start_to =
      if opts[:start?] do
        Paths.form_edit_path(
          socket.assigns.base,
          socket.assigns.flow_instance.id,
          socket.assigns.path
        )
      end

    assign(socket,
      form_instance: nil,
      notice: notice,
      start_to: start_to,
      parsed: nil,
      parse_error: nil
    )
  end

  # The sibling forms the filler may jump to. Navigating to the one being
  # filled would do nothing, so it is never among them — which is what
  # leaves an in-order wizard's progress entirely inert, the only form it
  # opens being that one.
  defp clickable(in_flow, path, type) do
    for form <- in_flow,
        form.path != path,
        type.openable?(form, in_flow),
        into: MapSet.new(),
        do: form.path
  end

  # The form's flow type: its "forms" flow's stored form_flow_type, resolved
  # through the host's FormFlow.Config (or the library's defaults). A
  # stranded position is no longer one of the tree's forms, so the flow
  # instance's own flow answers for it.
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

  # After submit: where the filler goes, as a URL. Nothing is opened here —
  # the page that addresses a position is the one that opens it.
  defp next_destination(flow_instance, assigns) do
    case next_path(flow_instance, assigns) do
      path when is_list(path) -> Paths.form_edit_path(assigns.base, flow_instance.id, path)
      nil -> Paths.flow_path(assigns.base, flow_instance.id)
    end
  end

  # The flow's type answers first — statuses derived fresh, so the form just
  # submitted counts as done — and the flow instance answers when that flow
  # has nothing left, carrying the filler on to whatever follows it.
  defp next_path(flow_instance, assigns) do
    tree = Templates.Flows.resolve_tree(flow_instance.flow_id)
    forms = FlowProgress.forms(tree, Instances.Flows.form_instances(flow_instance))
    path = assigns.form_instance.path
    type = type_module(assigns, tree, FlowProgress.find_form(forms, path))

    case type.next_form(FlowProgress.forms_in_flow(forms, path), path) do
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

  def render(%{form_instance: nil} = assigns) do
    ~H"""
    <div>
      <.breadcrumb base={@base} flow_instance={@flow_instance} flow_name={@flow_name} label={@form_label} />

      <div class="rounded-md border border-zinc-300 bg-zinc-50 px-3 py-2 text-sm text-zinc-600">
        <p>{@notice}</p>
        <p class="mt-2 flex items-center gap-3">
          <.link :if={@start_to} navigate={@start_to} class="text-cyan-600 hover:underline">
            Start this form →
          </.link>
          <.link
            navigate={Paths.flow_path(@base, @flow_instance.id)}
            class="text-cyan-600 hover:underline"
          >
            Back to the flow
          </.link>
        </p>
      </div>
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
      <.breadcrumb base={@base} flow_instance={@flow_instance} flow_name={@flow_name} label={@form_label} />

      <Components.FlowProgress.flow_progress
        :if={@show_progress?}
        id={"#{@id}-flow-progress"}
        base={@base}
        flow_instance_id={@flow_instance.id}
        forms={@forms}
        current_path={@path}
        clickable={@clickable}
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

      <%!-- Show mode is the read-only view of the same form: the disabled
            fieldset switches off every control inside (a native HTML
            behavior), and the submit button is hidden. A completed instance
            reads the same way in either mode — its answers change through
            Reopen, not through a URL. DynamicForm's render_only is NOT this
            — it is a parent-owns-the-form mode requiring a
            Phoenix.HTML.Form. --%>
      <p :if={@mode == :show && @form_instance.status != "completed"} class="mb-2 text-xs">
        <.link
          navigate={Paths.form_edit_path(@base, @flow_instance.id, @path)}
          class="text-cyan-600 hover:underline"
        >
          Continue filling this out →
        </.link>
      </p>

      <fieldset disabled={read_only?(assigns)} class="max-w-md">
        <DynamicForm.form
          id={"#{@id}-#{@form_instance.id}-#{@form_instance.status}-#{@mode}"}
          instance={@parsed}
          data={@form_instance.data}
          hide_submit={read_only?(assigns)}
          on_success={&submitted(&1, @id)}
        />
      </fieldset>
    </div>
    """
  end

  defp read_only?(assigns) do
    assigns.mode == :show or assigns.form_instance.status == "completed"
  end

  attr(:base, :string, required: true)
  attr(:flow_instance, :map, required: true)
  attr(:flow_name, :string, required: true)
  attr(:label, :string, required: true)

  defp breadcrumb(assigns) do
    ~H"""
    <div class="mb-2 text-sm font-semibold">
      <.link navigate={Paths.flows_path(@base)} class="hover:underline">Flows</.link>
      <span class="text-zinc-400">/</span>
      <.link navigate={Paths.flow_path(@base, @flow_instance.id)} class="hover:underline">
        {@flow_name}
      </.link>
      <span class="text-zinc-400">/</span>
      {@label}
    </div>
    """
  end
end
