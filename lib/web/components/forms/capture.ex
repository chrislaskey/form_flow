defmodule FormFlow.Web.Components.Forms.Capture do
  @moduledoc """
  `FormFlow.Web.Components.Forms.Capture` function component renders a
  button whose click **captures the form on the page** - reads the answers
  off a rendered `<form>` as they stand, valid or not - and pushes them to
  a LiveComponent as one event.

  Two buttons do this: the prefill menu's Capture prefill
  (`FormFlow.Web.Components.Forms.PrefillMenu`) and the Edit page's Save
  draft (`FormFlow.Web.Instances.Forms.Edit`). Both want the form as the
  user sees it, not as a submit would validate it, and the DOM is the only
  place that form exists in a shape both can read: the template pages draw
  theirs in a child LiveView of their own and an instance draws it in the
  page's own process, while both put the same `<form>` on screen. So this
  is the one piece of JavaScript in either feature, and it lives here so
  there is one place that knows how a form is read off the page.

  The hook serialises `FormData` the way a submit would, so the receiving
  page decodes it with `Plug.Conn.Query.decode/1` and gets the params it
  already knows (`FormFlow.Web.Components.Forms.Prefills.answers_from_params/1`).
  What `FormData` collects is what the browser would submit, not what the
  page can see: an unchecked box and a disabled field are absent rather
  than empty, and a question hidden by a condition is present.

  `form_id` is the DOM id of the `<form>` to read - an explicit attr, since a
  template page has two forms on it (the preview, and the editor's own
  fields). `event` is the event pushed, with the serialised form as
  `params`. Everything else on the button - its role, classes, a `phx-click`
  that closes a menu - is the caller's, through `rest`.
  """

  use Phoenix.Component

  attr(:id, :string, required: true)

  attr(:form_id, :string,
    required: true,
    doc: "the DOM id of the rendered form whose answers are read"
  )

  attr(:event, :string, required: true, doc: "the event pushed, with the form as `params`")
  attr(:target, :any, required: true, doc: "the LiveComponent receiving the event")
  attr(:rest, :global, include: ~w(role disabled))

  slot(:inner_block, required: true)

  def capture_button(assigns) do
    ~H"""
    <button
      type="button"
      id={@id}
      phx-hook=".Capture"
      phx-target={@target}
      data-form-id={@form_id}
      data-event={@event}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Capture">
      export default {
        mounted() {
          this.el.addEventListener("click", () => {
            const form = document.getElementById(this.el.dataset.formId)
            if (!form) return

            // The same encoding a submit would send, so the page decodes it
            // with Plug.Conn.Query and gets the params it already knows.
            const params = new URLSearchParams(new FormData(form)).toString()

            this.pushEventTo(this.el, this.el.dataset.event, {params})
          })
        }
      }
    </script>
    """
  end
end
