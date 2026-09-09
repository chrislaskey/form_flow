defmodule FormFlow.Web.Templates.Flows.Components.StatusDialog do
  @moduledoc """
  `FormFlow.Web.Templates.Flows.Components.StatusDialog` function component
  renders the dialog that changes a root flow's status from the flow Show
  page and the flows index: a dropdown of `FormFlow.Data.Templates.Flow.statuses/0`,
  and under it what the chosen status means for users and how many instances
  it reaches — the same words the Edit page draws under its own Status
  field, which is the third place a status is changed and the one that waits
  for Save.

  The caller owns the flow around it: opening, the `status_picked` event the
  form's change sends to `target` with `status` (so the summary follows the
  choice), the `save_status` event its submit sends, the `cancel_status`
  event the Cancel button sends, and the error it hands back.
  """

  use Phoenix.Component

  alias FormFlow.Web.Components.Core
  alias FormFlow.Web.Templates.Shared

  attr(:flow, :map, required: true, doc: "the root flow whose status is changing")

  attr(:status, :string,
    required: true,
    doc: "the status chosen so far — the flow's, until picked"
  )

  attr(:counts, :map, default: nil, doc: "`Shared.instance_counts/1` of the flow")
  attr(:target, :any, required: true, doc: "the LiveComponent receiving the three events")
  attr(:error, :string, default: nil, doc: "why the last attempt was refused")
  attr(:components, :atom, default: nil)

  def status_dialog(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/40">
      <div class="w-[28rem] rounded-md border border-zinc-300 bg-white p-4 shadow-lg">
        <p class="mb-1 text-sm font-semibold text-zinc-900">Change the status of “{@flow.name}”</p>
        <p class="mb-3 text-xs text-zinc-500">
          What users may do with this flow. Any status can move to any other; every
          change is logged with who made it.
        </p>

        <form phx-change="status_picked" phx-submit="save_status" phx-target={@target} class="space-y-3">
          <label class="block">
            <span class="mb-1 block text-sm font-medium text-zinc-800">Status</span>
            <select name="status" class="select select-bordered w-full">
              <option
                :for={{label, value} <- Shared.status_options()}
                value={value}
                selected={value == @status}
              >
                {label}
              </option>
            </select>
          </label>

          <div class="rounded-md border border-zinc-200 bg-zinc-50 px-3 py-2 text-sm">
            <div class="font-medium text-zinc-800">{Shared.status_label(@status)}</div>
            <p class="mt-0.5 text-xs text-zinc-600">{Shared.status_summary(@status)}</p>
            <p :if={Shared.instance_counts_sentence(@counts)} class="mt-0.5 text-xs text-zinc-600">
              {Shared.instance_counts_sentence(@counts)}
            </p>
          </div>

          <Core.error :if={@error} components={@components}>{@error}</Core.error>

          <div class="flex justify-end gap-2">
            <Core.button
              components={@components}
              type="button"
              phx-click="cancel_status"
              phx-target={@target}
              class="btn"
            >
              Cancel
            </Core.button>
            <Core.button components={@components} type="submit" variant="primary">
              Save status
            </Core.button>
          </div>
        </form>
      </div>
    </div>
    """
  end
end
