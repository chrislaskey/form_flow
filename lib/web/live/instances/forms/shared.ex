defmodule FormFlow.Web.Instances.Forms.Shared do
  @moduledoc """
  `FormFlow.Web.Instances.Forms.Shared` is what the two form pages have in
  common: resolving the position a page addresses into everything it needs
  to render, and the flow-level lookups both pages make along the way.

  `FormFlow.Web.Instances.Forms.Show` and `FormFlow.Web.Instances.Forms.Edit`
  are each addressed by a flow instance plus a `path`, and both need the same
  answers before they can render anything: which form the path names, which
  `FormFlow.Config.Flows.Type` governs its flow, whether that type lets the
  user edit there, and which live instance - if any - holds the answers.
  Only what they *do* with those answers differs, so the resolving lives here
  rather than in either of them, where two copies of one gate could drift
  apart.

  `resolve/1` is the loading itself, over a plain map of attrs: the position
  looked up into a template tree, a journey's progress, the live instance
  there, and the `FormFlow.Context` around them.
  `FormFlow.Web.Controllers.Downloads` calls it too, which is what makes a
  printed form and the page it was printed from the same answers.

  `assigns/1` reads the page's `flow_instance`, `path`, and the host's attrs
  (the type lists, `callback_data`) from the socket, resolves them, and
  assigns the lot back onto it, writing nothing:

    * `:form` - the `FormFlow.Data.Instances.FormProgress` at this path, or
      nil when the flow no longer has the position
    * `:forms` - every form of the "forms" flow this one belongs to, in order
    * `:form_instance` - the live `FormFlow.Data.Instances.Form`, or nil
    * `:events` - its event trail, oldest first
      (`FormFlow.Data.Instances.Forms.list_events/2`); `[]` until it has an
      instance. The header's status badge and last event line read it, and
      the History page lists it
    * `:type` - the `FormFlow.Config.Flows.Type` governing this form's flow,
      which Edit asks again after a submit to find where to go next
    * `:form_type` - the `FormFlow.Config.Forms.Type` governing the form
      itself
    * `:initial_data` - what the form renders with: the form type's
      `initial_data/2`, over a chosen prefill, under the user's saved
      draft; nil until the form has an instance
    * `:draft` - the user's saved draft
      (`FormFlow.Data.Instances.Form.Draft`), or nil. Edit says when and by
      whom it was saved; its answers are already in `:initial_data`
    * `:context` - the `FormFlow.Context` both types' callbacks take, for
      this form
    * `:visible?` - whether the type says this form's flow is for the viewer
      at all (`visible?/2`, the perspectives test by default)
    * `:editable?` - whether the type allows editing here - never when the
      form is not visible
    * `:start_error` - why `start/1` could not start the form, or nil
    * `:mount_error` / `:navigate_to` - the host's `on_mount` answer when it
      refused or redirected, or nil
    * `:step_links` - where each sibling form's step links, `:view` or
      `:edit` by path, for `FormFlow.Web.Instances.Components.Flows.Progress`
    * `:flow_name` / `:form_label` / `:form_trail` - what the breadcrumb needs:
      the flow's name, the full "subflow / subflow / form" text, and the
      subflow names alone, outermost first, for drawing each as its own link
    * `:parsed` / `:parse_error` - the instance's version's definition, through
      `DynamicForm`

  Then each page asks whether it may render (`on_mount/2`): first whether
  the instance is of a flow the page's `flows` attr names - a page about
  Dog License does not show a Cat License instance - and then the host's
  `on_mount`. Edit - only Edit, and only when the host said yes -
  makes the one write in here, `start/1`: a form with no instance yet is
  started when the flow's type allows it, which creates the instance and is
  the moment the form version is recorded. The order is the point: a refused
  visitor starts nothing.
  """

  import Phoenix.Component, only: [assign: 2, assign: 3]
  import Phoenix.LiveView, only: [start_async: 3]

  alias FormFlow.Config.Flows.Allowed
  alias FormFlow.Config.Flows.Perspective
  alias FormFlow.Context
  alias FormFlow.Data.Instances
  alias FormFlow.Data.Instances.FlowProgress
  alias FormFlow.Data.Instances.FormProgress
  alias FormFlow.Data.Templates

  # What a form is governed by when the page has no form types at all - a
  # host passing [].
  @default_form_type %FormFlow.Config.Forms.Type{
    module: FormFlow.Config.Forms.Type.Default,
    name: "Default"
  }

  def assigns(socket) do
    %{context: context, tree: tree, version: version, form_instance: form_instance} =
      resolve(socket.assigns)

    # The page's pre-release users, resolved now that the context exists -
    # `continue_allowed?/2` below is the first to ask
    socket =
      socket
      |> assign(:context, context)
      |> FormFlow.Web.Instances.Shared.resolve_pre_release_user_ids()

    type = flow_type(context, socket.assigns)
    {visible?, editable?} = access(type, context, socket.assigns)
    form_type = form_type(context, socket.assigns)
    prefills = prefills(context)
    prefill = prefill(context, socket.assigns.params["prefill"])
    draft = Instances.Forms.get_draft(form_instance)

    socket
    |> assign(
      form: context.form_progress,
      forms: context.flow_progress,
      form_instance: form_instance,
      events: events(form_instance),
      type: type,
      form_type: form_type,
      initial_data:
        initial_data(
          form_instance,
          form_type,
          context,
          socket.assigns.callback_data,
          prefill,
          draft
        ),
      draft: draft,
      context: context,
      visible?: visible?,
      editable?: editable?,
      continue_allowed?: continue_allowed?(context, socket.assigns),
      start_error: nil,
      mount_error: nil,
      navigate_to: nil,
      step_links: step_links(type, context, socket.assigns),
      flow_name: (tree && tree.flow.name) || "Untitled flow",
      prefills: prefills,
      prefill: prefill,
      missing_prefill_name: prefill == nil && presence(socket.assigns.params["prefill"]),
      prefills_offered?: prefills_offered?(context),
      form_label:
        (context.form_progress && FlowProgress.qualified_label(context.form_progress)) || "Form",
      form_trail:
        (context.form_progress && FlowProgress.ancestor_labels(context.form_progress)) || []
    )
    |> parse(version)
  end

  defp events(nil), do: []
  defp events(form_instance), do: Instances.Forms.list_events(form_instance)

  defp initial_data(nil, _form_type, _context, _callback_data, _prefill, _draft), do: nil

  defp initial_data(_form_instance, form_type, context, callback_data, prefill, draft) do
    form_type.module.initial_data(context, callback_data)
    |> fill_from_prefill(prefill)
    |> fill_from_draft(draft)
  end

  # The prefill's answers under whatever the form type supplies, which is the
  # user's stored answers by default: filling a form in from a saved set can
  # never replace something the user typed
  # (`FormFlow.Data.Templates.Form.Prefill`).
  defp fill_from_prefill(initial_data, nil), do: initial_data
  defp fill_from_prefill(initial_data, prefill), do: Map.merge(prefill.data, initial_data)

  # The user's saved draft over everything else: it is the newest thing they
  # did to this form. A reopened form has its submitted answers in `data`;
  # a draft saved after the reopen is what they were changing them to. So
  # the order is prefill under, stored answers over it, draft over both.
  defp fill_from_draft(initial_data, nil), do: initial_data
  defp fill_from_draft(initial_data, draft), do: Map.merge(initial_data, draft.data)

  defp prefills(%Context{form: %Templates.Form{} = form}), do: Templates.Forms.list_prefills(form)
  defp prefills(_context), do: []

  defp prefill(%Context{form: %Templates.Form{} = form}, name)
       when is_binary(name) and name != "",
       do: Templates.Forms.get_prefill(form, name)

  defp prefill(_context, _name), do: nil

  @doc """
  Whether this page offers to fill the form in from one of the form's
  prefills: while the flow is a `draft` or in `pre_release`, the statuses
  that mean it is being tried out rather than used. Nothing is stored by
  applying one - the answers are what the form renders with until the user
  saves or submits them.

  Not a permission: the pages draw the picker where this says so, and
  nothing behind it asks (`archive/plans/prefills-for-testing.md` §15).
  """
  def prefills_offered?(%Context{flow: %Templates.Flow{status: status}}),
    do: status in ~w(draft pre_release)

  def prefills_offered?(_context), do: false

  defp presence(empty) when empty in [nil, ""], do: nil
  defp presence(value), do: value

  @doc """
  Everything a page or a request addressing one position needs loaded, from
  a plain map of the same attrs `assigns/1` reads off a socket:
  `:flow_instance`, `:path`, `:user_id`, `:tenant_id`, `:perspectives`,
  and `:flow_types`.

  Returns `%{tree: …, forms: …, steps: …, form_instance: …, version: …, context: …}` -
  the resolved template tree, the whole journey's progress (its forms and
  its subflow steps), the live
  instance at the position (`nil` until it is started), the version it
  renders, and the `FormFlow.Context` the two form pages and every
  callback are given.

  It takes assigns rather than a socket because it is read from outside
  LiveView too: `FormFlow.Web.Controllers.Downloads` resolves a download's
  position through this, so a printed form and the page it was printed from
  can never disagree about what the answers are.
  """
  def resolve(assigns) do
    %{flow_instance: flow_instance, path: path} = assigns
    tree = Templates.Flows.resolve_tree(flow_instance.template_flow_id)
    instances = Instances.Flows.form_instances(flow_instance)
    forms = FlowProgress.forms(tree, instances)
    steps = FlowProgress.subflows(tree, instances)

    # An instance already at the position is simply used - including a
    # stranded one, whose position the tree no longer has
    form_instance = Instances.Forms.get_at(flow_instance, path)

    version = form_instance && Templates.Forms.get_version(form_instance.template_form_version_id)

    form = version && Templates.Forms.get(version.form_id)

    context = %Context{
      context(assigns, tree, forms, steps)
      | form: form,
        form_version: version,
        form_type_property_values: FormFlow.Config.Forms.Type.property_values(form),
        form_instance: form_instance
    }

    %{
      tree: tree,
      forms: forms,
      steps: steps,
      form_instance: form_instance,
      version: version,
      context: context
    }
  end

  @doc """
  The `FormFlow.Context` of the form at `path` in a flow instance: the form,
  its flow's forms in order, the journey's subflow steps (`steps`, from
  `FlowProgress.subflows/2` - the doors on the way down), and the form
  template they sit in. A stranded position is no longer one of the tree's
  forms, so the flow instance's own flow answers for it.
  """
  def context(%{flow_instance: flow_instance, path: path} = assigns, tree, forms, steps) do
    form = FlowProgress.find_form(forms, path)

    subflow = (form && form.flow) || (tree && tree.flow)

    context = %Context{
      user_id: assigns.user_id,
      tenant_id: assigns.tenant_id,
      perspectives: Perspective.normalize(assigns.perspectives),
      flow: tree && tree.flow,
      subflow: subflow,
      subflow_node: form && List.last(form.ancestors),
      form_node: form && form.node,
      flow_type_property_values: FormFlow.Config.Flows.Type.property_values(subflow),
      flow_instance: flow_instance,
      form_progress: form,
      flow_progress: FlowProgress.forms_in_flow(forms, path),
      flow_instance_progress: forms,
      flow_instance_subflows: steps
    }

    %Context{context | flow_perspectives: flow_perspectives(context, assigns)}
  end

  @doc """
  The `FormFlow.Config.Flows.Perspective` structs the context's `:subflow` is
  for - its stored ids resolved through the `:perspectives` its flow type
  declares (`flow_type/2`, so an unset type resolves as everywhere else).
  `[]` for a flow that names none, or names only ids the type no longer has.
  """
  def flow_perspectives(%Context{subflow: flow} = context, assigns) do
    Perspective.for_flow(flow, flow_type(context, assigns).perspectives)
  end

  @doc """
  Whether the flow type says the form at the context's `:form_progress` is
  for this viewer - `visible?/2`, the perspectives test by default. The
  pages hide, skip, and refuse a form that is not.
  """
  def visible?(type, context, assigns), do: type.module.visible?(context, assigns.callback_data)

  @doc """
  The first form of the whole flow instance the viewer can work next, in
  flow order: actionable, visible to them, and behind no closed step
  (`enterable_chain?/2`). `nil` when nothing is - the viewer's part is done,
  or blocked on someone else's.
  """
  def next_visible_form(%Context{flow_instance_progress: forms} = context, assigns) do
    Enum.find(forms, fn form ->
      form_context = form_context(context, form)

      FlowProgress.actionable?(form) and
        visible?(flow_type(form_context, assigns), form_context, assigns) and
        enterable_chain?(form_context, assigns)
    end)
  end

  # The context re-aimed at another form of the same flow instance
  defp form_context(%Context{flow_instance_progress: forms} = context, form) do
    %Context{
      context
      | subflow: form.flow,
        subflow_node: List.last(form.ancestors),
        form_node: form.node,
        flow_type_property_values: FormFlow.Config.Flows.Type.property_values(form.flow),
        form_progress: form,
        flow_progress: FlowProgress.forms_in_flow(forms, form.path)
    }
  end

  @doc """
  Whether every "subflows" flow above the form at `:form_progress` lets the
  step on the way down be entered - each ancestor step asked of its own
  flow's type (`enterable?/2`), root first. A form in the root flow
  has no steps above it and is never behind a door. A step the journey's
  progress does not know (a stranded position) is a closed one.
  """
  def enterable_chain?(%Context{form_progress: nil}, _assigns), do: false

  def enterable_chain?(%Context{form_progress: form} = context, assigns) do
    form.ancestors
    |> Enum.with_index(1)
    |> Enum.all?(fn {_node, depth} ->
      case FlowProgress.find_subflow(
             context.flow_instance_subflows || [],
             Enum.take(form.path, depth)
           ) do
        nil -> false
        step -> enterable?(step_context(context, step), assigns)
      end
    end)
  end

  @doc """
  The context re-aimed at a subflow step, for a "subflows" flow's type:
  `:subflow` is the flow the step is in, `:subflow_node` the step,
  `:subflow_progress` its progress and `:complex_progress` its siblings in
  order. The form fields are left as they were.
  """
  def step_context(%Context{flow_instance_subflows: steps} = context, step) do
    %Context{
      context
      | subflow: step.flow,
        subflow_node: step.node,
        subflow_progress: step,
        complex_progress: FlowProgress.subflows_in_flow(steps || [], step.path),
        flow_type_property_values: FormFlow.Config.Flows.Type.property_values(step.flow)
    }
  end

  @doc "Whether the \"subflows\" flow at a step context's `:subflow` lets the step be entered."
  def enterable?(%Context{} = step_context, assigns) do
    type = flow_type(step_context, assigns)
    type.module.enterable?(step_context, assigns.callback_data)
  end

  @doc """
  Where the user goes when the "forms" flow of the form at `:form_progress`
  has nothing left for them: each "subflows" flow above it is asked in turn,
  innermost first, for the next step (`handle_complete/2`), and the first
  form the viewer can work inside that step is the answer. `nil` when no
  level names a step with work for this viewer.
  """
  def next_after_step(%Context{form_progress: nil}, _assigns), do: nil

  def next_after_step(%Context{form_progress: form} = context, assigns) do
    form.ancestors
    |> Enum.with_index(1)
    |> Enum.reverse()
    |> Enum.find_value(fn {_node, depth} ->
      with %{} = step <-
             FlowProgress.find_subflow(
               context.flow_instance_subflows || [],
               Enum.take(form.path, depth)
             ),
           level = step_context(context, step),
           type = flow_type(level, assigns),
           %{path: next} <- type.module.handle_complete(level, assigns.callback_data) do
        first_workable_under(context, next, assigns)
      else
        _nothing -> nil
      end
    end)
  end

  # The first form under a step the viewer can work: actionable, theirs, and
  # behind no closed door
  defp first_workable_under(%Context{flow_instance_progress: forms} = context, prefix, assigns) do
    Enum.find(forms, fn form ->
      List.starts_with?(form.path, prefix) and
        FlowProgress.actionable?(form) and
        workable?(context, form, assigns)
    end)
  end

  defp workable?(context, form, assigns) do
    form_context = form_context(context, form)

    visible?(flow_type(form_context, assigns), form_context, assigns) and
      enterable_chain?(form_context, assigns)
  end

  @doc """
  The `FormFlow.Config.Flows.Type` governing the flow at the context's
  `:subflow` among the page's `flow_types`
  (`FormFlow.Config.Flows.Type.for_flow/2`) - a "forms" flow's or, for a
  step context (`step_context/2`), a "subflows" flow's.
  """
  def flow_type(%Context{subflow: flow}, assigns) do
    FormFlow.Config.Flows.Type.for_flow(assigns.flow_types, flow)
  end

  @doc """
  The `FormFlow.Config.Forms.Type` governing the form at the context's
  `:form`: its stored `properties["form_type"]` looked up among the page's
  `form_types`, with the same fallbacks as `flow_type/2` - the first type,
  then the library's default.
  """
  def form_type(%Context{form: form}, assigns) do
    types = assigns.form_types
    id = form && form.properties["form_type"]

    Enum.find(types, &(&1.id == id)) || List.first(types) || @default_form_type
  end

  @doc """
  Whether the page may render. First the library's own check: an instance
  page whose `flows` attr names flows in particular renders only an
  instance of one of them (`resolve_flows/2`), and refuses the rest with
  `:mount_error` - the counterpart of the listing refusing to start a flow it
  did not offer. A host naming no flows accepts every instance, and the
  listing has no instance in scope.

  Then the host's `on_mount`, with the page's `:context` and its
  `callback_data`, applying the answer: `{:ok, assigns}` runs `on_ok`
  (Edit's `start/1`) and then merges the assigns; `{:error, message}`
  assigns `:mount_error`, which the page renders alone; `{:redirect, to}`
  assigns `:navigate_to` and navigates, the page rendering nothing meanwhile.
  The flow instance's page and the listing use this too. No `on_mount`
  allows everything. Host code, deliberately not rescued: an exception here
  fails closed rather than falling through to the page.
  """
  def on_mount(socket, on_ok \\ & &1, opts \\ []) do
    socket = FormFlow.Web.Instances.Shared.resolve_pre_release_user_ids(socket)
    flow = instance_flow(socket.assigns)

    cond do
      not flow_in_scope?(socket.assigns) ->
        assign(socket, :mount_error, "This flow is not available here.")

      flow && not FormFlow.Web.Instances.Shared.status_allows?(flow, :see, socket.assigns) ->
        assign(socket, :mount_error, "This flow is not available right now.")

      flow && not allows?(flow, Keyword.get(opts, :allows, :see), socket.assigns) ->
        assign(
          socket,
          :mount_error,
          "This flow is read-only now; your answers are kept as they are."
        )

      true ->
        host_on_mount(socket, on_ok)
    end
  end

  # The flow's status is the second rule before the host's gate: an instance
  # of a flow whose status lets nobody see it (a draft, an archived one) is
  # refused on every instance page, whoever is looking; the edit page asks
  # for `:continue` as well (`opts[:allows]`), so a read-only flow refuses it
  # with the sentence that says why. The listing has no instance and passes.
  # The root flow is already in the page's context - `resolve/1` loaded it
  # with the tree - so nothing is read again; a page without one (the
  # instance's flow is gone) is refused by the pages' own not-found state.
  defp instance_flow(%{flow_instance: %{}, context: %Context{flow: %Templates.Flow{} = flow}}),
    do: flow

  defp instance_flow(_assigns), do: nil

  # The page's `flows` attr is its scope: an instance is in it when the attr
  # names its flow. Membership is what answers `:see` - there is no `see`
  # field on `FormFlow.Config.Flows.Allowed` because this is it. No attr, or
  # no instance in scope (the listing), and every instance is.
  defp flow_in_scope?(%{flow_instance: %{}, flows: flows} = assigns) when is_list(flows) do
    assigns |> instance_flow() |> page_allows?(:see, assigns)
  end

  defp flow_in_scope?(_assigns), do: true

  @doc """
  Whether a viewer may `:start`, `:continue`, or `:see` this flow here: the
  page's own answer (`page_allows?/3`) and the flow's status
  (`FormFlow.Web.Instances.Shared.status_allows?/3`), both of which an
  action needs.

  The two say different kinds of thing and neither wins: the status is the
  flow's own lifecycle, the same wherever it is drawn, and the attr is this
  page's decision about it. A host that wants a read-only page for a flow
  that is otherwise open writes `continue: false`; a flow that went
  `read_only` is read-only on every page, whatever they say.
  """
  def allows?(flow, action, assigns) do
    page_allows?(flow, action, assigns) and
      FormFlow.Web.Instances.Shared.status_allows?(flow, action, assigns)
  end

  @doc """
  Whether the page's `flows` attr allows `action` on this flow: the attr
  names the flow, and the `FormFlow.Config.Flows.Allowed` naming it says so
  (`:see` being answered by naming it at all). A host naming no flows
  allows everything; a flow of another tenant is named by nobody.

  This is half the rule. The flow's status is the other half
  (`FormFlow.Web.Instances.Shared.status_allows?/3`), and an action needs
  both - a `winding_down` flow the page says `start: true` about is still
  not offered.

  No query: the flow is in hand, so the attr's entries are matched against
  it by whichever handle they set.
  """
  def page_allows?(flow, action, assigns)

  def page_allows?(_flow, _action, assigns) when not is_map_key(assigns, :flows), do: true

  def page_allows?(%Templates.Flow{} = flow, action, %{flows: flows} = assigns)
      when is_list(flows) do
    case page_allowed(flow, assigns) do
      %Allowed{} = allowed -> Allowed.allows?(allowed, action)
      nil -> false
    end
  end

  def page_allows?(%Templates.Flow{}, _action, %{flows: nil}), do: true

  # No flow to match: the instance's template is gone. A page that named
  # flows in particular refuses rather than guesses; a page that named none
  # had nothing to match it against anyway.
  def page_allows?(nil, _action, %{flows: flows}) when is_list(flows), do: false
  def page_allows?(nil, _action, _assigns), do: true

  # The attr's entry for this flow, or `nil` when it names no such flow. The
  # router's tenant is applied first, as it is everywhere else: a slug is
  # unique per tenant, so an entry naming one never reaches another's flow.
  defp page_allowed(%Templates.Flow{} = flow, %{flows: flows} = assigns) do
    if in_tenant?(flow, Map.get(assigns, :tenant_id)) do
      Enum.find(flows, &Allowed.names?(&1, flow))
    end
  end

  @doc """
  The page's `flows` attr resolved to `FormFlow.Config.Flows.Allowed` structs
  with their `:flow` loaded: an entry naming a flow by `flow_id` or
  `flow_slug` is looked up in the tenant, and an entry whose flow is not
  found or belongs to another tenant is dropped. `nil` - the host named none
  in particular - is every root flow of the tenant, each fully allowed.

  These are the flows the page is about, each with what the page lets a user
  do with it. Only the listing needs them loaded; the instance pages match
  the flow they already hold (`page_allows?/3`).
  """
  def resolve_flows(nil, tenant_id) do
    Enum.map(Templates.Flows.list(tenant_id: tenant_id), &%Allowed{flow: &1})
  end

  def resolve_flows(flows, tenant_id) when is_list(flows) do
    flows
    |> Enum.map(&load_flow(&1, tenant_id))
    |> Enum.filter(&in_tenant?(&1.flow, tenant_id))
  end

  defp load_flow(%Allowed{} = allowed, tenant_id) do
    case Allowed.handle(allowed) do
      {:flow, %Templates.Flow{}} ->
        allowed

      {:flow_id, id} ->
        %{allowed | flow: Templates.Flows.get_row(id)}

      {:flow_slug, slug} ->
        %{allowed | flow: Templates.Flows.get_by_slug(slug, tenant_id: tenant_id)}
    end
  end

  defp load_flow(other, _tenant_id) do
    raise ArgumentError,
          "the `flows` attr takes FormFlow.Config.Flows.Allowed structs; got #{inspect(other)}"
  end

  defp in_tenant?(nil, _tenant_id), do: false
  defp in_tenant?(%Templates.Flow{}, nil), do: true
  defp in_tenant?(%Templates.Flow{tenant_id: tenant_id}, tenant_id), do: true
  defp in_tenant?(%Templates.Flow{}, _tenant_id), do: false

  defp host_on_mount(socket, on_ok) do
    %{context: context, on_mount: gate, callback_data: callback_data} = socket.assigns

    case gate && gate.(context, callback_data) do
      nil ->
        on_ok.(socket)

      {:ok, extra} when is_map(extra) ->
        socket |> on_ok.() |> assign(extra)

      {:error, message} when is_binary(message) ->
        assign(socket, :mount_error, message)

      {:redirect, to} when is_binary(to) ->
        socket
        |> assign(:navigate_to, to)
        |> start_async(:navigate, fn -> to end)

      other ->
        raise ArgumentError,
              "on_mount returned #{inspect(other)}; " <>
                "expected {:ok, assigns}, {:error, message}, or {:redirect, to}"
    end
  end

  @doc """
  Edit's mode: a position with no instance yet is started when the flow's
  type allows editing there - the instance is created, which records the
  form version - and the page's assigns are derived again, since the first
  derivation ran before the start and still called this form available rather
  than in progress. A position with an instance, or one the type keeps
  closed, is left as it is; a start that fails leaves `:start_error`.
  """
  def start(%{assigns: %{form_instance: nil, editable?: true}} = socket) do
    %{flow_instance: flow_instance, path: path} = socket.assigns

    case start_instance(flow_instance, path, socket.assigns) do
      {:ok, _started} -> assigns(socket)
      {:error, message} -> assign(socket, :start_error, message)
    end
  end

  def start(socket), do: socket

  @doc """
  Puts the page's form instance back in progress, and answers with the
  instance or with the message the page shows.

  The flow's status is asked again here, from the flow as it now is: Reopen
  was drawn while continuing was allowed, and the year may have closed while
  the tab sat open. All three form pages reopen through this, so the rule
  cannot hold on one of them and not another.
  """
  @spec reopen(map()) :: {:ok, Instances.Form.t()} | {:error, String.t()}
  def reopen(%{flow_instance: flow_instance, form_instance: form_instance} = assigns) do
    flow = Templates.Flows.get_row(flow_instance.template_flow_id)

    if match?(%Templates.Flow{}, flow) and allows?(flow, :continue, assigns) do
      case Instances.Forms.update_status(flow_instance, form_instance.path, :in_progress,
             user_id: assigns.user_id,
             tenant_id: assigns.tenant_id,
             flow_types: assigns.flow_types,
             callback_data: assigns.callback_data
           ) do
        {:ok, reopened} -> {:ok, reopened}
        {:error, _changeset} -> {:error, "Could not reopen the form."}
      end
    else
      {:error, "This flow is read-only now."}
    end
  end

  defp start_instance(flow_instance, path, assigns) do
    case Instances.Forms.update_status(flow_instance, path, :in_progress,
           user_id: assigns.user_id,
           tenant_id: assigns.tenant_id,
           flow_types: assigns.flow_types,
           callback_data: assigns.callback_data
         ) do
      {:ok, form_instance} ->
        {:ok, form_instance}

      {:error, :no_published_version} ->
        {:error, "That form has no published version yet - ask an administrator to publish it."}

      {:error, _reason} ->
        {:error, "Could not start this form. The flow may have changed - reload."}
    end
  end

  # A definition is admin-authored input - a malformed one becomes an inline
  # error, never a crash loop (the same posture as the preview).
  defp parse(socket, nil), do: assign(socket, parsed: nil, parse_error: nil)

  defp parse(socket, version) do
    assign(socket,
      parsed: DynamicForm.Parser.FromData.parse!(version.definition),
      parse_error: nil
    )
  rescue
    error -> assign(socket, parsed: nil, parse_error: Exception.message(error))
  end

  # Whether the form is for this viewer, and whether they may edit it now - a
  # position the tree no longer has is neither, and one that is not visible
  # is never editable
  defp access(_type, %Context{form_progress: nil}, _assigns), do: {false, false}

  defp access(type, context, assigns) do
    visible? = visible?(type, context, assigns)

    {visible?,
     visible? and continue_allowed?(context, assigns) and enterable_chain?(context, assigns) and
       editable?(type, context, assigns)}
  end

  # Whether this page and the flow's status let this viewer continue -
  # start, edit, reopen, submit - at any position (`allows?/3`); a flow the
  # tree no longer resolves lets nobody
  defp continue_allowed?(%Context{flow: %Templates.Flow{} = flow}, assigns),
    do: allows?(flow, :continue, assigns)

  defp continue_allowed?(_context, _assigns), do: false

  defp editable?(type, context, assigns),
    do: type.module.editable?(context, assigns.callback_data)

  # Where each sibling form's step links, behind the doors above it: `:view`
  # for one already submitted, `:edit` for one the type lets the user work
  # in - asked of the type one form at a time, through form_context/2, so
  # the type is asked about the sibling with every field of the context
  # aimed at it, `form_node` included. A sibling with neither is absent, and
  # so is the one this page addresses: navigating to it would do nothing.
  #
  # The two answers together are what an in-order wizard's steps read as -
  # the forms behind the user link to their answers, the ones ahead are
  # plain text - and an any-order wizard's, where everything links: what is
  # done to its answers, the rest to its form.
  defp step_links(type, context, assigns) do
    for sibling <- context.flow_progress,
        sibling.path != assigns.path,
        enterable_chain?(form_context(context, sibling), assigns),
        target = step_target(type, context, sibling, assigns),
        into: %{},
        do: {sibling.path, target}
  end

  defp step_target(_type, _context, %FormProgress{status: :completed}, _assigns), do: :view

  defp step_target(type, context, sibling, assigns) do
    if editable?(type, form_context(context, sibling), assigns), do: :edit
  end
end
