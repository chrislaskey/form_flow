defmodule FormFlow.Web.Templates.Flows.Components.CopyDialog do
  @moduledoc """
  `FormFlow.Web.Templates.Flows.Components.CopyDialog` function component
  renders the copy dialog shared by the flow Show and Edit pages: the copy's
  name and slug, prefilled with what `FormFlow.Data.Templates.Flows.copy/2`
  would pick, and one sentence on what comes along.

  The caller owns the flow around it: opening, the `copy` event the form
  submits to `target` with `name` and `slug`, the `cancel_copy` event the
  Cancel button sends, and the error it hands back when the copy is refused —
  a taken slug, the one field an admin can fix by typing, so the dialog stays
  open with the message rather than closing over it.
  """

  use Phoenix.Component

  alias FormFlow.Web.Components.Core

  attr(:flow, :map, required: true, doc: "the root flow being copied")
  attr(:name, :string, required: true, doc: "the copy's name as prefilled")
  attr(:slug, :string, required: true, doc: "the copy's slug as prefilled")
  attr(:target, :any, required: true, doc: "the LiveComponent receiving copy and cancel_copy")
  attr(:error, :string, default: nil, doc: "why the last attempt was refused")
  attr(:components, :atom, default: nil)

  attr(:saved_note, :boolean,
    default: false,
    doc: "warn that the copy is of the last saved version (the Edit page with unsaved changes)"
  )

  def copy_dialog(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/40">
      <div class="w-[28rem] rounded-md border border-zinc-300 bg-white p-4 shadow-lg">
        <p class="mb-1 text-sm font-semibold text-zinc-900">Copy this flow?</p>
        <p class="mb-3 text-xs text-zinc-500">
          A copy of “{@flow.name}” with its steps, connections, subflows, and forms.
          Forms from the catalog stay shared; the rest is the copy's own.
        </p>
        <p :if={@saved_note} class="mb-3 text-xs text-amber-700">
          The copy is made now, from the last saved version — unsaved edits are not included,
          and this page stays open with them. Save first to bring them along.
        </p>

        <form phx-submit="copy" phx-target={@target} class="space-y-3">
          <Core.input components={@components} type="text" name="name" label="Name" value={@name} />

          <div>
            <Core.input components={@components} type="text" name="slug" label="Slug" value={@slug} />
            <span class="mt-1 block text-xs text-zinc-500">
              A stable name for looking the copy up in code — lowercase letters, numbers, _ and -.
              Left blank, the flow's slug with a free suffix; a blank name is the one offered.
            </span>
          </div>

          <Core.error :if={@error} components={@components}>{@error}</Core.error>

          <div class="flex justify-end gap-2">
            <Core.button
              components={@components}
              type="button"
              phx-click="cancel_copy"
              phx-target={@target}
              class="btn"
            >
              Cancel
            </Core.button>
            <Core.button components={@components} type="submit" variant="primary">
              Copy flow
            </Core.button>
          </div>
        </form>
      </div>
    </div>
    """
  end
end
