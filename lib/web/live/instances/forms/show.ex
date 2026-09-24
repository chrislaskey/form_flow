defmodule FormFlow.Web.Instances.Forms.Show do
  @moduledoc """
  `FormFlow.Web.Instances.Forms.Show` LiveComponent renders the answers at one
  position of a flow instance, read-only - the instance's version's definition
  through `DynamicForm`, filled in with what is in `data`, every control
  disabled and no submit. The answers are the form's `FormFlow.Config.Forms.Type`'s
  to draw (`show_component/1`), as they are on Edit: the default is the
  disabled form alone, and a type that draws more around them here - a review
  showing what it reviewed - does so on this page too.

  It is the counterpart of `FormFlow.Web.Instances.Forms.Edit`, which is where
  work happens: `/:id/forms/*path` is this page,
  `/:id/forms/*path/edit` is that one, and `/:id/forms/*path/history`
  (`FormFlow.Web.Instances.Forms.History`) is what has happened to the form
  - the three views the header offers as tabs. All three are addressed by
  position and resolve it the same way (`FormFlow.Web.Instances.Forms.Shared`);
  the difference is that this page never starts anything. With nothing filled in
  yet it says so and offers the link across to Edit, which does. Like Edit, it
  asks the host's `on_mount` whether it may render at all and draws only its
  message, or nothing while redirecting, when not.

  It is also where the answers are taken away from: Download PDF and Print
  send the browser out to a download endpoint, because a LiveView holds a
  websocket and cannot send a file. Both send the same document - the
  disposition header is the only difference - and both resolve the position
  the way this page does, so what is printed is what is shown. They are
  drawn only when the page knows where downloads live: the `download_path`
  attr, or `config :form_flow, download_path:` behind it. An application
  that configures neither is one that does not offer downloads, and this
  page says nothing about them.

  The one write here is Reopen, and it lives here on purpose: reopening
  changes state, so it stays an explicit button rather than a mode of a URL,
  and it belongs beside the answers it reopens. It sits in the header with
  Download PDF and Print, because it is the third thing to do with a set of
  answers - when they were submitted is the status badge's to say, not a
  banner's. It asks for confirmation first
  (`FormFlow.Web.Instances.Components.ReopenDialog`), since it puts the form
  back in front of everyone who can see it. It lands on Edit, where those
  answers can then be changed.

  ## The states it draws

  Every one of `FormFlow.Web.Instances.Shared.form_page_state/1`'s, each in
  its own `render/1` clause, and nothing else - there is no catch-all, so a
  state nobody accounted for raises rather than drawing the page to whoever
  reached it:

    * `:flow_not_found` - "This flow no longer exists."
    * `:redirecting` - nothing, while the host's `on_mount` navigates away
    * `:refused` - the host's message alone
    * `:not_visible` - "This form is not part of your work here."
    * `:not_started` - why there is nothing to show, and the way onward
    * `:broken_definition` - the parse error, inline
    * `:ready` and `:completed` - the answers, and what may be done with them

  Both actions guard on that same state, on `:ready` or `:completed`: the
  answers of a submitted form are as reopenable and as downloadable as those
  of one still in progress. A LiveComponent's events are reachable whenever
  it is mounted, and this one is mounted in every state above, so which
  buttons were drawn gates nothing.
  """

  use Phoenix.LiveComponent

  alias FormFlow.Config.Flows.Perspective
  alias FormFlow.Data.Instances
  alias FormFlow.Web.Components.Core
  alias FormFlow.Web.Controllers.Downloads
  alias FormFlow.Web.Downloads.Token
  alias FormFlow.Web.Instances.Components.Forms.Status
  alias FormFlow.Web.Instances.Components.Forms.Tabs
  alias FormFlow.Web.Instances.Components.Header
  alias FormFlow.Web.Instances.Components.ReopenDialog
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
      |> assign_new(:pre_release_user_ids, fn -> [] end)
      |> assign_new(:download_path, fn -> nil end)
      |> then(&assign(&1, :download_path, &1.assigns.download_path || Downloads.path()))
      |> assign_new(:uri, fn -> nil end)
      |> assign_new(:params, fn -> %{} end)
      |> assign_new(:error, fn -> nil end)
      |> assign_new(:confirming_reopen?, fn -> false end)

    {:ok, socket |> load() |> assign_page_state()}
  end

  # The state the page is in, computed once where the loading and the gate
  # ran. Every render clause matches on it and every event guards on it,
  # because a LiveComponent's events are reachable whenever it is mounted -
  # which it is even when the page drew a refusal instead. A button that was
  # never rendered is not a check.
  defp assign_page_state(socket) do
    assign(socket, :page_state, FormFlow.Web.Instances.Shared.form_page_state(socket.assigns))
  end

  # Both actions are the answers': a submitted form's Reopen and Download
  # work here the way they always have.
  @impl true
  def handle_event("form_flow:download", params, socket)
      when socket.assigns.page_state in [:ready, :completed] do
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

  def handle_event("form_flow:download", _params, socket), do: {:noreply, socket}

  def handle_event("request_reopen", _params, socket)
      when socket.assigns.page_state in [:ready, :completed] do
    {:noreply, assign(socket, :confirming_reopen?, true)}
  end

  # A refused event is silent: the client was not driving a rendered
  # control, and a message would describe the gate to whoever was probing
  # it. An *unknown* event still raises - there is no blanket clause.
  def handle_event("request_reopen", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_reopen", _params, socket) do
    {:noreply, assign(socket, :confirming_reopen?, false)}
  end

  def handle_event("confirm_reopen", _params, socket)
      when socket.assigns.page_state in [:ready, :completed] do
    socket = assign(socket, :confirming_reopen?, false)

    case Shared.reopen(socket.assigns) do
      {:ok, reopened} ->
        to =
          Paths.form_edit_path(
            socket.assigns.base,
            socket.assigns.flow_instance.id,
            reopened.path
          )

        {:noreply, push_navigate(socket, to: to)}

      {:error, message} ->
        {:noreply, assign(socket, :error, message)}
    end
  end

  def handle_event("confirm_reopen", _params, socket), do: {:noreply, socket}

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
  def render(%{page_state: :flow_not_found} = assigns) do
    ~H"""
    <div>
      <Core.alert components={@components}>
        <span>This flow no longer exists.</span>
        <.link navigate={Paths.flows_path(@base)} class="link link-primary">
          Back to flows
        </.link>
      </Core.alert>
    </div>
    """
  end

  # The host's on_mount is sending the user elsewhere: nothing to draw meanwhile
  def render(%{page_state: :redirecting} = assigns) do
    ~H"""
    <div></div>
    """
  end

  # The host's on_mount refused the page; its message is all there is to draw
  def render(%{page_state: :refused} = assigns) do
    ~H"""
    <div>
      <.page_header {header_assigns(assigns)} tabs={false} />

      <Core.alert components={@components}>
        <span>{@mount_error}</span>
        <.link navigate={Paths.flow_path(@base, @flow_instance.id)} class="link link-primary">
          Back to the flow
        </.link>
      </Core.alert>
    </div>
    """
  end

  # The flow's type says this form is not for the viewer - another
  # perspective's work. Nothing of it is shown, started or not.
  def render(%{page_state: :not_visible} = assigns) do
    ~H"""
    <div>
      <.page_header {header_assigns(assigns)} tabs={false} />

      <Core.alert components={@components}>
        <span>This form is not part of your work here.</span>
        <.link navigate={Paths.flow_path(@base, @flow_instance.id)} class="link link-primary">
          Back to the flow
        </.link>
      </Core.alert>
    </div>
    """
  end

  # Nothing filled in here yet, so there are no answers to show - only why,
  # and the way onward when there is one.
  def render(%{page_state: :not_started} = assigns) do
    ~H"""
    <div>
      <.page_header {header_assigns(assigns)} />

      <Core.alert components={@components}>
        <span>{unstarted_message(assigns)}</span>
        <.link
          :if={@editable?}
          navigate={Paths.form_edit_path(@base, @flow_instance.id, @path)}
          class="link link-primary"
        >
          Start this form
        </.link>
        <.link navigate={Paths.flow_path(@base, @flow_instance.id)} class="link link-primary">
          Back to the flow
        </.link>
      </Core.alert>
    </div>
    """
  end

  def render(%{page_state: :broken_definition} = assigns) do
    ~H"""
    <div>
      <.page_header {header_assigns(assigns)} />

      <Core.alert kind={:warning} components={@components}>
        <div>
          <p class="font-medium">This form can't be rendered.</p>
          <p class="mt-1 font-mono text-sm">{@parse_error}</p>
        </div>
      </Core.alert>
    </div>
    """
  end

  # The answers, and what may be done with them. There is no catch-all
  # clause: a state nobody accounted for raises here rather than drawing the
  # whole page to whoever reached it.
  def render(%{page_state: state} = assigns) when state in [:ready, :completed] do
    ~H"""
    <div>
      <.page_header {header_assigns(assigns)}>
        <%!-- A LiveView holds a websocket, not a response, so taking the
              answers away is a request of its own, authorized by a token
              this page mints on the click. Minting then, rather than when
              the page was drawn, is what lets a tab left open for days
              still print: the token is always seconds old, whatever the
              page is. --%>
        <div
          :if={@download_path}
          id={"#{@id}-downloads"}
          phx-hook=".Downloads"
          phx-target={@myself}
          class="flex flex-wrap items-center gap-2"
        >
          <Core.button components={@components} type="button" data-disposition="download" class="btn btn-ghost">
            Download PDF
          </Core.button>
          <Core.button components={@components} type="button" data-disposition="print" class="btn btn-ghost">
            Print
          </Core.button>
        </div>
      </.page_header>

      {@type.module.progress_component(%{
        id: "#{@id}-flow-progress",
        base: @base,
        flow_instance_id: @flow_instance.id,
        forms: @forms,
        current_path: @path,
        step_links: @step_links,
        context: @context,
        callback_data: @callback_data,
        components: @components
      })}

      <Core.error :if={@error} components={@components}>{@error}</Core.error>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".Downloads">
        export default {
          mounted() {
            this.el.addEventListener("click", (event) => {
              const trigger = event.target.closest("[data-disposition]")
              if (!trigger) return
              event.preventDefault()

              // Opened now, while the click is still the user's gesture: a
              // window.open after the round trip below is what popup blockers
              // are for. Download needs no tab - an attachment does not
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

      <ReopenDialog.reopen_dialog
        :if={@confirming_reopen?}
        target={@myself}
        components={@components}
      />

      <p :if={@form_instance.status != "completed" and @continue_allowed?} class="mb-4">
        <.link
          navigate={Paths.form_edit_path(@base, @flow_instance.id, @path)}
          class="link link-primary"
        >
          Continue filling this out
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

  # The header every clause but the first two draws: sticky, the form's
  # status after its name, and the three views as tabs with View chosen. A
  # refused or invisible form draws it without tabs - nothing of the form
  # is shown, so nothing of it is offered. The answers clause adds the last
  # event and the download buttons in the slot.
  attr(:base, :string, required: true)
  attr(:flow_instance, :map, required: true)
  attr(:flow_name, :string, required: true)
  attr(:label, :string, required: true)
  attr(:title, :string, default: nil)
  attr(:trail, :list, default: [])
  attr(:path, :list, required: true)
  attr(:form_instance, :map, default: nil)
  attr(:events, :list, default: [])
  attr(:id, :string, required: true)
  attr(:reopen_first?, :boolean, default: false)
  attr(:myself, :any, default: nil)
  attr(:components, :atom, default: nil)
  attr(:tabs, :boolean, default: true)
  slot(:inner_block)

  defp page_header(assigns) do
    ~H"""
    <Header.header
      base={@base}
      flow_instance={@flow_instance}
      flow_name={@flow_name}
      label={@label}
      title={@title}
      trail={@trail}
      sticky
    >
      <:status>
        <Status.badge
          id={"#{@id}-status"}
          form_instance={@form_instance}
          events={@events}
          components={@components}
        />
      </:status>
      <:actions :if={@tabs}>
        {render_slot(@inner_block)}
        <Tabs.tabs
          base={@base}
          flow_instance_id={@flow_instance.id}
          path={@path}
          active={:show}
          reopen_first?={@reopen_first?}
          target={@myself}
          class="ml-2"
        />
      </:actions>
    </Header.header>
    """
  end

  defp header_assigns(assigns) do
    %{
      base: assigns.base,
      flow_instance: assigns.flow_instance,
      flow_name: assigns.flow_name,
      label: assigns.form_label,
      title: assigns[:form] && assigns.form.label,
      trail: assigns[:form_trail] || [],
      path: assigns.path,
      form_instance: assigns[:form_instance],
      events: assigns[:events] || [],
      id: assigns.id,
      reopen_first?: reopen_first?(assigns),
      myself: assigns.myself,
      components: assigns.components
    }
  end

  # The Edit tab asks before it goes when there is nothing to edit until the
  # form is reopened, and reopening is allowed. Anything else - in progress,
  # or submitted in a flow that is read-only now - is an ordinary link to a
  # page that says what it can.
  defp reopen_first?(%{form_instance: %{status: "completed"}} = assigns),
    do: assigns[:continue_allowed?] == true

  defp reopen_first?(_assigns), do: false

  # Anything but an explicit print is a download: it never navigates the user
  # away from the page they were on
  defp disposition(%{"disposition" => "print"}), do: :print
  defp disposition(_params), do: :download

  defp unstarted_message(%{form: nil}), do: "This form is not part of this flow."
  defp unstarted_message(%{editable?: true}), do: "You haven't started this form yet."

  defp unstarted_message(_assigns),
    do: "This form isn't available yet - it comes later in the flow."
end
