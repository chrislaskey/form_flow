defmodule FormFlow.Web.Instances.Components.ReopenDialog do
  @moduledoc """
  `FormFlow.Web.Instances.Components.ReopenDialog` draws the confirmation a
  reopen asks before it changes anything: reopening puts a submitted form
  back in progress for everyone who can see it, so it is a deliberate click
  behind a click rather than a `data-confirm`.

  Every caller wires the same two events at `target`: `"cancel_reopen"`
  closes it, `"confirm_reopen"` is what actually reopens the form.
  """

  use Phoenix.Component

  alias FormFlow.Web.Components.Core

  attr(:target, :any, required: true)
  attr(:components, :atom, default: nil)

  def reopen_dialog(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/40">
      <div class="w-80 rounded-md border border-zinc-300 bg-white p-4 shadow-lg">
        <p class="mb-4 text-sm text-zinc-700">
          Reopen this form? It goes back to in progress and can be changed again.
        </p>
        <div class="flex justify-end gap-2">
          <Core.button
            components={@components}
            phx-click="cancel_reopen"
            phx-target={@target}
            class="btn"
          >
            Cancel
          </Core.button>
          <Core.button
            components={@components}
            phx-click="confirm_reopen"
            phx-target={@target}
            class="btn btn-primary"
          >
            Reopen
          </Core.button>
        </div>
      </div>
    </div>
    """
  end
end
