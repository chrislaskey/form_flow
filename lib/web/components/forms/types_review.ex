defmodule FormFlow.Web.Components.Forms.Types.Review do
  @moduledoc """
  Form type `"review"`: a form for checking an earlier form's answers. The
  edit page shows that form read-only on the left — the same rendering the
  user-facing Show page gives submitted answers — and this form, as designed,
  editable on the right.

  Which earlier form is the type's one property, `"source"`, a
  `:related_form` an admin picks on the form edit page from the forms before
  this one in the flow. At render it resolves through
  `FormFlow.Config.Forms.Type.related_form/2` to that form as it stands in
  this flow instance. A source that doesn't resolve — unset, blank, or a path
  the flow no longer has, however it came about — is one error with one fix,
  an administrator choosing again, and is said so in its place; a source the
  user hasn't reached yet is not an error and says that instead. The review
  form itself stays editable either way.
  """

  use FormFlow.Config.Forms.Type
  use Phoenix.Component

  alias FormFlow.Config.Forms.Type
  alias FormFlow.Config.Property
  alias FormFlow.Data.Instances.FlowProgress
  alias FormFlow.Data.Templates

  @doc "The type's properties: the form to review."
  def properties do
    [
      %Property{
        id: "source",
        name: "Form to review",
        description: "The earlier form whose answers this one shows for checking.",
        type: :related_form,
        required: true
      }
    ]
  end

  @impl true
  def edit_component(assigns) do
    # A plain map from the edit page, not a component's assigns — merged, not
    # assign/2'd, and rendered without change tracking
    source = Type.related_form(assigns.context, "source")
    assigns = Map.merge(assigns, %{source: source, source_parsed: parse(source)})

    ~H"""
    <div class="flex flex-wrap gap-6">
      <section class="min-w-0 flex-1">
        <h3 class="mb-2 text-xs font-medium text-zinc-500">
          Reviewing{if @source, do: ": #{FlowProgress.qualified_label(@source)}"}
        </h3>
        <p :if={is_nil(@source)} class="text-sm text-red-600">
          The form to review is missing — an administrator needs to choose it on this form's settings.
        </p>
        <p :if={@source && is_nil(@source.instance)} class="text-sm text-zinc-500">
          {FlowProgress.qualified_label(@source)} hasn't been started yet, so there is nothing to review.
        </p>
        <%!-- Read-only the way the Show page does it: a disabled fieldset
              around the form, its submit button hidden --%>
        <fieldset :if={@source_parsed} disabled class="max-w-md">
          <DynamicForm.form
            id={"#{@id}-source-#{@source.instance.id}"}
            instance={@source_parsed}
            data={@source.instance.data}
            hide_submit
          />
        </fieldset>
      </section>
      <section class="min-w-0 flex-1">
        {Type.Default.edit_component(assigns)}
      </section>
    </div>
    """
  end

  # The source's pinned definition, parsed — nil with no instance to show,
  # and nil rather than a crash for a malformed definition (the same posture
  # as the form pages)
  defp parse(%{instance: %{template_form_version_id: version_id}}) do
    version = Templates.Forms.get_version(version_id)
    DynamicForm.Parser.FromData.parse!(version.definition)
  rescue
    _error -> nil
  end

  defp parse(_source), do: nil
end
