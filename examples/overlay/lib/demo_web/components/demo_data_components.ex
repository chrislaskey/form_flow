defmodule DemoWeb.DemoDataComponents do
  @moduledoc """
  The control that puts the demo's data back to what it ships with, and the
  event it sends.

  Two pages carry it — the index at `/` and the demo landing page at `/demo` —
  so the card and the handling of its click are written once here. A page
  renders `reset_demo_data/1` and forwards the event to `handle_reset/1`:

      def handle_event("reset_demo", _params, socket),
        do: {:noreply, DemoDataComponents.handle_reset(socket)}

  The card is shown to everyone and `handle_reset/1` refuses anyone but the
  admin, which is the demo's idiom elsewhere too: a page says whose it is
  rather than hiding from you (`DemoWeb.PersonaComponents`). The check has to
  live there regardless — a LiveView event can be pushed by anyone, whether or
  not a button was rendered for them.
  """

  use DemoWeb, :html

  # `:html` brings the markup side; the flash a click leaves behind is
  # LiveView's.
  import Phoenix.LiveView, only: [put_flash: 3]
  import DemoWeb.PersonaComponents

  @doc """
  The framed "Reset the demo data" card. Rendered for every perspective; the
  click is what checks the role.
  """
  attr :id, :string, default: "reset-demo"
  attr :current_user, :map, required: true

  def reset_demo_data(assigns) do
    ~H"""
    <section
      id={@id}
      class="flex max-w-5xl items-center justify-between gap-4 rounded-xl border border-gray-300 px-6 py-5"
    >
      <div class="space-y-1">
        <h2 class="font-semibold text-gray-900">Reset the demo data</h2>
        <p class="text-sm text-base-content/70">
          Puts the flows, forms, and applications back to the pet licensing data
          the demo ships with. Anything built or filled in since goes — including
          whatever someone else reading this demo was in the middle of.
        </p>
      </div>
      <button
        type="button"
        phx-click="reset_demo"
        data-confirm="Reset the demo? Every flow, form, and application goes back to what the demo ships with, for everyone reading it."
        class="rounded-lg border border-gray-300 px-4 py-2 text-sm font-semibold whitespace-nowrap text-gray-900 transition-colors hover:bg-gray-100"
      >
        Reset demo data
      </button>
    </section>
    """
  end

  @doc """
  Runs the reset for the admin, and refuses anyone else. Returns the socket
  with the outcome in the flash.
  """
  def handle_reset(socket) do
    if allows?(socket.assigns.current_user, [:admin]) do
      {:ok, counts} = Demo.Reset.run()

      put_flash(
        socket,
        :info,
        "Demo data reset: #{counts.deleted} rows cleared, #{counts.loaded} reloaded from the snapshot."
      )
    else
      put_flash(socket, :error, "Only the admin can reset the demo data.")
    end
  end
end
