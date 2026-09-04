defmodule FormFlow.Web.Components.Forms.Types.Default do
  @moduledoc """
  `FormFlow.Config.Forms.Type`'s defaults — what every form type inherits for
  the callbacks it doesn't override: the form renders whatever the user has
  answered so far, it renders as the form alone — editable on the edit page,
  read-only on the Show page — nothing is recorded when it is submitted, and
  nothing happens afterwards.
  """

  use FormFlow.Config.Forms.Type
  use Phoenix.Component

  alias FormFlow.Context

  @impl true
  def initial_data(%Context{form_instance: %{data: data}}, _callback_data), do: data
  def initial_data(%Context{form_instance: nil}, _callback_data), do: %{}

  @impl true
  def edit_component(assigns) do
    ~H"""
    <div class="max-w-md">
      <DynamicForm.form id={@id} instance={@instance} data={@data} on_success={@on_success} />
    </div>
    """
  end

  @impl true
  def show_component(assigns) do
    ~H"""
    <%!-- Read-only is the whole job: the disabled fieldset switches off every
          control inside (a native HTML behavior) and the submit button is
          hidden. DynamicForm's render_only is NOT this — it is a
          parent-owns-the-form mode requiring a Phoenix.HTML.Form. --%>
    <fieldset disabled class="max-w-md">
      <DynamicForm.form id={@id} instance={@instance} data={@data} hide_submit />
    </fieldset>
    """
  end

  @impl true
  def snapshot_data(_context, _callback_data), do: %{}

  @impl true
  def handle_complete(_context, _callback_data), do: :ok
end
