defmodule FormFlow.Web.Instances.Forms.Show do
  @moduledoc """
  `FormFlow.Web.Instances.Forms.Show` LiveComponent renders the answers at one
  position of a flow instance, read-only — the pinned version's definition
  through `DynamicForm`, filled in with what is in `data`, every control
  disabled and no submit. The answers are the form's `FormFlow.Config.Forms.Type`'s
  to draw (`show_component/1`), as they are on Edit: the default is the
  disabled form alone, and a type that draws more around them here — a review
  showing what it reviewed — does so on this page too.

  It is the counterpart of `FormFlow.Web.Instances.Forms.Edit`, which is where
  work happens: `/:id/forms/*path` is this page,
  `/:id/forms/*path/edit` is that one. Both are addressed by position
  and resolve it the same way (`FormFlow.Web.Instances.Forms.Shared`); the
  difference is that this page never starts anything. With nothing filled in
  yet it says so and offers the link across to Edit, which does. Like Edit, it
  asks the host's `on_mount` whether it may render at all and draws only its
  message, or nothing while redirecting, when not.

  It is also where the answers are taken away from: Download PDF and Print
  are plain links out to a download endpoint, because a LiveView holds a
  websocket and cannot send a file. Both send the same document — the
  disposition header is the only difference — and both resolve the position
  the way this page does, so what is printed is what is shown. They are
  drawn only when the page knows where downloads live: the `download_path`
  attr, or `config :form_flow, download_path:` behind it. An application
  that configures neither is one that does not offer downloads, and this
  page says nothing about them.

  The one write here is Reopen, and it lives here on purpose: reopening
  changes state, so it stays an explicit button rather than a mode of a URL,
  and it belongs beside the answers it reopens. It lands on Edit, where those
  answers can then be changed.
  """

  use Phoenix.LiveComponent

  alias FormFlow.Config.Flows.Perspective
  alias FormFlow.Data.Instances
  alias FormFlow.Web.Components.Core
  alias FormFlow.Web.Controllers.Downloads
  alias FormFlow.Web.Downloads.Token
  alias FormFlow.Web.Instances.Components
  alias FormFlow.Web.Instances.Forms.Shared
  alias FormFlow.Web.Instances.Paths

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:base, fn -> "" end)
      |> assign_new(:tenant_id, fn -> nil end)
      |> assign_new(:perspectives, fn -> [] end)
      |> assign_new(:flow_types, fn -> FormFlow.Config.Flows.Type.defaults() end)
      |> assign_new(:form_types, fn -> FormFlow.Config.Forms.Type.defaults() end)
      |> assign_new(:callback_data, fn -> %{} end)
      |> assign_new(:components, fn -> nil end)
      |> assign_new(:on_mount, fn -> nil end)
      |> assign_new(:instances, fn -> nil end)
      |> assign_new(:flows, fn -> nil end)
      |> assign_new(:download_path, fn -> nil end)
      |> then(&assign(&1, :download_path, &1.assigns.download_path || Downloads.path()))
      |> assign_new(:uri, fn -> nil end)
      |> assign_new(:params, fn -> %{} end)
      |> assign_new(:error, fn -> nil end)

    {:ok, socket |> load() |> assign_workable()}
  end

  # What the gate decided, as one answer, computed where the gate ran. The
  # render clause that draws the page's actions reads it and so does every
  # handle_event, because a LiveComponent's events are reachable whenever it
  # is mounted — which it is even when the page drew a refusal instead. A
  # button that was never rendered is not a check.
  defp assign_workable(socket) do
    assigns = socket.assigns

    assign(
      socket,
      :workable?,
      is_nil(assigns[:mount_error]) and is_nil(assigns[:navigate_to]) and
        assigns[:visible?] == true and not is_nil(assigns[:flow_instance]) and
        not is_nil(assigns[:form_instance]) and is_nil(assigns[:parse_error])
    )
  end

  @impl true
  def handle_event("form_flow:download", _params, socket) when not socket.assigns.workable? do
    {:noreply, socket}
  end

  def handle_event("form_flow:download", params, socket) do
    %{flow_instance: flow_instance, path: path} = socket.assigns

    token =
      Token.encode(socket, %{
        user_id: socket.assigns.user_id,
        tenant_id: socket.assigns.tenant_id,
        perspectives: Perspective.normalize(socket.assigns.perspectives),
        flow_instance_id: flow_instance.id,
        path: path,
        disposition: disposition(params)
      })

    {:reply, %{url: Downloads.form_path(socket.assigns.download_path, token)}, socket}
  end

  def handle_event("reopen", _params, socket) when not socket.assigns.workable? do
    {:noreply, socket}
  end

  def handle_event("reopen", _params, socket) do
    %{flow_instance: flow_instance, form_instance: form_instance} = socket.assigns

    case Instances.Forms.update_status(flow_instance, form_instance.path, :in_progress,
           user_id: socket.assigns.user_id,
           tenant_id: socket.assigns.tenant_id
         ) do
      {:ok, reopened} ->
        to = Paths.form_edit_path(socket.assigns.base, flow_instance.id, reopened.path)
        {:noreply, push_navigate(socket, to: to)}

      {:error, _changeset} ->
        {:noreply, assign(socket, :error, "Could not reopen the form.")}
    end
  end

  defp load(%{assigns: %{flow_instance_id: flow_instance_id}} = socket) do
    case Instances.Flows.get(flow_instance_id) do
      nil ->
        assign(socket, :flow_instance, nil)

      flow_instance ->
        socket = socket |> assign(:flow_instance, flow_instance) |> Shared.assigns()

        Shared.on_mount(socket)
    end
  end

  @impl true
  def handle_async(:navigate, {:ok, to}, socket) do
    {:noreply, push_navigate(socket, to: to)}
  end

  @impl true
  def render(%{flow_instance: nil} = assigns) do
    ~H"""
    <p class="text-sm text-zinc-500">This flow no longer exists.</p>
    """
  end

  # The host's on_mount is sending the user elsewhere: nothing to draw meanwhile
  def render(%{navigate_to: to} = assigns) when is_binary(to) do
    ~H"""
    <div></div>
    """
  end

  # The host's on_mount refused the page; its message is all there is to draw
  def render(%{mount_error: message} = assigns) when is_binary(message) do
    ~H"""
    <div>
      <Components.FormPage.breadcrumb
        base={@base}
        flow_instance={@flow_instance}
        flow_name={@flow_name}
        label={@form_label}
      />

      <Components.FormPage.notice message={@mount_error}>
        <.link
          navigate={Paths.flow_path(@base, @flow_instance.id)}
          class="text-cyan-600 hover:underline"
        >
          Back to the flow
        </.link>
      </Components.FormPage.notice>
    </div>
    """
  end

  # The flow's type says this form is not for the viewer — another
  # perspective's work. Nothing of it is shown, started or not.
  def render(%{visible?: false, form: %{path: _path}} = assigns) do
    ~H"""
    <div>
      <Components.FormPage.breadcrumb
        base={@base}
        flow_instance={@flow_instance}
        flow_name={@flow_name}
        label={@form_label}
      />

      <Components.FormPage.notice message="This form is not part of your work here.">
        <.link
          navigate={Paths.flow_path(@base, @flow_instance.id)}
          class="text-cyan-600 hover:underline"
        >
          Back to the flow
        </.link>
      </Components.FormPage.notice>
    </div>
    """
  end

  # Nothing filled in here yet, so there are no answers to show — only why,
  # and the way onward when there is one.
  def render(%{form_instance: nil} = assigns) do
    ~H"""
    <div>
      <Components.FormPage.breadcrumb
        base={@base}
        flow_instance={@flow_instance}
        flow_name={@flow_name}
        label={@form_label}
      />

      <Components.FormPage.notice message={unstarted_message(assigns)}>
        <.link
          :if={@editable?}
          navigate={Paths.form_edit_path(@base, @flow_instance.id, @path)}
          class="text-cyan-600 hover:underline"
        >
          Start this form →
        </.link>
        <.link
          navigate={Paths.flow_path(@base, @flow_instance.id)}
          class="text-cyan-600 hover:underline"
        >
          Back to the flow
        </.link>
      </Components.FormPage.notice>
    </div>
    """
  end

  def render(%{parse_error: error} = assigns) when is_binary(error) do
    ~H"""
    <div class="rounded-md border border-amber-300 bg-amber-50 px-3 py-2 text-xs text-amber-800">
      <p class="font-medium">This form can't be rendered.</p>
      <p class="mt-1 font-mono">{@parse_error}</p>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div>
      <Components.FormPage.breadcrumb
        base={@base}
        flow_instance={@flow_instance}
        flow_name={@flow_name}
        label={@form_label}
      />

      {@type.module.progress_component(%{
        id: "#{@id}-flow-progress",
        base: @base,
        flow_instance_id: @flow_instance.id,
        forms: @forms,
        current_path: @path,
        clickable: @clickable,
        context: @context,
        callback_data: @callback_data
      })}

      <Core.error :if={@error} components={@components}>{@error}</Core.error>

      <%!-- A LiveView holds a websocket, not a response, so taking the answers
            away is a request of its own, authorized by a token this page
            mints on the click. Minting then, rather than when the page was
            drawn, is what lets a tab left open for days still print: the
            token is always seconds old, whatever the page is. --%>
      <div
        :if={@download_path && @workable?}
        id={"#{@id}-downloads"}
        phx-hook=".Downloads"
        phx-target={@myself}
        class="mb-3 flex items-center gap-4 text-xs"
      >
        <button type="button" data-disposition="download" class="text-cyan-600 hover:underline">
          Download PDF
        </button>
        <button type="button" data-disposition="print" class="text-cyan-600 hover:underline">
          Print
        </button>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".Downloads">
        export default {
          mounted() {
            this.el.addEventListener("click", (event) => {
              const trigger = event.target.closest("[data-disposition]")
              if (!trigger) return
              event.preventDefault()

              // Opened now, while the click is still the user's gesture: a
              // window.open after the round trip below is what popup blockers
              // are for. Download needs no tab — an attachment does not
              // navigate the page it was asked from.
              const disposition = trigger.dataset.disposition
              const tab = disposition === "print" ? window.open("", "_blank") : null

              this.pushEventTo(this.el, "form_flow:download", {disposition}, (reply) => {
                if (!reply || !reply.url) {
                  if (tab) tab.close()
                  return
                }

                if (tab) {
                  tab.location = reply.url
                } else {
                  window.location = reply.url
                }
              })
            })
          }
        }
      </script>

      <div
        :if={@form_instance.status == "completed"}
        class="mb-3 flex items-center gap-3 rounded-md border border-emerald-300 bg-emerald-50 px-3 py-2 text-xs text-emerald-800"
      >
        <span>
          Submitted {Calendar.strftime(@form_instance.completed_at, "%Y-%m-%d %H:%M")} UTC.
        </span>
        <Core.button
          components={@components}
          phx-click="reopen"
          phx-target={@myself}
          class="rounded-md border border-emerald-300 px-2 py-0.5 hover:border-emerald-400"
        >
          Reopen
        </Core.button>
      </div>

      <p :if={@form_instance.status != "completed"} class="mb-2 text-xs">
        <.link
          navigate={Paths.form_edit_path(@base, @flow_instance.id, @path)}
          class="text-cyan-600 hover:underline"
        >
          Continue filling this out →
        </.link>
      </p>

      {@form_type.module.show_component(%{
        id: "#{@id}-#{@form_instance.id}-#{@form_instance.status}",
        instance: @parsed,
        data: @form_instance.data,
        context: @context,
        callback_data: @callback_data,
        components: @components
      })}
    </div>
    """
  end

  # Anything but an explicit print is a download: it never navigates the user
  # away from the page they were on
  defp disposition(%{"disposition" => "print"}), do: :print
  defp disposition(_params), do: :download

  defp unstarted_message(%{form: nil}), do: "This form is not part of this flow."
  defp unstarted_message(%{editable?: true}), do: "You haven't started this form yet."

  defp unstarted_message(_assigns),
    do: "This form isn't available yet — it comes later in the flow."
end
