defmodule FormFlow.Web.Components.Forms.PrefillDialog do
  @moduledoc """
  `FormFlow.Web.Components.Forms.PrefillDialog` function component
  renders the dialog that writes one prefill — the named set of test answers
  a form is filled with while it is being built
  (`FormFlow.Data.Templates.Form.Prefill`).

  Two fields, because a prefill is two things: the **name** an admin picks it
  by, and the **answers**, as the JSON object they are stored as — question
  names to values, wrapped in nothing, the shape a filled-in form has
  (`{"full_name": "Alex Doe"}`, never `{"data": {…}}`: the stored entry's
  `"data"` key is `FormFlow.Data.Templates.Form.Prefill`'s, and the field
  edits what goes inside it). The answers are read here as JSON rather than
  filled in through the form itself, which is the plainest thing that works
  while the form being built is the one on the page; a prefill editor that
  renders the definition is its own page, and this dialog is not it. Capture
  is the shortcut around the typing — it fills the field from the form on
  screen, and what lands there is the same JSON.

  The caller owns the flow around it: opening, the `save_prefill` event the
  form submits to `target` with `name` and `data`, the `cancel_prefill`
  event Cancel sends, and the error it hands back when a write is refused —
  a name already taken, JSON that does not parse — so the dialog stays open
  over what was typed rather than closing on it.

  `action` is `:create` or `:update`, and decides only what the dialog says:
  the same two fields either way, since updating a prefill is writing its
  name and answers again.

  Every prefill is **readable by everyone who can reach the form it belongs
  to**, on the admin pages and, while a flow is being tried out, on the form
  itself. Nothing hides one, and there is no per-user set. The dialog says so
  where the answers are typed, because the exposure is the answers' content:
  an admin who saves a real person's details has published them to every
  other user of that form. That sentence is the whole of the protection
  (`archive/plans/prefills-for-testing.md` §15), which is why it is on screen
  and not only in a moduledoc.

  `captured` says the answers came off the form on screen rather than out of
  the store (`FormFlow.Web.Components.Forms.PrefillMenu`, Capture
  prefill), which the dialog says out loud: what the browser hands over is
  what it would submit, so an unchecked box and a disabled field are missing
  from it and a question hidden by a condition is in it. Seeing that before
  the write is the reason Capture opens this dialog instead of saving
  straight away.
  """

  use Phoenix.Component

  alias FormFlow.Web.Components.Core

  attr(:action, :atom, required: true, doc: ":create or :update")
  attr(:name, :string, default: "", doc: "the name as prefilled")
  attr(:data, :string, default: "{}", doc: "the answers as prefilled, JSON")
  attr(:target, :any, required: true, doc: "the LiveComponent receiving save_prefill and cancel")
  attr(:error, :string, default: nil, doc: "why the last attempt was refused")

  attr(:captured, :boolean,
    default: false,
    doc: "whether the answers were read off the form on screen"
  )

  attr(:components, :atom, default: nil)

  def prefill_dialog(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/40">
      <div class="w-[34rem] rounded-md border border-zinc-300 bg-white p-4 shadow-lg">
        <p class="mb-2 font-semibold text-xl text-zinc-900">
          {if @action == :create, do: "New prefill", else: "Edit this prefill"}
        </p>
        <p class="mb-3 text-zinc-500">
          Prefills are shared for all users. Be thoughtful about what data is stored in them. 
        </p>
        <form phx-submit="save_prefill" phx-target={@target} class="space-y-3">
          <Core.input
            components={@components}
            type="text"
            name="name"
            label="Name"
            value={@name}
            required
          />

          <div>
            <Core.input
              components={@components}
              type="textarea"
              name="data"
              label="Answers"
              value={@data}
              rows="12"
              class="w-full textarea bg-white border border-zinc-300 font-mono text-sm"
            />
            <span class="mt-1 block text-sm text-zinc-500">
              Format is JSON object of question names to values, e.g. <code class="font-mono">{~s({"full_name": "Alex Doe", "species": "dog"})}</code>
            </span>
          </div>

          <Core.error :if={@error} components={@components}>{@error}</Core.error>

          <div class="flex justify-end gap-2">
            <Core.button
              components={@components}
              type="button"
              phx-click="cancel_prefill"
              phx-target={@target}
              class="btn"
            >
              Cancel
            </Core.button>
            <Core.button components={@components} type="submit" variant="primary">
              {if @action == :create, do: "Create prefill", else: "Save prefill"}
            </Core.button>
          </div>
        </form>
      </div>
    </div>
    """
  end
end
