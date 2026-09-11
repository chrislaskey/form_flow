defmodule FormFlow.Web.Templates.Flows.Components.StatusDialog do
  @moduledoc """
  `FormFlow.Web.Templates.Flows.Components.StatusDialog` function component
  renders the dialog that changes a root flow's status from the flow Show
  page and the flows index: a dropdown of `FormFlow.Data.Templates.Flow.statuses/0`
  (a `select` through `FormFlow.Web.Components.Core.input/1`, so a host's
  `components` draws it), and under it what the chosen status means for
  users and how many instances it reaches — the same words the Edit page
  draws under its own Status field, which is the third place a status is
  changed and the one that waits for Save.

  As a flow leaves Pre-release the dialog says how many of its instances
  were started during it (`pre_release_count`) and offers a box, **Delete
  them**, unticked; `FormFlow.Web.Templates.Shared.save_status/3` acts on
  it. The trial run is the pre-release users' and the real run begins with
  the change, so the offer is made where the change is — but the deletion
  is theirs to choose, never the default.

  The caller owns the flow around it: opening, the `status_picked` event the
  form's change sends to `target` with `status` and `delete_pre_release` (so
  the summary and the box follow the form), the `save_status` event its
  submit sends, the `cancel_status` event the Cancel button sends, and the
  error it hands back.
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

  attr(:pre_release_count, :integer,
    default: 0,
    doc: "`Shared.pre_release_count/1` of the flow — the instances the dialog offers to delete"
  )

  attr(:delete_pre_release?, :boolean, default: false, doc: "whether the offer's box is ticked")
  attr(:target, :any, required: true, doc: "the LiveComponent receiving the three events")
  attr(:error, :string, default: nil, doc: "why the last attempt was refused")
  attr(:components, :atom, default: nil)

  def status_dialog(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/40">
      <div class="w-[28rem] rounded-md border border-zinc-300 bg-white p-4 shadow-lg">
        <p class="mb-1 font-semibold text-zinc-900">Change the status of “{@flow.name}”</p>
        <p class="mb-3 text-sm text-zinc-500">
          What users may do with this flow. Any status can move to any other; every
          change is logged with who made it.
        </p>

        <form phx-change="status_picked" phx-submit="save_status" phx-target={@target} class="space-y-3">
          <Core.input
            components={@components}
            type="select"
            id="status-dialog-status"
            name="status"
            label="Status"
            value={@status}
            options={Shared.status_options()}
          />

          <div class="rounded-md border border-zinc-200 bg-zinc-50 px-3 py-2">
            <div class="font-medium text-zinc-800">{Shared.status_label(@status)}</div>
            <p class="mt-0.5 text-sm text-zinc-600">{Shared.status_summary(@status)}</p>
            <p :if={Shared.instance_counts_sentence(@counts)} class="mt-0.5 text-sm text-zinc-600">
              {Shared.instance_counts_sentence(@counts)}
            </p>
          </div>

          <div
            :if={true || offer_delete?(@flow, @status, @pre_release_count)}
            id="status-dialog-pre-release"
            class="rounded-md border border-amber-200 bg-amber-50 px-3 py-2"
          >
            <p class="font-medium text-zinc-800">{started_sentence(@pre_release_count)}</p>
            <Core.input
              components={@components}
              type="checkbox"
              id="status-dialog-delete-pre-release"
              name="delete_pre_release"
              label="Delete them"
              value={@delete_pre_release?}
            />
            <p class="text-sm text-zinc-600">
              The trial run, marked when it was started. Deleting it is logged and cannot be undone;
              left alone, it stays among the real instances.
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

  # The offer is for the one move it is about: off Pre-release, with
  # something to delete
  defp offer_delete?(%{status: "pre_release"}, picked, count) when picked != "pre_release",
    do: count > 0

  defp offer_delete?(_flow, _picked, _count), do: false

  defp started_sentence(1), do: "1 instance was started during pre-release."
  defp started_sentence(count), do: "#{count} instances were started during pre-release."
end
