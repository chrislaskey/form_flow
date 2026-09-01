defmodule FormFlow.Web.Instances.Forms.Position do
  @moduledoc """
  `FormFlow.Web.Instances.Forms.Position` resolves what is at the position a
  form page addresses, the same way for both pages that address one.

  `FormFlow.Web.Instances.Forms.Show` and `FormFlow.Web.Instances.Forms.Edit`
  are each addressed by a flow instance plus a `path`, and both need the same
  answers before they can render anything: which form the path names, whether
  the filler may work there, and which live instance — if any — holds the
  answers. Only what they *do* with those answers differs, so the resolving
  lives here rather than in either of them, where two copies of one gate
  could drift apart.

  `resolve/2` reads the page's `flow_instance` and `path` from the socket and
  writes the lot back onto it:

    * `:form` - the `FormFlow.Data.Instances.FormProgress` at this path, or
      nil when the flow no longer has the position
    * `:forms` - every form of the "forms" flow this one belongs to, in order
    * `:form_instance` - the live `FormFlow.Data.Instances.Form`, or nil
    * `:openable?` - whether the flow allows work here
      (`FormFlow.Data.Instances.Flows.Progress.actionable?/1`)
    * `:open_error` - why `open: true` could not open the position, or nil
    * `:show_progress?` / `:clickable` - what
      `FormFlow.Web.Instances.Components.Flows.Progress` needs
    * `:flow_name` / `:form_label` - what the breadcrumb needs
    * `:parsed` / `:parse_error` - the pinned definition, through `DynamicForm`

  `open: true` is Edit's mode and the one write in here: an absent instance is
  created when the flow allows it (create-on-open, which pins the version).
  Show never passes it.
  """

  import Phoenix.Component, only: [assign: 2]

  alias FormFlow.Data.Instances
  alias FormFlow.Data.Instances.Flows.Progress
  alias FormFlow.Data.Templates

  def resolve(socket, opts \\ []) do
    %{flow_instance: flow_instance, path: path} = socket.assigns
    tree = Templates.Flows.resolve_tree(flow_instance.flow_id)
    forms = Progress.forms(tree, Instances.Flows.form_instances(flow_instance))
    form = Progress.find_form(forms, path)
    openable? = not is_nil(form) and Progress.actionable?(form)

    {form_instance, open_error, forms} =
      resolve_instance(socket, tree, forms, openable?, Keyword.get(opts, :open, false))

    form = Progress.find_form(forms, path)
    in_flow = Progress.forms_in_flow(forms, path)

    socket
    |> assign(
      form: form,
      forms: in_flow,
      form_instance: form_instance,
      openable?: openable?,
      open_error: open_error,
      show_progress?: length(in_flow) > 1,
      clickable: clickable(in_flow, path),
      flow_name: (tree && tree.flow.name) || "Untitled flow",
      form_label: (form && Progress.qualified_label(form)) || "Form"
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
            {opened, nil, Progress.forms(tree, Instances.Flows.form_instances(flow_instance))}

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

    assign(socket,
      parsed: DynamicForm.Parser.FromData.parse!(version.definition),
      parse_error: nil
    )
  rescue
    error -> assign(socket, parsed: nil, parse_error: Exception.message(error))
  end

  # The sibling forms the filler may jump to: the ones the flow allows work
  # on. Navigating to the one this page addresses would do nothing, so it is
  # never among them.
  defp clickable(in_flow, path) do
    for form <- in_flow,
        form.path != path,
        Progress.actionable?(form),
        into: MapSet.new(),
        do: form.path
  end
end
