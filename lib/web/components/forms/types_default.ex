defmodule FormFlow.Web.Components.Forms.Types.Default do
  @moduledoc """
  `FormFlow.Config.Forms.Type`'s defaults — what every form type inherits for
  the callbacks it doesn't override: the form renders whatever the user has
  answered so far, and it renders as the form alone.
  """

  use FormFlow.Config.Forms.Type
  use Phoenix.Component

  alias FormFlow.Context

  @impl true
  def initial_data(%Context{form_instance: %{data: data}}, _config_data), do: data
  def initial_data(%Context{form_instance: nil}, _config_data), do: %{}

  @impl true
  def edit_component(assigns) do
    ~H"""
    <div class="max-w-md">
      <DynamicForm.form id={@id} instance={@instance} data={@data} on_success={@on_success} />
    </div>
    """
  end
end
