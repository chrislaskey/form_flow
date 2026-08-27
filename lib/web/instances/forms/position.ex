defmodule FormFlow.Web.Instances.Forms.Position do
  @moduledoc """
  `FormFlow.Web.Instances.Forms.Position` resolves what is at the position a
  form page addresses, the same way for both pages that address one.

  `FormFlow.Web.Instances.Forms.Show` and `FormFlow.Web.Instances.Forms.Edit`
  are each addressed by a flow instance plus a `path`, and both need the same
  answers before they can render anything: which form the path names, what
  its "forms" flow's `FormFlow.Flows.Types` module makes of it, whether the
  filler may work there, and which live instance — if any — holds the answers.
  Only what they *do* with those answers differs, so the resolving lives here
  rather than in either of them, where two copies of one gate could drift
  apart.

  `resolve/2` reads the page's `flow_instance`, `path`, and host config from
  the socket and writes the lot back onto it:

    * `:form` - the `FormFlow.Data.Instances.FormProgress` at this path, or
      nil when the flow no longer has the position
    * `:forms` - every form of the "forms" flow this one belongs to, in order
    * `:form_instance` - the live `FormFlow.Data.Instances.Form`, or nil
    * `:type` - the `FormFlow.Flows.Types` module governing this form's flow,
      which Edit asks again after a submit to find where to go next
    * `:openable?` - whether the flow's type allows work here
    * `:open_error` - why `open: true` could not open the position, or nil
    * `:show_progress?` / `:clickable` - what
      `FormFlow.Web.Instances.Components.FlowProgress` needs
    * `:flow_name` / `:form_label` - what the breadcrumb needs
    * `:parsed` / `:parse_error` - the pinned definition, through `DynamicForm`

  `open: true` is Edit's mode and the one write in here: an absent instance is
  created when the type allows it (create-on-open, which pins the version).
  Show never passes it.
  """

  import Phoenix.Component, only: [assign: 2]

  alias FormFlow.Config.Context
  alias FormFlow.Data.Instances
  alias FormFlow.Data.Instances.FlowProgress
  alias FormFlow.Data.Templates
  alias FormFlow.Flows.Types

  def resolve(socket, opts \\ []) do
    %{flow_instance: flow_instance, path: path} = socket.assigns
    tree = Templates.Flows.resolve_tree(flow_instance.flow_id)
    forms = FlowProgress.forms(tree, Instances.Flows.form_instances(flow_instance))
    form = FlowProgress.find_form(forms, path)
    type = type_module(socket.assigns, tree, form)

    openable? =
      not is_nil(form) and type.openable?(form, FlowProgress.forms_in_flow(forms, path))

    {form_instance, open_error, forms} =
      resolve_instance(socket, tree, forms, openable?, Keyword.get(opts, :open, false))

    form = FlowProgress.find_form(forms, path)
    in_flow = FlowProgress.forms_in_flow(forms, path)

    socket
    |> assign(
      form: form,
      forms: in_flow,
      form_instance: form_instance,
      type: type,
      openable?: openable?,
      open_error: open_error,
      show_progress?: type.show_progress?(in_flow),
      clickable: clickable(in_flow, path, type),
      flow_name: (tree && tree.flow.name) || "Untitled flow",
      form_label: (form && FlowProgress.qualified_label(form)) || "Form"
    )
    |> parse(form_instance)
  end

  # An instance already at the position is simply used — including a stranded
  # one, whose position the tree no longer has. Otherwise Edit opens it, and
  # the progress is derived again afterwards: the first derivation ran before
  # the open, so it still called this form available rather than in progress.
  defp resolve_instance(socket, tree, forms, openable?, open?) do
    %{flow_instance: flow_instance, path: path} = socket.assigns

    case Instances.Forms.get_at(flow_instance, path) do
      %Instances.Form{} = form_instance ->
        {form_instance, nil, forms}

      nil when open? and openable? ->
        case open(flow_instance, path, socket.assigns.user_id) do
          {:ok, opened} ->
            {opened, nil, FlowProgress.forms(tree, Instances.Flows.form_instances(flow_instance))}

          {:error, message} ->
            {nil, message, forms}
        end

      nil ->
        {nil, nil, forms}
    end
  end

  defp open(flow_instance, path, user_id) do
    case Instances.Forms.update_status(flow_instance, path, :in_progress, user_id: user_id) do
      {:ok, form_instance} ->
        {:ok, form_instance}

      {:error, :no_published_version} ->
        {:error, "That form has no published version yet — ask an administrator to publish it."}

      {:error, _reason} ->
        {:error, "Could not open this form. The flow may have changed — reload."}
    end
  end

  # A definition is admin-authored input — a malformed one becomes an inline
  # error, never a crash loop (the same posture as the preview).
  defp parse(socket, nil), do: assign(socket, parsed: nil, parse_error: nil)

  defp parse(socket, form_instance) do
    version = Templates.Forms.get_version(form_instance.template_form_version_id)

    assign(socket, parsed: DynamicForm.Parser.JSON.parse!(version.definition), parse_error: nil)
  rescue
    error -> assign(socket, parsed: nil, parse_error: Exception.message(error))
  end

  # The sibling forms the filler may jump to. Navigating to the one this page
  # addresses would do nothing, so it is never among them — which is what
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
  # through the host's FormFlow.Config (or the library's defaults). A stranded
  # position is no longer one of the tree's forms, so the flow instance's own
  # flow answers for it.
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
end
