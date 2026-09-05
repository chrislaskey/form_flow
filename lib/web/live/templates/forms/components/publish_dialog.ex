defmodule FormFlow.Web.Templates.Forms.Components.PublishDialog do
  @moduledoc """
  `FormFlow.Web.Templates.Forms.PublishDialog` function component renders the
  publish dialog shared by the form Show and Edit pages: the three
  plain-language presets (bug / small / big fix) as a `DynamicForm` radiogroup,
  with the blast radius restated before anything moves.

  The caller owns the flow around it: opening (only after the first publish —
  with no published history there is nobody to migrate), the `on_success`
  callback that performs the publish, and the `cancel_publish` event the
  Cancel button sends to `target`.
  """

  use Phoenix.Component

  alias FormFlow.Web.Components.Core

  attr(:id, :string, required: true, doc: "the DynamicForm component id")
  attr(:counts, :map, required: true, doc: "instance counts by status, for the blast radius")
  attr(:target, :any, required: true, doc: "the LiveComponent receiving cancel_publish")
  attr(:on_success, :any, required: true, doc: "1-arity payload callback performing the publish")
  attr(:components, :atom, default: nil)

  attr(:saved_note, :boolean,
    default: false,
    doc: "warn that publishing uses the last saved definition (the Edit page)"
  )

  def publish_dialog(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/40">
      <div class="max-h-[90vh] w-[28rem] overflow-y-auto rounded-md border border-zinc-300 bg-white p-4 shadow-lg">
        <p class="mb-1 text-sm font-semibold text-zinc-900">Publish this draft?</p>
        <p class="mb-1 text-xs text-zinc-500">
          {@counts["in_progress"]} in progress and {@counts["completed"]} completed
          instance(s) exist for this form.
        </p>
        <p :if={@saved_note} class="mb-1 text-xs text-amber-700">
          Publishing uses the last saved definition — unsaved edits are not included.
          Save first.
        </p>

        <DynamicForm.form id={@id} submit_text="Publish" on_success={@on_success}>
          <:field
            type="radiogroup"
            name="preset"
            label="How should existing users be treated?"
            required
            default="small_fix"
            options={[
              {"Small fix — existing users keep the version they started; new users get this one.",
               "small_fix"},
              {"Bug fix — in-progress users move to this version and keep their answers (they may see new required fields); completed instances are untouched.",
               "bug_fix"},
              {"Big fix — everyone must fill this version out: #{@counts["in_progress"]} in-progress instance(s) will be reset and #{@counts["completed"]} completed instance(s) reopened. Prior answers are kept in the audit trail.",
               "big_fix"}
            ]}
            metadata={%{"style" => "vertical"}}
          />
        </DynamicForm.form>

        <div class="mt-2 flex justify-end">
          <Core.button
            components={@components}
            phx-click="cancel_publish"
            phx-target={@target}
            class="rounded-md border border-zinc-300 px-2 py-1 text-xs hover:border-zinc-400"
          >
            Cancel
          </Core.button>
        </div>
      </div>
    </div>
    """
  end
end
