defmodule FormFlow.Web.Instances.Components.FormPage do
  @moduledoc """
  `FormFlow.Web.Instances.Components.FormPage` is the frame both form pages
  put around their content: the breadcrumb up to the flow instance.

  What a page says when it has no form to render is not here. Those messages
  are `FormFlow.Web.Components.Core.alert/1`, written at each page's own
  `render/1` clause — Show says a form hasn't been started, Edit says it
  can't be started or is already submitted — because the wording and the way
  onward belong to the page, and the box around them belongs to every page in
  the library alike.
  """

  use Phoenix.Component

  alias FormFlow.Web.Instances.Paths

  attr(:base, :string, required: true)
  attr(:flow_instance, :map, required: true)
  attr(:flow_name, :string, required: true)
  attr(:label, :string, required: true, doc: "the form's own label, the last crumb")

  def breadcrumb(assigns) do
    ~H"""
    <div class="mb-4 flex min-h-12 flex-wrap items-center gap-2 text-base font-semibold">
      <.link navigate={Paths.flows_path(@base)} class="hover:underline">Flows</.link>
      <span class="text-base-content/40">/</span>
      <.link navigate={Paths.flow_path(@base, @flow_instance.id)} class="hover:underline">
        {@flow_name}
      </.link>
      <span class="text-base-content/40">/</span>
      {@label}
    </div>
    """
  end
end
