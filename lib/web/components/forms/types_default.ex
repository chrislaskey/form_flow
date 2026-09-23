defmodule FormFlow.Web.Components.Forms.Types.Default do
  @moduledoc """
  `FormFlow.Config.Forms.Type`'s defaults - what every form type inherits for
  the callbacks it doesn't override: the form renders whatever the user has
  answered so far, it renders as the form alone - editable on the edit page,
  read-only on the Show page - nothing is recorded when it is submitted, and
  nothing happens afterwards.

  ## Prefilling from another flow

  The one property the defaults declare, so every form type that ships has
  it: **"Prefill with answers from"**, `"prefill_with_answers_from"`, a
  `:related_form_in_any_flow` naming a form of another flow. Set, this form
  starts filled in with what **the same user** answered at that form, in
  their most recent journey of the flow holding it. Unset - which is how
  every form starts - nothing is prefilled and `initial_data/2` is the
  stored answers alone.

  A renewal is what it is for: the 2027 licence prefilled from the 2026 one,
  so the owner does not retype an address that has not changed. It is not a
  renewal *type*, because a renewal form is often a review form too, and a
  type is a kind while this is a question.

  The walk is: the user's journeys of the named flow, newest first
  (`FormFlow.Data.Instances.Flows.list/1`); in each, the form completed at
  the named position (`FormFlow.Data.Instances.FlowProgress.forms/2`); its
  answers. The first journey that has one wins. Nothing found is `%{}` and
  silent - a pointer at a deleted flow prefills nothing and says nothing to
  the user, and `FormFlow.Data.Templates.Flows.Health` tells the admin
  instead. A viewer with no `user_id` gets `%{}`: their last year cannot be
  named.

  The answers go **under** the user's own, merged by question name, so a
  prefill can never replace something they typed, a question the source
  asked and this form does not is ignored, and a question only this form
  asks starts empty.

  Privacy needs no care here: a user is shown their own answers from their
  own earlier journey, and nothing crosses between people.

  Not to be confused with a *prefill*
  (`FormFlow.Data.Templates.Form.Prefill`), which is a named answer set an
  admin saved, the same for everybody, chosen by hand at the form. This is
  one user's own answers, applied without being asked for.
  """

  use FormFlow.Config.Forms.Type
  use Phoenix.Component

  alias FormFlow.Config.Forms.Type
  alias FormFlow.Config.Property
  alias FormFlow.Context
  alias FormFlow.Data.Instances
  alias FormFlow.Data.Instances.FlowProgress
  alias FormFlow.Data.Templates
  alias FormFlow.Web.CoreComponents

  @prefill_property "prefill_with_answers_from"

  @doc """
  The properties every form type inherits: the form to prefill from - see
  "Prefilling from another flow". A type declaring its own puts them in
  front of these, the way `FormFlow.Config.Forms.Type.defaults/0` does for
  the review type.
  """
  @spec properties() :: [Property.t()]
  def properties do
    [
      %Property{
        id: @prefill_property,
        name: "Prefill with answers from",
        description:
          "A form in another flow. This one starts filled in with what the same user " <>
            "answered there, under anything they have typed here. Cleared when this flow " <>
            "is copied.",
        type: :related_form_in_any_flow,
        clear_on_copy: true
      }
    ]
  end

  @impl true
  def initial_data(%Context{form_instance: nil}, _callback_data), do: %{}

  def initial_data(%Context{form_instance: %{data: data}} = context, _callback_data) do
    Map.merge(prefilled_answers(context), data || %{})
  end

  # `hide_submit` is the edit page's: it draws Submit in its pinned header,
  # as a button whose `form` attribute names this form, so the form's own
  # button would be a second one
  @impl true
  def edit_component(assigns) do
    assigns = Map.put_new(assigns, :hide_submit, false)

    ~H"""
    <div class="max-w-md">
      <DynamicForm.form
        id={@id}
        instance={@instance}
        data={@data}
        on_success={@on_success}
        hide_submit={@hide_submit}
        components={@components || CoreComponents}
      />
    </div>
    """
  end

  @impl true
  def show_component(assigns) do
    ~H"""
    <%!-- Read-only is the whole job: the disabled fieldset switches off every
          control inside (a native HTML behavior) and the submit button is
          hidden. DynamicForm's render_only is NOT this - it is a
          parent-owns-the-form mode requiring a Phoenix.HTML.Form. --%>
    <fieldset disabled class="max-w-md">
      <DynamicForm.form
        id={@id}
        instance={@instance}
        data={@data}
        hide_submit
        components={@components || CoreComponents}
      />
    </fieldset>
    """
  end

  @impl true
  def snapshot(_context, _callback_data), do: %{}

  @impl true
  def handle_complete(_context, _callback_data), do: :ok

  # --- prefilling from another flow -----------------------------------------

  # Nobody to read a last journey for, or no pointer set: the common path,
  # and no query on it
  defp prefilled_answers(%Context{user_id: nil}), do: %{}

  defp prefilled_answers(%Context{} = context) do
    value = Type.property_values(context.form)[@prefill_property]

    case Property.parse_flow_position(value) do
      nil -> %{}
      {flow_id, path} -> answers_at(flow_id, path, context)
    end
  end

  # This user's journeys of the named flow, newest first, and the first of
  # them with a completed form at the named position. Every journey is of
  # the one flow, so its tree is resolved once.
  defp answers_at(flow_id, path, %Context{user_id: user_id, tenant_id: tenant_id}) do
    case Instances.Flows.list(user_id: user_id, tenant_id: tenant_id, flow: flow_id) do
      [] ->
        %{}

      journeys ->
        case Templates.Flows.resolve_tree(flow_id) do
          nil -> %{}
          tree -> Enum.find_value(journeys, %{}, &submitted_at(&1, tree, path))
        end
    end
  end

  # The stored answers of the completed form at `path`, read the way the
  # pages read progress: the resolved tree and every form instance of the
  # journey, so a superseded instance is passed over and a position the flow
  # no longer has is not a form of it
  defp submitted_at(%Instances.Flow{} = journey, tree, path) do
    tree
    |> FlowProgress.forms(Instances.Flows.form_instances(journey))
    |> Enum.find_value(fn
      %{path: ^path, status: :completed, instance: %{data: data}} -> data
      _other -> nil
    end)
  end
end
