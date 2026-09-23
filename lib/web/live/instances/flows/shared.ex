defmodule FormFlow.Web.Instances.Flows.Shared do
  @moduledoc """
  `FormFlow.Web.Instances.Flows.Shared` module contains what the two flow
  instance pages - `FormFlow.Web.Instances.Flows.Show` and
  `FormFlow.Web.Instances.Flows.History` - have in common: the assigns they
  start from, and the loading that turns a flow instance id into the
  instance, its forms, the viewer's rows among them, the trail, and where
  the viewer stands. The sibling of `FormFlow.Web.Instances.Forms.Shared`,
  which is what the three *form* pages share.

  ## What `load/1` assigns

    * `flow_instance`, `flow_name`, `context` - the instance, its flow's
      name, and the page's own `FormFlow.Context` (the instance as a
      whole, no form in scope) for the host's `on_mount` to answer with
    * `forms` - every form of the flow with its derived state
      (`FormFlow.Data.Instances.FlowProgress.forms/2`)
    * `rows` - the forms the viewer's perspectives are for and no other
      perspective stands in front of, each
      `%{form: form, editable?: bool, word: word, last: entry}`: the flow
      type's `editable?/2`, the form pages' status word for its instance
      (`FormFlow.Web.Instances.Components.Forms.Status.status/2`), and the
      newest entry of its trail
    * `groups` - the rows cut where one "forms" flow ends and the next
      begins, as `{flow, rows}`
    * `trail` - everything that has happened in the instance, oldest first
      (`FormFlow.Data.Instances.Flows.list_events/1`), read once and
      shared between the rows' last-event lines, the perspective status,
      and the History page
    * `perspective_status` - the status of the instance for this viewer
      (`FormFlow.Web.Instances.Components.Flows.Status.status/2`)
    * `next_up` - the row that wants the viewer now: a reopened form, else
      one in progress, else the first they may start; nil when none
    * `continue_allowed?`, `part_done?`, `stranded`, `mount_error`,
      `navigate_to`

  The rows are only the forms the viewer may see - a form of a flow that is
  not for them is not a row at all - so every count, the perspective
  status, and next up are the viewer's, as the page under them is.

  ## Two rules decide which forms are rows

  The first is the flow type's `visible?/2`, the perspectives test by
  default: a form of a flow that is not for the viewer is not a row.

  The second is about the journey rather than the template. A form can be
  the viewer's and still be one no act of theirs will ever reach: the
  applicant's closing feedback form, sitting behind the reviewer's step.
  Listing it says "later" when the truth is "not yours to move". So a form
  is dropped when a step holding it is **shut on another perspective** -
  its flow's type will not let the viewer enter it
  (`FormFlow.Web.Instances.Forms.Shared.enterable?/2`), and among the
  positions still standing in that step's way
  (`FormFlow.Data.Instances.FlowProgress.unfinished_predecessors/3`) is a
  step with no form inside it the viewer may see.

  The type is asked before the edges on purpose. A "subflows" flow worked
  in any order lets a user into any unfinished step whatever the edges say,
  so none of its steps is ever shut on anyone. When the other perspective
  finishes its step, the walk back stops at a completed position, and the
  form appears on the next render with nothing else changed.
  """

  import Phoenix.Component

  alias FormFlow.Config.Flows.Perspective
  alias FormFlow.Context
  alias FormFlow.Data.Instances
  alias FormFlow.Data.Instances.FlowProgress
  alias FormFlow.Data.Templates
  alias FormFlow.Web.Controllers.Downloads
  alias FormFlow.Web.Instances.Components.Flows.Status
  alias FormFlow.Web.Instances.Components.Forms.Status, as: FormStatus
  alias FormFlow.Web.Instances.Forms

  @doc """
  The assigns every flow instance page starts from, where the router gave
  none. `download_path` falls back to `config :form_flow, download_path:`
  as the form pages' does (`FormFlow.Web.Controllers.Downloads.path/0`).
  """
  def defaults(socket) do
    socket
    |> assign_new(:base, fn -> "" end)
    |> assign_new(:tenant_id, fn -> nil end)
    |> assign_new(:perspectives, fn -> [] end)
    |> assign_new(:flow_types, fn -> FormFlow.Config.Flows.Type.defaults() end)
    |> assign_new(:form_types, fn -> FormFlow.Config.Forms.Type.defaults() end)
    |> assign_new(:callback_data, fn -> %{} end)
    |> assign_new(:components, fn -> nil end)
    |> assign_new(:on_mount, fn -> nil end)
    |> assign_new(:instances, fn -> nil end)
    |> assign_new(:flows, fn -> nil end)
    |> assign_new(:pre_release_user_ids, fn -> [] end)
    |> assign_new(:download_path, fn -> nil end)
    |> then(&assign(&1, :download_path, &1.assigns.download_path || Downloads.path()))
    |> assign_new(:uri, fn -> nil end)
    |> assign_new(:params, fn -> %{} end)
    |> assign_new(:error, fn -> nil end)
  end

  @doc """
  Loads the instance named by `flow_instance_id` and everything the pages
  read from it (see the moduledoc), then asks the host's `on_mount`. A
  missing instance assigns `flow_instance: nil` and empty lists, which is
  what `FormFlow.Web.Instances.Shared.page_state/1` reads as
  `:flow_not_found`.
  """
  def load(%{assigns: %{flow_instance_id: flow_instance_id}} = socket) do
    case Instances.Flows.get(flow_instance_id) do
      nil ->
        assign(socket,
          flow_instance: nil,
          flow_name: nil,
          forms: [],
          rows: [],
          groups: [],
          trail: [],
          perspective_status: nil,
          next_up: nil,
          stranded: []
        )

      flow_instance ->
        tree = Templates.Flows.resolve_tree(flow_instance.template_flow_id)
        instances = Instances.Flows.form_instances(flow_instance)
        forms = FlowProgress.forms(tree, instances)
        steps = FlowProgress.subflows(tree, instances)
        flow = tree && tree.flow

        context = %Context{
          user_id: socket.assigns.user_id,
          tenant_id: socket.assigns.tenant_id,
          perspectives: Perspective.normalize(socket.assigns.perspectives),
          flow: flow,
          subflow: flow,
          flow_type_property_values: FormFlow.Config.Flows.Type.property_values(flow),
          flow_instance: flow_instance,
          flow_instance_progress: forms,
          flow_instance_subflows: steps
        }

        # The context first, and the page's pre-release users with it: the
        # rows and `continue_allowed?/2` ask the status by this viewer
        socket =
          socket
          |> assign(:context, context)
          |> FormFlow.Web.Instances.Shared.resolve_pre_release_user_ids()

        trail = Instances.Flows.list_events(flow_instance)
        statuses = FlowProgress.derive(tree, instances)
        rows = rows(forms, steps, tree, statuses, flow_instance, trail, socket.assigns)
        continue_allowed? = continue_allowed?(flow, socket.assigns)

        socket =
          assign(socket,
            flow_instance: flow_instance,
            flow_name: (flow && flow.name) || "Untitled flow",
            forms: forms,
            rows: rows,
            groups: groups(rows),
            trail: trail,
            perspective_status: Status.status(rows, flow_instance),
            next_up: next_up(rows, continue_allowed?),
            continue_allowed?: continue_allowed?,
            part_done?: part_done?(rows, flow_instance),
            stranded: Instances.Flows.list_stranded(flow_instance),
            mount_error: nil,
            navigate_to: nil
          )

        Forms.Shared.on_mount(socket)
    end
  end

  @doc """
  Whether this page and the flow's status let this viewer continue work in
  it (`FormFlow.Web.Instances.Forms.Shared.allows?/3`) - a page whose
  `flows` attr says `continue: false` about the flow draws the journey
  read-only, as a `read_only` status does.
  """
  def continue_allowed?(%Templates.Flow{} = flow, assigns),
    do: Forms.Shared.allows?(flow, :continue, assigns)

  def continue_allowed?(_none, _assigns), do: false

  # Every form the viewer's perspectives are for and no other perspective
  # stands in front of, with the one question its own flow's type answers
  # here, and what its trail says of it. Editable means the form's type says
  # so and every step above it is open (`Forms.Shared.enterable_chain?/2`)
  defp rows(forms, steps, tree, statuses, flow_instance, trail, assigns) do
    by_instance =
      trail
      |> Enum.reject(&is_nil(&1.form_instance))
      |> Enum.group_by(& &1.form_instance.id)

    mine =
      for form <- forms,
          context = form_context(form, forms, steps, tree, flow_instance, assigns),
          type = Forms.Shared.flow_type(context, assigns),
          Forms.Shared.visible?(type, context, assigns),
          do: {form, context, type}

    shut = shut_on_another_perspective(mine, forms, steps, tree, statuses, assigns)

    for {form, context, type} <- mine, not behind_another_perspective?(form, shut) do
      entries = (form.instance && Map.get(by_instance, form.instance.id, [])) || []

      %{
        form: form,
        editable?:
          Forms.Shared.enterable_chain?(context, assigns) and
            type.module.editable?(context, assigns.callback_data),
        word: FormStatus.status(form.instance, Enum.map(entries, & &1.event)),
        last: List.last(entries)
      }
    end
  end

  # Whether one of the steps holding this form is a step only another
  # perspective can open.
  defp behind_another_perspective?(form, shut) do
    Enum.any?(1..length(form.ancestors)//1, &MapSet.member?(shut, Enum.take(form.path, &1)))
  end

  # The steps only another perspective can open: the step's own flow's type
  # will not let the viewer in, and among the positions still standing in
  # its way is a step with nothing inside for them. Their paths.
  #
  # Asking the type first is what keeps the edges honest. A "subflows" flow
  # worked in any order has predecessors and no door - every unfinished
  # step of it is enterable - so none of its steps is ever shut on anyone.
  defp shut_on_another_perspective(mine, forms, steps, tree, statuses, assigns) do
    theirs = steps_holding_nothing_of_mine(forms, mine)

    if MapSet.size(theirs) == 0 do
      MapSet.new()
    else
      for step <- steps,
          not Forms.Shared.enterable?(Forms.Shared.step_context(assigns.context, step), assigns),
          tree
          |> FlowProgress.unfinished_predecessors(statuses, step.path)
          |> Enum.any?(&MapSet.member?(theirs, &1)),
          into: MapSet.new(),
          do: step.path
    end
  end

  # The steps with no form inside them, at any depth, that the viewer's
  # perspectives are for. A step holding no form at all is not one of them:
  # there is nobody it belongs to instead.
  defp steps_holding_nothing_of_mine(forms, mine) do
    seen = MapSet.new(mine, fn {form, _context, _type} -> form.path end)

    forms
    |> Enum.flat_map(fn form ->
      for depth <- 1..length(form.ancestors)//1,
          do: {Enum.take(form.path, depth), MapSet.member?(seen, form.path)}
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.reject(fn {_path, mine?} -> Enum.any?(mine?) end)
    |> Enum.map(&elem(&1, 0))
    |> MapSet.new()
  end

  defp form_context(form, forms, steps, tree, flow_instance, assigns) do
    context = %Context{
      user_id: assigns.user_id,
      tenant_id: assigns.tenant_id,
      perspectives: Perspective.normalize(assigns.perspectives),
      flow: tree.flow,
      subflow: form.flow,
      subflow_node: List.last(form.ancestors),
      form_node: form.node,
      flow_type_property_values: FormFlow.Config.Flows.Type.property_values(form.flow),
      flow_instance: flow_instance,
      form_progress: form,
      flow_progress: FlowProgress.forms_in_flow(forms, form.path),
      flow_instance_progress: forms,
      flow_instance_subflows: steps
    }

    %Context{context | flow_perspectives: Forms.Shared.flow_perspectives(context, assigns)}
  end

  # The viewer's part is done when every form they can see is completed and
  # the instance as a whole is not - what remains is someone else's
  defp part_done?(rows, flow_instance) do
    rows != [] and flow_instance.status != "completed" and
      Enum.all?(rows, &(&1.form.status == :completed))
  end

  # The rows in the order the flow walks them, cut where one "forms" flow
  # ends and the next begins. A simple flow is one group; a complex one is
  # a group per subflow the viewer can see, headed by that subflow's name.
  defp groups(rows) do
    rows
    |> Enum.chunk_by(& &1.form.flow.id)
    |> Enum.map(fn [first | _] = group -> {first.form.flow, group} end)
  end

  # The one row that wants the viewer: sent back to them first, then what
  # they have under way, then the first the flow lets them start. Continuing
  # needs the flow to allow it; starting is the type's answer alone, as the
  # Start button's is.
  defp next_up(rows, continue_allowed?) do
    (continue_allowed? &&
       (Enum.find(rows, &(&1.word == :reopened and &1.form.status == :in_progress)) ||
          Enum.find(rows, &(&1.form.status == :in_progress and &1.form.instance)))) ||
      Enum.find(rows, &(&1.editable? and is_nil(&1.form.instance)))
  end
end
