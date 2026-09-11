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
  alias FormFlow.Web.CoreComponents

  attr(:id, :string, required: true, doc: "the DynamicForm component id")
  attr(:counts, :map, required: true, doc: "instance counts by status, for the blast radius")

  attr(:counts_by_flow, :list,
    default: [],
    doc:
      "the same counts attributed to root flows (`Forms.instance_counts_by_flow/1`) — " <>
        "how an admin learns a catalog form's publish reaches several flows"
  )

  attr(:target, :any, required: true, doc: "the LiveComponent receiving cancel_publish")
  attr(:on_success, :any, required: true, doc: "1-arity payload callback performing the publish")
  attr(:components, :atom, default: nil)

  attr(:saved_note, :boolean,
    default: false,
    doc:
      "warn that publishing uses the last saved definition — the Edit page, and only " <>
        "while it holds unsaved edits for that warning to be about"
  )

  def publish_dialog(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/40">
      <div class="max-h-[90vh] w-[28rem] overflow-y-auto rounded-md border border-zinc-300 bg-white p-4 shadow-lg">
        <p class="mb-1 font-semibold text-zinc-900">Publish this draft?</p>
        <p class="mb-1 text-sm text-zinc-500">
          {@counts["in_progress"]} in progress and {@counts["completed"]} completed
          instance(s) exist for this form.
        </p>
        <%!-- Which flows those are in: publishing a shared form migrates the
              instances of every flow using it, and this is the moment to
              learn that --%>
        <p :for={line <- attribution(@counts_by_flow)} class="mb-1 text-sm text-zinc-500">
          {line}
        </p>

        <p :if={@saved_note} class="my-3 text-sm text-amber-600">
          <span class="font-bold">Warning!</span> Publishing only uses the last saved definition — unsaved edits are not included.
          Save first.
        </p>

        <DynamicForm.form
          id={@id}
          submit_text="Publish"
          on_success={@on_success}
          components={@components || CoreComponents}
          hide_submit
        >
          <:field
            type="radiogroup"
            name="preset"
            label="How should existing users be treated?"
            required
            default="small_fix"
            options={[
              {"Bug fix — in-progress users move to this version and keep their answers (they may see new required fields); completed instances are untouched.",
               "bug_fix"},
              {"Small fix — existing users keep the version they started; new users get this one.",
               "small_fix"},
              {"Big fix — everyone must fill this version out: #{@counts["in_progress"]} in-progress instance(s) will be reset and #{@counts["completed"]} completed instance(s) reopened. Prior answers are kept in the audit trail.",
               "big_fix"}
            ]}
            metadata={%{"style" => "vertical"}}
          />
        </DynamicForm.form>

        <div class="mt-2 flex justify-end gap-2">
          <Core.button
            components={@components}
            phx-click="cancel_publish"
            phx-target={@target}
            class="rounded-md border border-zinc-300 px-2 py-1 text-sm hover:border-zinc-400"
          >
            Cancel
          </Core.button>
          <DynamicForm.submit_button form={@id}>
            Save Profile
          </DynamicForm.submit_button>
        </div>
      </div>
    </div>
    """
  end

  # One line per status with instances: "In progress: 1 in Dog License, 1 in
  # Cat License". Standalone instances — no flow — are said to be so.
  defp attribution(counts_by_flow) do
    for {status, key} <- [{"In progress", :in_progress}, {"Completed", :completed}],
        parts = for(%{^key => n} = entry <- counts_by_flow, n > 0, do: "#{n} in #{place(entry)}"),
        parts != [] do
      "#{status}: #{Enum.join(parts, ", ")}"
    end
  end

  defp place(%{flow_name: nil}), do: "no flow (filled standalone)"
  defp place(%{flow_name: name}), do: name
end
