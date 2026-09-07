defmodule FormFlow.Web.Templates.Forms.Components.CatalogBadge do
  @moduledoc """
  `FormFlow.Web.Templates.Forms.Components.CatalogBadge` function component
  says, on a step's form page, that the step reuses a catalog form — and
  where else that form is used, since an edit or a publish here reaches all
  of those places. "Catalog" is the word `/forms` uses for itself.

  It also says how a step leaves a catalog form: removed from the canvas
  and added again, the new step's chooser offers Copy form for a private
  copy of the catalog form.

  Rendered by `FormFlow.Web.Templates.Forms.Show` and `Edit` when the page
  was reached through a step whose form has no owner. A catalog form's own
  page has no step, and says "Used in" instead.
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
    <div class={["flex flex-wrap items-center gap-2 text-xs text-zinc-600", @class]}>
      <Core.badge kind={:info} components={@components}>Catalog form</Core.badge>
      <span>
        “{@form.name}” · used in {Enum.join(Shared.usage_labels(@usages), ", ")}.
      </span>
      <span>
        To stop reusing it, remove this step from the canvas and add it again — the new step gets a
        form of its own (or a copy of this one, through Copy form); users who started this step are
        stranded.
      </span>
    </div>
    """
  end
end
