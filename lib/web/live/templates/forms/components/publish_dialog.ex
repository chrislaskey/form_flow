defmodule FormFlow.Web.Templates.Forms.Components.PublishDialog do
  @moduledoc """
  `FormFlow.Web.Templates.Forms.PublishDialog` function component renders the
  publish dialog shared by the form Show and Edit pages.

  It asks the one question a publish has: what to do with the forms already
  **submitted** in flows still in progress - leave them as they are, or
  reopen them with their answers kept. Drafts always move to the new version
  and completed flows are never touched, and the dialog says so rather than
  asking. When nothing has been submitted in a flow still in progress there
  is nothing to ask, and the dialog is the counts, the sentence, and a
  Publish button.

  The caller owns the flow around it: opening (only after the first publish -
  with no published history there is nobody to migrate), the `on_success`
  callback that performs the publish with the answer, the `publish_now`
  event the question-less Publish button sends to `target`, and the
  `cancel_publish` event the Cancel button sends there.
  """

  use Phoenix.Component

  alias FormFlow.Web.Components.Core
  alias FormFlow.Web.CoreComponents
  alias FormFlow.Web.Templates.Shared

  attr(:id, :string, required: true, doc: "the DynamicForm component id")

  attr(:counts, :map,
    required: true,
    doc: "`Forms.instance_counts/1` - the forms this publish reaches, by draft / submitted"
  )

  attr(:counts_by_flow, :list,
    default: [],
    doc:
      "the same counts attributed to root flows (`Forms.instance_counts_by_flow/1`) - " <>
        "how an admin learns a catalog form's publish reaches several flows"
  )

  attr(:sweep_size, :integer,
    default: 0,
    doc:
      "`Forms.sweep_size/1` - how many flow instances a reopening publish recomputes, " <>
        "for the time estimate under the reopen option"
  )

  attr(:target, :any,
    required: true,
    doc: "the LiveComponent receiving cancel_publish and publish_now"
  )

  attr(:on_success, :any,
    required: true,
    doc: "1-arity payload callback performing the publish with the dialog's answer"
  )

  attr(:components, :atom, default: nil)

  attr(:saved_note, :boolean,
    default: false,
    doc:
      "warn that publishing uses the last saved definition - the Edit page, and only " <>
        "while it holds unsaved edits for that warning to be about"
  )

  def publish_dialog(assigns) do
    assigns = assign(assigns, :submitted, assigns.counts.submitted)

    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/40">
      <div class="max-h-[90vh] w-[28rem] overflow-y-auto rounded-md border border-zinc-300 bg-white p-4 shadow-lg">
        <p class="mb-1 font-semibold text-zinc-900">Publish this draft?</p>

        <p :if={@saved_note} class="my-3 text-sm text-amber-600">
          <span class="font-bold">Warning!</span> Publishing only uses the last saved definition - unsaved edits are not included.
          Save first.
        </p>

        <p class="mb-1 text-sm text-zinc-500">{impact_sentence()}</p>

        <%!-- Which flows the submitted forms are in: publishing a shared form
              reaches every flow using it, and this is the moment to learn that --%>
        <p class="mb-3 text-sm text-zinc-500">
          {submitted_sentence(@submitted, @counts_by_flow)}
        </p>

        <DynamicForm.form
          :if={@submitted > 0}
          id={@id}
          submit_text="Publish"
          on_success={@on_success}
          components={@components || CoreComponents}
          hide_submit
        >
          <:field
            type="radiogroup"
            name="reopen_submitted"
            label={"There are #{@submitted} flows that are in-progress that have completed this particular form. What should we do?"}
            required
            default="false"
            options={[
              {"Leave submitted forms as they are - people who already submitted this form keep the version they submitted and the form is not reopened.",
               "false"},
              {"Reopen submitted forms - the #{@submitted} users who haven't completed the full flow, but have already submitted an answer to this particular form will have it reopened, with their existing answers prefilled. Those users must check and submit again.",
               "true"}
            ]}
            metadata={%{"style" => "vertical"}}
          />
        </DynamicForm.form>

        <%!-- Inform, do not steer: reopening is how a wrong question on a
              live form gets fixed. Say what it costs when it costs enough
              to say. --%>
        <p
          :if={@submitted > 0 && Shared.sweep_estimate(@sweep_size)}
          class="mt-2 text-sm text-zinc-500"
        >
          Reopening also recomputes where every flow instance still in progress in those
          flows is open. That takes {Shared.sweep_estimate(@sweep_size)}, and this page waits.
        </p>

        <div class="mt-2 flex justify-end gap-2">
          <Core.button
            components={@components}
            phx-click="cancel_publish"
            phx-target={@target}
            class="rounded-md border border-zinc-300 px-2 py-1 text-sm hover:border-zinc-400"
          >
            Cancel
          </Core.button>
          <DynamicForm.submit_button :if={@submitted > 0} form={"#{@id}-form"}>
            Publish
          </DynamicForm.submit_button>
          <%!-- Nothing to ask: the button publishes on its own --%>
          <Core.button
            :if={@submitted == 0}
            id={"#{@id}-publish-now"}
            components={@components}
            phx-click="publish_now"
            phx-target={@target}
            class="btn btn-primary btn-sm"
          >
            Publish
          </Core.button>
        </div>
      </div>
    </div>
    """
  end

  # One string, not template text, so the sentence never wraps mid-phrase
  defp impact_sentence do
    "This change only impacts users who have not yet started the flow or are " <>
      "in-progress of completing it but haven't finished yet. " <>
      "Already completed flows are not updated."
  end

  # "3 submitted form(s) in flows still in progress, across these flows: Dog
  # License (2), Cat License (1)." Standalone instances - no flow - are said
  # to be so.
  defp submitted_sentence(0, _counts_by_flow),
    do: "No submitted forms in flows still in progress."

  defp submitted_sentence(submitted, counts_by_flow) do
    parts = for %{submitted: n} = entry <- counts_by_flow, n > 0, do: "#{place(entry)} (#{n})"

    "#{submitted} submitted form(s) in flows still in progress, across these flows: " <>
      Enum.join(parts, ", ") <> "."
  end

  defp place(%{flow_name: nil}), do: "no flow (filled standalone)"
  defp place(%{flow_name: name}), do: name
end
