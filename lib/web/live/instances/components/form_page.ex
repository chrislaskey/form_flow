defmodule FormFlow.Web.Instances.Components.FormPage do
  @moduledoc """
  `FormFlow.Web.Instances.Components.FormPage` function components are the
  frame both form pages put around their content — the breadcrumb up to the
  flow instance, and the panel that stands in for a form when there is none to
  render.

  The wording of that panel belongs to the page, not here: Show says a form
  hasn't been started, Edit says it can't be opened or is already submitted.
  Only the chrome is shared.
  """

  use Phoenix.Component

  alias FormFlow.Web.Instances.Paths

  attr(:base, :string, required: true)
  attr(:flow_instance, :map, required: true)
  attr(:flow_name, :string, required: true)
  attr(:label, :string, required: true, doc: "the form's own label, the last crumb")

  def breadcrumb(assigns) do
    ~H"""
    <div class="mb-2 text-sm font-semibold">
      <.link navigate={Paths.flows_path(@base)} class="hover:underline">Flows</.link>
      <span class="text-zinc-400">/</span>
      <.link navigate={Paths.flow_path(@base, @flow_instance.id)} class="hover:underline">
        {@flow_name}
      </.link>
      <span class="text-zinc-400">/</span>
      {@label}
    </div>
    """
  end

  attr(:message, :string, required: true)
  slot(:inner_block, doc: "the page's own links out of here")

  def notice(assigns) do
    ~H"""
    <div class="rounded-md border border-zinc-300 bg-zinc-50 px-3 py-2 text-sm text-zinc-600">
      <p>{@message}</p>
      <p class="mt-2 flex items-center gap-3">
        {render_slot(@inner_block)}
      </p>
    </div>
    """
  end
end
