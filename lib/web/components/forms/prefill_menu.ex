defmodule FormFlow.Web.Components.Forms.PrefillMenu do
  @moduledoc """
  `FormFlow.Web.Components.Forms.PrefillMenu` function component
  renders the **⋮** menu beside a form page's prefill picker: New prefill,
  Edit prefill, Capture prefill, Delete prefill.

  It goes in `FormFlow.Web.Components.Forms.PrefillPicker`'s `actions` slot
  on the two template pages, which is where prefills are written. The pages
  that only apply one - a form instance being filled - pass no actions, so
  the picker is a picker there and nothing more.

  A `<details>` dropdown, as the flows index's row actions: open and close
  are the browser's, click-away closes it, and choosing an item closes it
  before the event goes out. Its trigger is a square button the size of the
  health one beside the page's other headers, so the row reads as a control
  and a button rather than a control and a character.

  Edit and Delete act on what is selected and are **not drawn** while nothing
  is: a menu where an item does nothing is a menu that has to be read twice.
  Delete asks first. New and Capture are always there, because both write a
  prefill that need not exist yet.

  **Capture** reads the answers off the form as it stands on the page and
  opens the same dialog New and Edit open, with them already filled in. It is
  a `FormFlow.Web.Components.Forms.Capture` button - the one piece of
  JavaScript in the feature lives there, shared with the Edit page's Save
  draft, and its moduledoc says why the DOM is where the form is read from
  and what `FormData` does and does not collect. `form_id` is which form -
  an explicit attr, since a template page has two (the preview, and the
  editor's own fields) and the answers are always the preview's. The dialog
  says what a capture can miss (`FormFlow.Web.Components.Forms.PrefillDialog`).

  The caller owns what the items do: `open_prefill` with an `action` of
  `"create"` or `"update"`, `capture_prefill` with the serialised form as
  `params`, and `delete_prefill`, all to `target`.
  """

  use Phoenix.Component

  alias FormFlow.Web.Components.Forms.Capture
  alias Phoenix.LiveView.JS

  attr(:id, :string, required: true)
  attr(:selected, :map, default: nil, doc: "the prefill in use, or nil")

  attr(:form_id, :string,
    required: true,
    doc: "the DOM id of the rendered form Capture reads its answers from"
  )

  attr(:target, :any, required: true, doc: "the LiveComponent receiving the menu's events")

  def prefill_menu(assigns) do
    ~H"""
    <details id={@id} class="dropdown dropdown-end" phx-click-away={JS.remove_attribute("open")}>
      <summary
        class="flex size-10 cursor-pointer list-none items-center justify-center rounded-lg btn text-lg leading-none text-zinc-700 select-none hover:bg-zinc-50 [&::-webkit-details-marker]:hidden"
        aria-label="Prefill actions"
        aria-haspopup="menu"
      >
        ⋮
      </summary>
      <ul
        class="dropdown-content menu z-30 mt-1 w-56 rounded-md border border-zinc-300 bg-white p-1 text-sm shadow-lg"
        role="menu"
      >
        <li>
          <button
            type="button"
            role="menuitem"
            phx-click={
              JS.remove_attribute("open", to: "##{@id}")
              |> JS.push("open_prefill", value: %{action: "create"})
            }
            phx-target={@target}
            class={item_class()}
          >
            New prefill
          </button>
        </li>
        <li :if={@selected}>
          <button
            type="button"
            role="menuitem"
            phx-click={
              JS.remove_attribute("open", to: "##{@id}")
              |> JS.push("open_prefill", value: %{action: "update"})
            }
            phx-target={@target}
            class={item_class()}
          >
            Edit prefill
          </button>
        </li>
        <li>
          <%!-- The click does two things and neither is a server event from
                the button: the JS command closes the menu the way its
                siblings do, and the Capture button's hook reads the form
                and pushes what it found. --%>
          <Capture.capture_button
            id={"#{@id}-capture"}
            form_id={@form_id}
            event="capture_prefill"
            target={@target}
            role="menuitem"
            phx-click={JS.remove_attribute("open", to: "##{@id}")}
            class={item_class()}
          >
            Capture prefill
          </Capture.capture_button>
        </li>
        <li :if={@selected}>
          <button
            type="button"
            role="menuitem"
            data-confirm={@selected && ~s(Delete the prefill “#{@selected.name}”?)}
            phx-click={
              JS.remove_attribute("open", to: "##{@id}") |> JS.push("delete_prefill")
            }
            phx-target={@target}
            class={[item_class(), "text-red-600"]}
          >
            Delete prefill
          </button>
        </li>
      </ul>
    </details>
    """
  end

  # The page's primary, filled: an item under the pointer is the one about to
  # happen, and says so the way a primary button does
  defp item_class, do: "hover:bg-cyan-600 hover:text-white"
end
