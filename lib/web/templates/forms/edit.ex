defmodule FormFlow.Web.Templates.Forms.Edit do
  @moduledoc """
  `FormFlow.Web.Templates.Forms.Edit` LiveComponent edits one draft.

  Drafts only — published and archived definitions are immutable, and this
  page refuses to render them editable. The definition editor starts minimal
  (the JSON, in a textarea); the versioning chrome around it is the point:
  the optimistic-lock "changed under you" conflict, the stale-draft warning,
  and the picker between coexisting drafts.

  Addressed like `FormFlow.Web.Templates.Forms.Show`, standalone
  (`/forms/:id/versions/:version_id/edit`) or by drill-in
  (`/flows/:root/nodes/:node_id/form/versions/:version_id/edit`).
  """

  use Phoenix.LiveComponent

  alias FormFlow.Data.Graphs
  alias FormFlow.Data.Templates.Forms

  @impl true
  def mount(socket) do
    {:ok, assign(socket, error: nil, notice: nil)}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:base, fn -> "" end)
      |> assign_new(:app, fn -> "default" end)
      |> assign_new(:form_id, fn -> nil end)
      |> assign_new(:version_id, fn -> nil end)
      |> assign_new(:root_id, fn -> nil end)
      |> assign_new(:node_id, fn -> nil end)

    {:ok, load(socket)}
  end

  defp load(socket) do
    assigns = socket.assigns
    node = assigns.node_id && Graphs.get_node(assigns.node_id)
    form_id = assigns.form_id || (node && node.form_id)
    form = form_id && Forms.get(form_id)
    version = assigns.version_id && Forms.get_version(assigns.version_id)
    versions = if form, do: Forms.list_versions(form.id), else: []

    socket
    |> assign(form: form, node: node, version: version, versions: versions)
    |> assign_new(:definition_json, fn ->
      version && Phoenix.json_library().encode!(version.definition, pretty: true)
    end)
  end

  @impl true
  def handle_event("save", %{"definition" => definition_json}, socket) do
    with {:ok, definition} <- decode(definition_json),
         {:ok, version} <- Forms.update_draft(socket.assigns.version, %{definition: definition}) do
      {:noreply,
       assign(socket,
         version: version,
         definition_json: Phoenix.json_library().encode!(version.definition, pretty: true),
         error: nil,
         notice: "Saved."
       )}
    else
      {:error, :invalid_json} ->
        {:noreply,
         assign(socket, error: "Not valid JSON — fix the syntax and save again.", notice: nil)}

      {:error, :stale} ->
        {:noreply,
         assign(socket,
           error:
             "This draft changed under you — someone else saved it. " <>
               "Reload to pick up their version.",
           notice: nil
         )}

      {:error, %Ecto.Changeset{}} ->
        {:noreply,
         assign(socket,
           error: "Only drafts can be edited — this version is published.",
           notice: nil
         )}
    end
  end

  defp decode(json) do
    case Phoenix.json_library().decode(json) do
      {:ok, definition} when is_map(definition) -> {:ok, definition}
      _other -> {:error, :invalid_json}
    end
  end

  @impl true
  def render(%{form: nil} = assigns) do
    ~H"""
    <div>
      <p class="text-sm text-zinc-500">
        Form not found.
        <.link navigate={"#{@base}/forms"} class="underline">Back to forms</.link>
      </p>
    </div>
    """
  end

  def render(%{version: version} = assigns) when version == nil or version.status != "draft" do
    ~H"""
    <div>
      <p class="text-sm text-zinc-500">
        Only drafts can be edited.
        <.link navigate={show_path(assigns)} class="underline">Back to the form</.link>
      </p>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div>
      <div class="mb-2 h-14 flex items-center justify-between gap-4">
        <div class="text-sm font-semibold">
          <%= if @node do %>
            <.link navigate={"#{@base}/flows"} class="hover:underline">Flows</.link>
            <span class="text-zinc-400">/</span>
          <% else %>
            <.link navigate={"#{@base}/forms"} class="hover:underline">Forms</.link>
            <span class="text-zinc-400">/</span>
          <% end %>
          <.link navigate={show_path(assigns)} class="hover:underline">{@form.name}</.link>
          <span class="ml-1 text-xs font-normal text-zinc-500">draft</span>
        </div>
        <div class="flex items-center gap-2">
          <.link
            navigate={version_show_path(assigns, @version)}
            role="switch"
            aria-checked="true"
            aria-label="Switch to Show"
            class="flex items-center gap-1.5 text-xs"
          >
            <span class="text-zinc-500">Show</span>
            <span class="relative inline-flex h-5 w-9 shrink-0 items-center rounded-full bg-cyan-600 transition-colors">
              <span class="inline-block h-4 w-4 translate-x-4 rounded-full bg-white shadow transition-transform" />
            </span>
            <span class="font-semibold text-zinc-900">Edit</span>
          </.link>
        </div>
      </div>

      <p :if={@error} class="mb-2 text-xs text-red-600">{@error}</p>
      <p :if={@notice} class="mb-2 text-xs text-green-700">{@notice}</p>

      <p
        :if={Forms.stale_draft?(@version)}
        class="mb-2 rounded-md border border-amber-300 bg-amber-50 px-2 py-1 text-xs text-amber-800"
      >
        This draft was based on a version that is no longer the latest — review before publishing.
      </p>

      <div class="flex flex-wrap gap-6">
        <form phx-submit="save" phx-target={@myself} class="min-w-0 flex-1">
          <h3 class="mb-1 text-xs font-medium text-zinc-500">Definition (JSON)</h3>
          <textarea
            name="definition"
            rows="18"
            spellcheck="false"
            class="w-full rounded-md border border-zinc-300 p-3 font-mono text-xs"
          >{@definition_json}</textarea>
          <div class="mt-2">
            <button
              type="submit"
              class="rounded-md border border-cyan-600 bg-cyan-600 px-3 py-1.5 text-xs text-white hover:bg-cyan-700"
            >
              Save draft
            </button>
          </div>
        </form>

        <div class="w-64 shrink-0">
          <h3 class="mb-1 text-xs font-medium text-zinc-500">Drafts</h3>
          <ul class="space-y-1 text-sm">
            <li :for={version <- @versions} :if={version.status == "draft"}>
              <.link
                navigate={"#{version_show_path(assigns, version)}/edit"}
                class={["hover:underline", @version.id == version.id && "font-semibold"]}
              >
                draft
              </.link>
              <span class="block text-[10px] text-zinc-400">
                {Calendar.strftime(version.updated_at, "%Y-%m-%d %H:%M")}
              </span>
            </li>
          </ul>
        </div>
      </div>
    </div>
    """
  end

  defp form_base_path(%{node: nil} = assigns), do: "#{assigns.base}/forms/#{assigns.form.id}"

  defp form_base_path(assigns) do
    "#{assigns.base}/flows/#{assigns.root_id}/nodes/#{assigns.node_id}/form"
  end

  defp show_path(assigns), do: form_base_path(assigns)

  defp version_show_path(assigns, version) do
    "#{form_base_path(assigns)}/versions/#{version.id}"
  end
end
