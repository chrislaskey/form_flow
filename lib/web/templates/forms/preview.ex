defmodule FormFlow.Web.Templates.Forms.Preview do
  @moduledoc """
  `FormFlow.Web.Templates.Forms.Preview` LiveView renders a definition as the
  real, interactive form a user would see.

  This is deliberately a LiveView, not a LiveComponent, and it is embedded
  with `Phoenix.Component.live_render/3` from the forms Show and Edit pages.
  A LiveComponent shares its parent's process, so a definition that crashes
  the renderer would take the whole admin page down with it. A child LiveView
  runs in its own process: if the preview crashes, the client remounts only
  the preview and the surrounding page keeps working. Previews render
  arbitrary user-authored JSON — the one place in the admin UI where a crash
  is an expected input, not a bug.

  Two layers of protection:

    * Known-bad definitions (unparseable JSON shapes) are caught eagerly in
      `mount/3` and rendered as an inline error, so they never enter a
      crash-remount loop.
    * Unforeseen crashes (renderer bugs, bad element attributes surfacing at
      diff time or in event handlers) are contained by process isolation.

  Mounted via `live_render`, never at the router, so addressing comes through
  the `session` map. Two modes:

    * `"version_id"` — Show: the definition is loaded fresh from the database
    * `"definition"` — Edit: the current (possibly unsaved, possibly invalid)
      JSON string from the editor rides in directly

  Either way the session also carries `"id"`, the `live_render` id, reused as
  the inner form's id. A child LiveView never re-reads its session — the
  embedder re-renders the preview by changing the `live_render` id, which
  remounts it with a fresh session.

  Submissions are swallowed on purpose: a valid submit shows a confirmation
  notice and persists nothing.
  """

  use Phoenix.LiveView

  alias FormFlow.Data.Templates.Forms

  @impl true
  def mount(:not_mounted_at_router, session, socket) do
    if connected?(socket) && FormFlow.app_config(:pubsub_server) && session["pubsub_topic"] do
      Phoenix.PubSub.subscribe(FormFlow.app_config(:pubsub_server), session["pubsub_topic"])
    end

    {:ok,
     socket
     |> assign(id: session["id"], submitted?: false)
     |> assign_instance(session)}
  end

  # Parse the definition eagerly so a malformed one becomes an inline error.
  # Left to crash at render time, the client would remount the preview into
  defp assign_instance(socket, %{"definition" => json}) when is_binary(json) do
    parse(socket, json)
  end

  defp assign_instance(socket, %{"version_id" => version_id}) do
    case Forms.get_version(version_id) do
      nil -> assign(socket, instance: nil, parse_error: nil, missing?: true)
      version -> parse(socket, version.definition)
    end
  end

  defp parse(socket, definition) do
    socket
    |> assign(missing?: false)
    |> assign(instance: DynamicForm.Parser.JSON.parse!(definition), parse_error: nil)
  rescue
    error -> assign(socket, instance: nil, parse_error: Exception.message(error))
  end

  @impl true
  def handle_info({:dynamic_form, :success, _payload}, socket) do
    {:noreply, assign(socket, :submitted?, true)}
  end

  def handle_info({:form_flow, :update_definition, definition}, socket) do
    {:noreply, assign_instance(socket, %{"definition" => definition})}
  end

  @impl true
  def render(%{missing?: true} = assigns) do
    ~H"""
    <p class="text-sm text-zinc-500">This version no longer exists.</p>
    """
  end

  def render(%{parse_error: error} = assigns) when is_binary(error) do
    ~H"""
    <div class="rounded-md border border-amber-300 bg-amber-50 px-3 py-2 text-xs text-amber-800">
      <p class="font-medium">This definition can't be rendered as a form.</p>
      <p class="mt-1 font-mono">{@parse_error}</p>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div>
      <p
        :if={@submitted?}
        class="mb-3 rounded-md border border-emerald-300 bg-emerald-50 px-3 py-2 text-xs text-emerald-800"
      >
        Valid submission — this is a preview, nothing was saved.
      </p>
      <DynamicForm.form id={"#{@id}-form"} instance={@instance} />
    </div>
    """
  end
end
