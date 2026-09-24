defmodule FormFlow.Web.Templates.Flows.Components.CopyDialog do
  @moduledoc """
  `FormFlow.Web.Templates.Flows.Components.CopyDialog` function component
  renders the copy dialog shared by the flow Show page and the flows index:
  the copy's name and slug, prefilled with what
  `FormFlow.Data.Templates.Flows.copy/2` would pick, and one sentence on what
  comes along. On screen the action is *Duplicate* - the canvas's Copy means
  "to the clipboard" - while the code, the events, and this module keep the
  word `copy` (see `FormFlow.Web.Templates.Flows.Show`).

  Under that sentence, when there is any, the dialog lists the settings the
  copy will leave empty (`FormFlow.Web.Templates.Shared.cleared_by_copy/3`):
  a setting that points out of this flow is cleared rather than carried
  forward, and a copy that says nothing about it would arrive still
  pointing at the flow it was copied from - resolving perfectly, at the
  wrong flow. Most copies clear nothing and the list is not drawn.

  The caller owns the flow around it: opening, the `copy` event the form
  submits to `target` with `name` and `slug`, the `cancel_copy` event the
  Cancel button sends, and the error it hands back when the copy is refused -
  a taken slug, the one field an admin can fix by typing, so the dialog stays
  open with the message rather than closing over it.
  """

  use Phoenix.Component

  alias FormFlow.Web.Components.Core
  alias FormFlow.Web.Components.Dialog

  attr(:flow, :map, required: true, doc: "the root flow being copied")
  attr(:name, :string, required: true, doc: "the copy's name as prefilled")
  attr(:slug, :string, required: true, doc: "the copy's slug as prefilled")
  attr(:target, :any, required: true, doc: "the LiveComponent receiving copy and cancel_copy")
  attr(:error, :string, default: nil, doc: "why the last attempt was refused")

  attr(:cleared, :list,
    default: [],
    doc: "what the copy will leave empty, from Shared.cleared_by_copy/3"
  )

  attr(:components, :atom, default: nil)

  def copy_dialog(assigns) do
    ~H"""
    <Dialog.dialog width={:medium}>
      <p class="mb-1 text-sm font-semibold text-zinc-900">Duplicate this flow?</p>
      <p class="mb-3 text-xs text-zinc-500">
        A duplicate of “{@flow.name}” with its steps, connections, subflows, and forms.
        Forms from the catalog stay shared; the rest is the copy's own.
      </p>

      <div :if={@cleared != []} class="mb-3 text-xs text-zinc-500">
        <p>Left empty in the copy, for an administrator to set again:</p>
        <ul class="mt-1 list-disc pl-4">
          <li :for={{name, count} <- @cleared}>{name} - set in {places(count)}</li>
        </ul>
      </div>

      <form phx-submit="copy" phx-target={@target} class="space-y-3">
        <Core.input components={@components} type="text" name="name" label="Name" value={@name} />

        <div>
          <Core.input components={@components} type="text" name="slug" label="Slug" value={@slug} />
          <span class="mt-1 block text-xs text-zinc-500">
            A stable name for looking the copy up in code - lowercase letters, numbers, _ and -.
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
            Duplicate flow
          </Core.button>
        </div>
      </form>
    </Dialog.dialog>
    """
  end

  defp places(1), do: "1 place"
  defp places(count), do: "#{count} places"
end
