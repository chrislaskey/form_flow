defmodule FormFlow.Web.Instances.Components.ReopenDialog do
  @moduledoc """
  `FormFlow.Web.Instances.Components.ReopenDialog` draws the confirmation a
  reopen asks before it changes anything: reopening puts a submitted form
  back in progress for everyone who can see it, so it is a deliberate click
  behind a click rather than a `data-confirm`.

  It says **Reopen form?** over what reopening does - that the form was
  submitted, that reopening is how to change it again, and that it goes
  back to "in progress" - because the same dialog is reached from a Reopen
  button and from the Edit tab, and the second reader did not ask for a
  reopen by name.

  Every caller wires the same two events at `target`: `"cancel_reopen"`
  closes it, `"confirm_reopen"` is what actually reopens the form.
  """

  use Phoenix.Component

  alias FormFlow.Web.Components.Core
  alias FormFlow.Web.Components.Dialog

  attr(:target, :any, required: true)
  attr(:components, :atom, default: nil)

  def reopen_dialog(assigns) do
    ~H"""
    <Dialog.dialog width={:medium}>
      <h2 class="mb-2 text-base font-semibold text-zinc-900">Reopen form?</h2>
      <p class="mb-4 text-sm text-zinc-700">
        This form has been submitted. Reopen the form if you would like to make
        additional changes. Reopening a form puts it back to "in progress" status.
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
    </Dialog.dialog>
    """
  end
end
