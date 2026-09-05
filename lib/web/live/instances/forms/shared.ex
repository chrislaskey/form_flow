defmodule FormFlow.Web.Instances.Forms.Shared do
  @moduledoc """
  `FormFlow.Web.Instances.Forms.Shared` is what the two form pages have in
  common: resolving the position a page addresses into everything it needs
  to render, and the flow-level lookups both pages make along the way.

  `FormFlow.Web.Instances.Forms.Show` and `FormFlow.Web.Instances.Forms.Edit`
  are each addressed by a flow instance plus a `path`, and both need the same
  answers before they can render anything: which form the path names, which
  `FormFlow.Config.Flows.Type` governs its flow, whether that type lets the
  user edit there, and which live instance — if any — holds the answers.
  Only what they *do* with those answers differs, so the resolving lives here
  rather than in either of them, where two copies of one gate could drift
  apart.

  `resolve/1` is the loading itself, over a plain map of attrs: the position
  looked up into a template tree, a journey's progress, the live instance
  there, and the `FormFlow.Context` around them. `FormFlow.Web.Downloads`
  calls it too, which is what makes a printed form and the page it was
  printed from the same answers.

  `assigns/1` reads the page's `flow_instance`, `path`, and the host's attrs
  (the type lists, `callback_data`) from the socket, resolves them, and
  assigns the lot back onto it, writing nothing:

    * `:form` - the `FormFlow.Data.Instances.FormProgress` at this path, or
      nil when the flow no longer has the position
    * `:forms` - every form of the "forms" flow this one belongs to, in order
    * `:form_instance` - the live `FormFlow.Data.Instances.Form`, or nil
    * `:type` - the `FormFlow.Config.Flows.Type` governing this form's flow,
      which Edit asks again after a submit to find where to go next
    * `:form_type` - the `FormFlow.Config.Forms.Type` governing the form
      itself
    * `:initial_data` - what the form renders with, from the form type's
      `initial_data/2`; nil until the form has an instance
    * `:context` - the `FormFlow.Context` both types' callbacks take, for
      this form
    * `:visible?` - whether the type says this form's flow is for the viewer
      at all (`visible?/2`, the perspectives test by default)
    * `:editable?` - whether the type allows editing here — never when the
      form is not visible
    * `:start_error` - why `start/1` could not start the form, or nil
    * `:mount_error` / `:navigate_to` - the host's `on_mount` answer when it
      refused or redirected, or nil
    * `:clickable` - the sibling forms the type lets the user jump to, for
      `FormFlow.Web.Instances.Components.Flows.Progress`
    * `:flow_name` / `:form_label` - what the breadcrumb needs
    * `:parsed` / `:parse_error` - the pinned definition, through `DynamicForm`

  Then each page asks whether it may render (`on_mount/2`): first whether
  the instance is of a flow the page's `flows` attr names — a page about
  Dog License does not show a Cat License instance — and then the host's
  `on_mount`. Edit — only Edit, and only when the host said yes —
  makes the one write in here, `start/1`: a form with no instance yet is
  started when the flow's type allows it, which creates the instance and is
  the moment the form version is pinned. The order is the point: a refused
  visitor starts nothing.
  """

  import Phoenix.Component, only: [assign: 2, assign: 3]
  import Phoenix.LiveView, only: [start_async: 3]

  alias FormFlow.Config.Flows.Perspective
  alias FormFlow.Context
  alias FormFlow.Data.Instances
  alias FormFlow.Data.Instances.FlowProgress
  alias FormFlow.Data.Templates

  # What a flow is governed by when its context has no types at all — a
  # "forms" flow always has the page's flow types, so this is reached only by
  # a host passing [] or a stranded position answered for by a "subflows"
  # root.
  @default_type %FormFlow.Config.Flows.Type{
    module: FormFlow.Config.Flows.Type.Default,
    name: "Default"
  }

  # What a form is governed by when the page has no form types at all — a
  # host passing [].
  @default_form_type %FormFlow.Config.Forms.Type{
    module: FormFlow.Config.Forms.Type.Default,
    name: "Default"
  }

  def assigns(socket) do
    %{context: context, tree: tree, version: version, form_instance: form_instance} =
      resolve(socket.assigns)

    type = flow_type(context, socket.assigns)
    {visible?, editable?} = access(type, context, socket.assigns)
    form_type = form_type(context, socket.assigns)

    socket
    |> assign(
      form: context.form_progress,
      forms: context.flow_progress,
      form_instance: form_instance,
      type: type,
      form_type: form_type,
      initial_data:
        form_instance && form_type.module.initial_data(context, socket.assigns.callback_data),
      context: context,
      visible?: visible?,
      editable?: editable?,
      start_error: nil,
      mount_error: nil,
      navigate_to: nil,
      clickable: clickable(type, context, socket.assigns),
      flow_name: (tree && tree.flow.name) || "Untitled flow",
      form_label:
        (context.form_progress && FlowProgress.qualified_label(context.form_progress)) || "Form"
    )
    |> parse(version)
  end

  @doc """
  Everything a page or a request addressing one position needs loaded, from
  a plain map of the same attrs `assigns/1` reads off a socket:
  `:flow_instance`, `:path`, `:user_id`, `:tenant_id`, `:perspectives`, and
  `:flow_types`.

  Returns `%{tree: …, forms: …, form_instance: …, version: …, context: …}` —
  the resolved template tree, the whole journey's progress, the live
  instance at the position (`nil` until it is started), the version it is
  pinned to, and the `FormFlow.Context` the two form pages and every
  callback are given.

  It takes assigns rather than a socket because it is read from outside
  LiveView too: `FormFlow.Web.Downloads` resolves a download's position
  through this, so a printed form and the page it was printed from can
  never disagree about what the answers are.
  """
  def resolve(assigns) do
    %{flow_instance: flow_instance, path: path} = assigns
    tree = Templates.Flows.resolve_tree(flow_instance.flow_id)
    forms = FlowProgress.forms(tree, Instances.Flows.form_instances(flow_instance))

    # An instance already at the position is simply used — including a
    # stranded one, whose position the tree no longer has
    form_instance = Instances.Forms.get_at(flow_instance, path)

    version = form_instance && Templates.Forms.get_version(form_instance.template_form_version_id)

    form = version && Templates.Forms.get(version.template_form_id)

    context = %Context{
      context(assigns, tree, forms)
      | form: form,
        form_version: version,
        form_type_property_values: FormFlow.Config.Forms.Type.property_values(form),
        form_instance: form_instance
    }

    %{tree: tree, forms: forms, form_instance: form_instance, version: version, context: context}
  end

  @doc """
  The `FormFlow.Context` of the form at `path` in a flow instance: the form,
  its flow's forms in order, and the template lineage they sit in. A stranded
  position is no longer one of the tree's forms, so the flow instance's own
  flow answers for it.
  """
  def context(%{flow_instance: flow_instance, path: path} = assigns, tree, forms) do
    form = FlowProgress.find_form(forms, path)

    subflow = (form && form.flow) || (tree && tree.flow)

    context = %Context{
      user_id: assigns.user_id,
      tenant_id: assigns.tenant_id,
      perspectives: Perspective.normalize(assigns.perspectives),
      flow: tree && tree.flow,
      subflow: subflow,
      subflow_node: form && List.last(form.ancestors),
      flow_type_property_values: FormFlow.Config.Flows.Type.property_values(subflow),
      flow_instance: flow_instance,
      form_progress: form,
      flow_progress: FlowProgress.forms_in_flow(forms, path),
      flow_instance_progress: forms
    }

    %Context{context | flow_perspectives: flow_perspectives(context, assigns)}
  end

  @doc """
  The `FormFlow.Config.Flows.Perspective` structs the context's `:subflow` is
  for — its stored ids resolved through the `:perspectives` its flow type
  declares (`flow_type/2`, so an unset type resolves as everywhere else).
  `[]` for a flow that names none, or names only ids the type no longer has.
  """
  def flow_perspectives(%Context{subflow: flow} = context, assigns) do
    Perspective.for_flow(flow, flow_type(context, assigns).perspectives)
  end

  @doc """
  Whether the flow type says the form at the context's `:form_progress` is
  for this viewer — `visible?/2`, the perspectives test by default. The
  pages hide, skip, and refuse a form that is not.
  """
  def visible?(type, context, assigns), do: type.module.visible?(context, assigns.callback_data)

  @doc """
  The first form of the whole flow instance the viewer can work next, in
  flow order: actionable, and visible to them. `nil` when nothing is — the
  viewer's part is done, or blocked on someone else's.
  """
  def next_visible_form(%Context{flow_instance_progress: forms} = context, assigns) do
    Enum.find(forms, fn form ->
      form_context = form_context(context, form)

      FlowProgress.actionable?(form) and
        visible?(flow_type(form_context, assigns), form_context, assigns)
    end)
  end

  # The context re-aimed at another form of the same flow instance
  defp form_context(%Context{flow_instance_progress: forms} = context, form) do
    %Context{
      context
      | subflow: form.flow,
        subflow_node: List.last(form.ancestors),
        flow_type_property_values: FormFlow.Config.Flows.Type.property_values(form.flow),
        form_progress: form,
        flow_progress: FlowProgress.forms_in_flow(forms, form.path)
    }
  end

  @doc """
  The `FormFlow.Config.Flows.Type` governing the flow at the context's
  `:subflow`: its stored `properties["form_flow_type"]` looked up among the
  page's `flow_types` (`FormFlow.Web.Templates.Shared.flow_types_for/2`, so a
  "subflows" flow has none). An unset or unrecognized value resolves to the
  first type — the defaults list the in-order wizard first, so it stays the
  baseline — and a context with no types to the library's default, so a form
  always has a type to ask.
  """
  def flow_type(%Context{subflow: flow} = context, assigns) do
    types = FormFlow.Web.Templates.Shared.flow_types_for(context, assigns)
    id = flow && flow.properties["form_flow_type"]

    Enum.find(types, &(&1.id == id)) || List.first(types) || @default_type
  end

  @doc """
  The `FormFlow.Config.Forms.Type` governing the form at the context's
  `:form`: its stored `properties["form_type"]` looked up among the page's
  `form_types`, with the same fallbacks as `flow_type/2` — the first type,
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
  `:mount_error` — the counterpart of the listing refusing to start a flow it
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
  def on_mount(socket, on_ok \\ & &1) do
    if flow_in_scope?(socket.assigns) do
      host_on_mount(socket, on_ok)
    else
      assign(socket, :mount_error, "This flow is not available here.")
    end
  end

  # The page's `flows` attr is its scope: an instance is in it when its flow
  # is one of the flows the attr names. No attr, or no instance in scope
  # (the listing), and every instance is.
  defp flow_in_scope?(%{flow_instance: %{flow_id: flow_id}, flows: flows} = assigns)
       when is_list(flows) do
    Enum.any?(resolve_flows(flows, Map.get(assigns, :tenant_id)), &(&1.id == flow_id))
  end

  defp flow_in_scope?(_assigns), do: true

  @doc """
  The page's `flows` attr resolved to `FormFlow.Data.Templates.Flow` structs:
  structs pass through, slugs are looked up in the tenant, `nil` entries and
  flows of another tenant are dropped. `nil` — the host named none in
  particular — is every root flow of the tenant not made reusable. These are
  the flows the page is about: what the listing offers to start, and the only
  flows whose instances the instance pages render.
  """
  def resolve_flows(nil, tenant_id) do
    Templates.Flows.list(tenant_id: tenant_id) |> Enum.reject(& &1.made_reusable_at)
  end

  def resolve_flows(flows, tenant_id) when is_list(flows) do
    flows
    |> Enum.map(fn
      %Templates.Flow{} = flow -> flow
      slug when is_binary(slug) -> Templates.Flows.get_by_slug(slug, tenant_id: tenant_id)
      nil -> nil
    end)
    |> Enum.reject(&is_nil/1)
    |> in_tenant(tenant_id)
  end

  defp in_tenant(flows, nil), do: flows
  defp in_tenant(flows, tenant_id), do: Enum.filter(flows, &(&1.tenant_id == tenant_id))

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
  type allows editing there — the instance is created, which pins the form
  version — and the page's assigns are derived again, since the first
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

  defp start_instance(flow_instance, path, %{user_id: user_id, tenant_id: tenant_id}) do
    case Instances.Forms.update_status(flow_instance, path, :in_progress,
           user_id: user_id,
           tenant_id: tenant_id
         ) do
      {:ok, form_instance} ->
        {:ok, form_instance}

      {:error, :no_published_version} ->
        {:error, "That form has no published version yet — ask an administrator to publish it."}

      {:error, _reason} ->
        {:error, "Could not start this form. The flow may have changed — reload."}
    end
  end

  # A definition is admin-authored input — a malformed one becomes an inline
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

  # Whether the form is for this viewer, and whether they may edit it now — a
  # position the tree no longer has is neither, and one that is not visible
  # is never editable
  defp access(_type, %Context{form_progress: nil}, _assigns), do: {false, false}

  defp access(type, context, assigns) do
    visible? = visible?(type, context, assigns)

    {visible?, visible? and editable?(type, context, assigns)}
  end

  defp editable?(type, context, assigns),
    do: type.module.editable?(context, assigns.callback_data)

  # The sibling forms the user may jump to — asked of the type one form at a
  # time. Navigating to the one this page addresses would do nothing, so it
  # is never among them, which is what leaves an in-order wizard's progress
  # entirely inert: the only form it lets the user edit is that one.
  defp clickable(type, context, assigns) do
    for sibling <- context.flow_progress,
        sibling.path != assigns.path,
        editable?(type, %{context | form_progress: sibling}, assigns),
        into: MapSet.new(),
        do: sibling.path
  end
end
