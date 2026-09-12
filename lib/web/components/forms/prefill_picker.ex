defmodule FormFlow.Web.Components.Forms.PrefillPicker do
  @moduledoc """
  `FormFlow.Web.Components.Forms.PrefillPicker` function component renders
  the control that fills a form in with saved answers: a searchable select of
  the form's prefills (`FormFlow.Data.Templates.Form.Prefill`), and whatever
  actions the page puts beside it.

  It is on both sides of the library — the template pages, where a form is
  being built and looked at, and a form instance, where a flow that is not
  open yet is walked through — so it lives here rather than under either.
  What differs between them is the `actions` slot: the pages that *write*
  prefills put their menu there, and the pages that only apply one pass
  none.

  The select carries no label of its own: with one control in the row, the
  placeholder — **Prefill** — says what it is, and the row stays a control
  rather than a section. It is never disabled, so a form with no prefills yet
  still opens to say there are none rather than looking broken.

  Choosing one sends `pick_prefill` to `target` with the name, or with `""`
  when the select is cleared; the page decides what that means, since on a
  page with unsaved content it is a navigation to ask about first.

  `missing` is the name a URL asked for that this form has not got — a link
  to a prefill since deleted, or one saved against another form. The select
  shows nothing selected, which on its own looks like the link was ignored,
  so the picker says which name it could not find.
  """

  use Phoenix.Component

  attr(:id, :string, required: true)
  attr(:prefills, :list, required: true, doc: "the form's prefills, as structs")
  attr(:selected, :string, default: nil, doc: "the name of the one in use, or nil")

  attr(:missing, :string,
    default: nil,
    doc: "a name the URL asked for that this form has not got"
  )

  attr(:target, :any, required: true, doc: "the LiveComponent receiving pick_prefill")
  attr(:class, :any, default: nil)
  attr(:components, :atom, default: nil)

  slot(:actions, doc: "what the page offers beside the select — a menu, or nothing")

  def prefill_picker(assigns) do
    ~H"""
    <div class={@class}>
      <div class="flex items-center gap-2">
        <form
          id={"#{@id}-form"}
          phx-change="pick_prefill"
          phx-target={@target}
          class="min-w-0 flex-1"
        >
          <PhoenixSelect.select
            id={@id}
            name="prefill"
            value={@selected}
            options={Enum.map(@prefills, & &1.name)}
            placeholder="Prefill"
          />
        </form>
        {render_slot(@actions)}
      </div>
      <p :if={@missing} class="mt-1 text-xs text-zinc-500">
        This form has no prefill named “{@missing}”.
      </p>
    </div>
    """
  end
end
