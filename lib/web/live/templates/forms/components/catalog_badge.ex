defmodule FormFlow.Web.Templates.Forms.Components.CatalogBadge do
  @moduledoc """
  `FormFlow.Web.Templates.Forms.Components.CatalogBadge` function component
  says, on a step's form page, that the step reuses a form from the catalog -
  and lists every flow that form is used in, since an edit or a publish here
  reaches all of them.

  It also says how a step leaves a reused form: removed from the canvas and
  added again, the new step's chooser offers Copy form for a private copy of
  it.

  Rendered by `FormFlow.Web.Templates.Forms.Show`, `Edit`, and `Details`
  when the page was reached through a step whose form has no owner. A
  catalog form's own page has no step, and says "Used in" instead.
  """

  use Phoenix.Component

  alias FormFlow.Web.Components.Core
  alias FormFlow.Web.Templates.Shared

  attr(:form, :map, required: true, doc: "the catalog form the step points at")
  attr(:usages, :list, required: true, doc: "`Flows.form_usages/1` for the form")
  attr(:components, :atom, default: nil)
  attr(:class, :any, default: nil)

  def catalog_badge(assigns) do
    ~H"""
    <div class={[
      "mb-3 mt-3 flex items-start gap-x-4 rounded-md border border-zinc-300 bg-white px-3 py-3 text-sm text-zinc-700",
      @class
    ]}>
      <Core.badge kind={:info} components={@components}>reusable form</Core.badge>
      <div class="-mt-1 flex flex-col gap-y-1">
        <div class="text-lg">{@form.name}</div>
        <%!-- One line per place, not one per step: two steps of a flow
              pointing here read as one use (`Shared.usage_labels/1`) --%>
        <div :if={@usages != []}>
          This reusable form is used in the following flows:
          <ul class="mb-2 ml-4 list-disc">
            <li :for={label <- Shared.usage_labels(@usages)}>{label}</li>
          </ul>
        </div>
        <div class="text-sm">
          To stop reusing the form in this flow, remove the step from the canvas and add it again -
          the new step gets a form of its own (or a copy of this one, through Copy form). Users who
          started this step are stranded.
        </div>
      </div>
    </div>
    """
  end
end
