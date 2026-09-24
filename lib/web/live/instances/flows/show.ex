defmodule FormFlow.Web.Instances.Flows.Show do
  @moduledoc """
  `FormFlow.Web.Instances.Flows.Show` LiveComponent is one flow instance's
  page - its **Overview**: every form in flow order with its derived state,
  where the viewer stands among them, and what wants them next.

  ## What the page draws

  The header names the flow and, after its name, its **status for the
  viewer** - Your turn, Needs your attention, Waiting on others, Completed
  (`FormFlow.Web.Instances.Components.Flows.Status`). Its actions are the
  two views as tabs, **Overview | History**
  (`FormFlow.Web.Instances.Components.Flows.Tabs`), and **Download all**,
  drawn disabled: one PDF of every completed form does not exist yet, and
  the button says so on hover (`archive/plans/instances-refresh.md` §8).

  Under the header, a **card** for the whole flow in the vocabulary of the
  card a form page carries (`FormFlow.Web.Instances.Components.Flows.Progress`):
  the ring of forms done, the flow's name, "2 of 5 forms done · next Dog
  Information", and the one **Start** or **Continue** that goes to the form
  that wants the viewer now - a form sent back to them first, then one under
  way, then the first they may start.

  Then the forms. A complex flow draws **a card per subflow** the viewer
  can see - a small ring and "1 of 5 done" in its head, its forms as rows
  inside - because the flow reads that way on the admin canvas; a simple
  flow draws its rows in one bordered box. Every row is the form's name, its
  badge (Done / In progress / Available / Pending, or **Reopened** when the
  form was sent back since it was last submitted), what last happened to it
  and when, and its actions on the right. The row that is next up is tinted
  and carries the page's only primary button; every other Start or Continue
  is plain. Under it all, **Details** is the instance's own fact sheet.

  The badge is the row's own word, not the derivation's alone. A form's
  derived status is read inside its "forms" flow, where the first form of a
  subflow is `:available` the moment that flow's Start is - even when the
  step holding the flow is still shut. The row knows better, because it
  also asked `editable?` of the flow's type and walked the doors above the
  form (`FormFlow.Web.Instances.Flows.Shared`): an unstarted form the row
  makes no offer on reads **Pending**, because Available is an offer and
  this row has none. `row_status/1` is that word, and the badge, the
  greying and the row's tint all read it, so nothing on the row can say
  one thing while its buttons say another.

  Which forms appear, and which offer to start, is not this page's decision:
  each form belongs to a "forms" flow, and that flow's `FormFlow.Config.Flows.Type`
  answers `visible?/2` and `editable?/2` for it. A flow for another
  perspective is not listed at all; an in-order wizard offers only where the
  flow allows work; an any-order one offers every form of its own that isn't
  done, which is how a user jumps ahead. One instance can hold several
  "forms" flows with different types, so the questions are asked per form.
  A form of the viewer's own that sits behind a step only another
  perspective can open is not listed either, until that other side finishes
  - `FormFlow.Web.Instances.Flows.Shared` is where both rules are.
  When every form the viewer can see is done but the instance is not, the
  page says so: their part is finished, the rest is someone else's.

  Whether the page renders at all is the host's `on_mount` to say (with the
  flow instance's context): refused, only its message is drawn; redirected,
  nothing is until the navigation lands.

  Every action here navigates, because a form's URL addresses its *position*
  and so exists before its instance row does - starting happens on the form
  page itself (see `FormFlow.Web.Instances.Forms.Show`). Start, Continue and
  View are links wearing a button's clothes for that reason. Reopen is the
  exception: it changes state, so it posts an event, and it lives beside the
  answers it reopens. It asks for confirmation first
  (`FormFlow.Web.Instances.Components.ReopenDialog`), the row it is for held
  in `confirming_reopen_path` rather than resent by the confirming click, so
  a stray or forged click cannot supply a path this page never drew a
  button for.

  ## The states it draws

  There is no form in scope here, so the page asks the narrower
  `FormFlow.Web.Instances.Shared.page_state/1` and draws four states, each
  in its own `render/1` clause and with no catch-all:

    * `:flow_not_found` - "This flow no longer exists."
    * `:redirecting` - nothing, while the host's `on_mount` navigates away
    * `:refused` - the host's message alone
    * `:ready` - the forms and their state

  Reopen needs both rules. The state says whether the page may act at all;
  it cannot say whether it may act on *this* position, and the position
  arrives from the client. So the event also finds the row it names among
  the ones the page drew - rows are only forms the flow's type calls
  visible, and Reopen is only drawn on a completed row that has an instance.
  Without that second rule the event is not a reopen at all: an unstarted
  position falls through to `FormFlow.Data.Instances.Forms.update_status/4`'s
  create, which would start a form here, past the gate Edit is built around.

  That rule closes it for this page, not for the library. The create
  resolves a position's node with a bare lookup - no tenant, no flow
  narrowing - so **any** caller handing
  `FormFlow.Data.Instances.Forms.update_status/4` a client-supplied path has
  the same hole. Narrowing the lookup to the journey's own tree is the
  follow-up; it touches the data layer and needs its own audit of what would
  change.

  What the page shares with `FormFlow.Web.Instances.Flows.History` - the
  loading, the rows, the trail, the perspective status - is
  `FormFlow.Web.Instances.Flows.Shared`.
  """

  use Phoenix.LiveComponent

  alias FormFlow.Data.Instances
  alias FormFlow.Data.Instances.FlowProgress
  alias FormFlow.Data.Templates
  alias FormFlow.Web.Components.Core
  alias FormFlow.Web.Components.FactSheet
  alias FormFlow.Web.Components.SectionHeading
  alias FormFlow.Web.Instances.Components.Flows.Progress
  alias FormFlow.Web.Instances.Components.Flows.Status
  alias FormFlow.Web.Instances.Components.Flows.Tabs
  alias FormFlow.Web.Instances.Components.Forms.Status, as: FormStatus
  alias FormFlow.Web.Instances.Components.Header
  alias FormFlow.Web.Instances.Components.ReopenDialog
  alias FormFlow.Web.Instances.Flows.Shared
  alias FormFlow.Web.Instances.Paths

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> Shared.defaults()
      |> assign_new(:confirming_reopen_path, fn -> nil end)

    {:ok, socket |> Shared.load() |> assign_page_state()}
  end

  # The state the page is in, computed once where the loading and the gate
  # ran. Every render clause matches on it and the one event guards on it,
  # because a LiveComponent's events are reachable whenever it is mounted -
  # which it is even when the page drew a refusal instead.
  defp assign_page_state(socket) do
    assign(socket, :page_state, FormFlow.Web.Instances.Shared.page_state(socket.assigns))
  end

  # Reopening a position the page did not offer is not something the page
  # can do, so the row it names has to be one it drew: visible to the
  # viewer, completed, and holding an instance - the same three things the
  # Reopen button is drawn for.
  @impl true
  def handle_event("request_reopen", %{"path" => joined}, socket)
      when socket.assigns.page_state == :ready do
    path = String.split(joined, ",")

    case Enum.find(socket.assigns.rows, &(&1.form.path == path)) do
      %{form: %{status: :completed, instance: %Instances.Form{}}} ->
        {:noreply, assign(socket, :confirming_reopen_path, path)}

      _other ->
        {:noreply, socket}
    end
  end

  # A refused event is silent: the client was not driving a rendered
  # control, and a message would describe the gate to whoever was probing
  # it. Only a well-formed one, though - the params are matched here too, so
  # a "request_reopen" carrying no position is as much a `FunctionClauseError`
  # as an event name nothing answers to. Silence is for a refusal, not for a
  # message this page does not understand.
  def handle_event("request_reopen", %{"path" => _path}, socket), do: {:noreply, socket}

  def handle_event("cancel_reopen", _params, socket) do
    {:noreply, assign(socket, :confirming_reopen_path, nil)}
  end

  # The row it is for is read back from `confirming_reopen_path`, not the
  # click - the same rule `request_reopen` applies, asked again in case the
  # row changed underneath the open dialog.
  def handle_event("confirm_reopen", _params, socket)
      when socket.assigns.page_state == :ready do
    path = socket.assigns.confirming_reopen_path
    socket = assign(socket, :confirming_reopen_path, nil)

    case path && Enum.find(socket.assigns.rows, &(&1.form.path == path)) do
      %{form: %{status: :completed, instance: %Instances.Form{}}} -> reopen(socket, path)
      _other -> {:noreply, socket}
    end
  end

  def handle_event("confirm_reopen", _params, socket), do: {:noreply, socket}

  # The status is the pages' rule, asked again at the click from the flow
  # as it now is: the page drew Reopen while the flow allowed continuing,
  # and the year may have closed since. The data layer does what it is
  # asked (`FormFlow.Data.Instances.Forms.update_status/4`).
  defp reopen(socket, path) do
    flow = Templates.Flows.get_row(socket.assigns.flow_instance.template_flow_id)

    if Shared.continue_allowed?(flow, socket.assigns) do
      case Instances.Forms.update_status(socket.assigns.flow_instance, path, :in_progress,
             user_id: socket.assigns.user_id,
             tenant_id: socket.assigns.tenant_id,
             flow_types: socket.assigns.flow_types,
             callback_data: socket.assigns.callback_data
           ) do
        {:ok, _reopened} -> {:noreply, socket |> Shared.load() |> assign_page_state()}
        {:error, _reason} -> {:noreply, assign(socket, :error, "Could not reopen the form.")}
      end
    else
      {:noreply, assign(socket, :error, "This flow is read-only now.")}
    end
  end

  @impl true
  def handle_async(:navigate, {:ok, to}, socket) do
    {:noreply, push_navigate(socket, to: to)}
  end

  # The instance's status as `{text, kind}` - the same two words and palette
  # the listing uses for the same column
  defp status_badge("completed"), do: {"Completed", :success}
  defp status_badge(_in_progress), do: {"In progress", :warning}

  defp timestamp(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M") <> " UTC"

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
      <Header.header base={@base} flow_instance={@flow_instance} flow_name={@flow_name} />

      <Core.alert components={@components}>
        <span>{@mount_error}</span>
        <.link navigate={Paths.flows_path(@base)} class="link link-primary">
          Back to flows
        </.link>
      </Core.alert>
    </div>
    """
  end

  # The forms and their state. There is no catch-all clause: a state nobody
  # accounted for raises here rather than drawing the page to whoever
  # reached it.
  def render(%{page_state: :ready} = assigns) do
    ~H"""
    <div>
      <Header.header base={@base} flow_instance={@flow_instance} flow_name={@flow_name}>
        <:status>
          <Status.badge status={@perspective_status} components={@components} />
        </:status>
        <:actions>
          <%!-- One PDF of every completed form in flow order does not exist
                yet; each form's page downloads its own. Drawn only where
                downloads are on at all, and disabled, so the host sees the
                shape of what is coming without a button that does nothing --%>
          <span
            :if={@download_path}
            title="Downloading every form at once isn't available yet. Each form's page has its own download."
          >
            <Core.button components={@components} type="button" class="btn btn-ghost" disabled>
              Download all
            </Core.button>
          </span>
          <Tabs.tabs base={@base} flow_instance_id={@flow_instance.id} active={:show} class="ml-2" />
        </:actions>
      </Header.header>

      <Core.error :if={@error} components={@components}>{@error}</Core.error>

      <ReopenDialog.reopen_dialog
        :if={@confirming_reopen_path}
        target={@myself}
        components={@components}
      />

      <Core.alert :if={@rows == []} components={@components} class="mb-4">
        Nothing in this flow is for you to fill out.
      </Core.alert>

      <Core.alert :if={@part_done?} kind={:success} components={@components} class="mb-4">
        Your part is done. The rest of this flow is being worked on by others.
      </Core.alert>

      <.overall_card
        :if={@rows != []}
        base={@base}
        flow_instance={@flow_instance}
        flow_name={@flow_name}
        rows={@rows}
        next_up={@next_up}
        components={@components}
      />

      <%!-- A complex flow's forms are cards, one per subflow they belong
            to, each with its own count; a simple flow's need no heading,
            there is one group --%>
      <div :if={@rows != []} id={"#{@id}-forms"} class="space-y-4">
        <%= if length(@groups) > 1 do %>
          <div :for={{flow, rows} <- @groups} class="rounded-2xl border border-zinc-300">
            <div class="flex items-center gap-4 px-5 py-4">
              <Progress.ring size={:sm} {ring_assigns(rows)} />
              <div class="min-w-0 flex-1 leading-tight">
                <p class="font-semibold">{flow.name || "Untitled"}</p>
                <p class="text-xs text-zinc-500">{done(rows)} of {length(rows)} done</p>
              </div>
            </div>
            <div class="divide-y divide-zinc-200 border-t border-zinc-200">
              <.row
                :for={row <- rows}
                row={row}
                label={row.form.label}
                next_up={@next_up}
                base={@base}
                flow_instance={@flow_instance}
                continue_allowed?={@continue_allowed?}
                components={@components}
                myself={@myself}
                last
              />
            </div>
          </div>
        <% else %>
          <div :for={{_flow, rows} <- @groups} class="divide-y divide-zinc-200 rounded-lg border border-zinc-300">
            <.row
              :for={row <- rows}
              row={row}
              label={FlowProgress.qualified_label(row.form)}
              next_up={@next_up}
              base={@base}
              flow_instance={@flow_instance}
              continue_allowed?={@continue_allowed?}
              components={@components}
              myself={@myself}
            />
          </div>
        <% end %>
      </div>

      <Core.alert :if={@stranded != []} kind={:warning} components={@components} class="mt-6">
        {length(@stranded)} answer set(s) were filled at positions this flow no longer has.
        An administrator can resolve them.
      </Core.alert>

      <%!-- The instance's own facts, under the forms, read rather than
            edited: where it stands as a whole and when --%>
      <SectionHeading.section_heading
        title="Details"
        description="Where this flow stands as a whole, and when it was started."
        class="mt-8 mb-3"
      />
      <FactSheet.fact_sheet>
        <FactSheet.detail label="Flow">{@flow_name}</FactSheet.detail>
        <FactSheet.detail label="Status">
          <% {text, kind} = status_badge(@flow_instance.status) %>
          <Core.badge components={@components} kind={kind}>{text}</Core.badge>
        </FactSheet.detail>
        <FactSheet.detail label="Started">{timestamp(@flow_instance.inserted_at)}</FactSheet.detail>
        <FactSheet.detail label="Last updated">
          {timestamp(@flow_instance.updated_at)}
        </FactSheet.detail>
      </FactSheet.fact_sheet>
    </div>
    """
  end

  # The whole flow as the form pages' card: the ring of forms done, the
  # name, the count and what is next, and the one button that goes there
  attr(:base, :string, required: true)
  attr(:flow_instance, :map, required: true)
  attr(:flow_name, :string, required: true)
  attr(:rows, :list, required: true)
  attr(:next_up, :map, default: nil)
  attr(:components, :atom, default: nil)

  defp overall_card(assigns) do
    assigns = assign(assigns, done: done(assigns.rows), total: length(assigns.rows))

    ~H"""
    <div class="mb-6 flex flex-wrap items-center gap-5 rounded-2xl border border-zinc-300 px-5 py-4">
      <Progress.ring {ring_assigns(@rows)} />
      <div class="min-w-0 flex-1">
        <p class="truncate text-lg font-semibold leading-tight">{@flow_name}</p>
        <p class="text-sm text-zinc-500">
          {@done} of {@total} forms done
          <span :if={@next_up}>· next {@next_up.form.label}</span>
          <span :if={is_nil(@next_up) and @done == @total}>· all done</span>
          <span :if={is_nil(@next_up) and @done < @total}>· nothing for you right now</span>
        </p>
      </div>
      <Core.button
        :if={@next_up}
        components={@components}
        navigate={Paths.form_edit_path(@base, @flow_instance.id, @next_up.form.path)}
        variant="primary"
      >
        {if @next_up.form.instance, do: "Continue", else: "Start"}
      </Core.button>
    </div>
    """
  end

  # One form: its name, its badge, what last happened to it, its actions.
  # The row that is next up is tinted and carries the only primary button.
  attr(:row, :map, required: true)
  attr(:label, :string, required: true)
  attr(:next_up, :map, default: nil)
  attr(:base, :string, required: true)
  attr(:flow_instance, :map, required: true)
  attr(:continue_allowed?, :boolean, required: true)
  attr(:components, :atom, default: nil)
  attr(:myself, :any, required: true)
  attr(:last, :boolean, default: false, doc: "the row list's last row rounds the card's corners")

  defp row(assigns) do
    assigns =
      assign(assigns, next?: assigns.row == assigns.next_up, status: row_status(assigns.row))

    ~H"""
    <div
      data-path={Enum.join(@row.form.path, ",")}
      class={[
        "flex flex-wrap items-center gap-3 px-6 py-4",
        @next? && "bg-primary/5",
        @last && "last:rounded-b-2xl",
        @status == :pending && "text-zinc-400"
      ]}
    >
      <% {text, kind} = row_badge(@status) %>
      <span class={[if(@next?, do: "font-semibold", else: "font-medium")]}>{@label}</span>
      <Core.badge components={@components} kind={kind}>{text}</Core.badge>
      <span :if={@row.last} class="text-sm text-zinc-500" title={FormStatus.absolute(@row.last.event.inserted_at)}>
        {FormStatus.event_label(@row.last.event)}
        {FormFlow.Web.Templates.Shared.relative(@row.last.event.inserted_at)}
        <span :if={@row.last.event.user_id}>· <code class="text-xs">{@row.last.event.user_id}</code></span>
      </span>
      <span class="ml-auto flex items-center gap-3">
        <%!-- Start is the offer to begin work here - an any-order wizard
              makes it on forms an in-order one keeps closed. A form
              already started continues instead; both land on the same
              page, which is the one that starts the form. --%>
        <Core.button
          :if={@row.editable? && is_nil(@row.form.instance)}
          components={@components}
          navigate={Paths.form_edit_path(@base, @flow_instance.id, @row.form.path)}
          class={if(@next?, do: "btn btn-primary", else: "btn")}
        >
          Start
        </Core.button>
        <Core.button
          :if={@row.form.status == :in_progress && @row.form.instance && @continue_allowed?}
          components={@components}
          navigate={Paths.form_edit_path(@base, @flow_instance.id, @row.form.path)}
          class={if(@next?, do: "btn btn-primary", else: "btn")}
        >
          Continue
        </Core.button>
        <.link
          :if={@row.form.status == :completed && @row.form.instance}
          navigate={Paths.form_path(@base, @flow_instance.id, @row.form.path)}
          class="text-cyan-600 hover:underline"
        >
          View
        </.link>
        <Core.button
          :if={@row.form.status == :completed && @row.form.instance && @continue_allowed?}
          components={@components}
          phx-click="request_reopen"
          phx-value-path={Enum.join(@row.form.path, ",")}
          phx-target={@myself}
          class="text-cyan-600 hover:underline"
        >
          Reopen
        </Core.button>
      </span>
    </div>
    """
  end

  # A row's state as the page says it: the derived status of its form,
  # except that a form sent back since it was last submitted reads Reopened,
  # as its own pages say, and an unstarted form this row offers nothing on
  # reads Pending rather than Available - the door above it is shut, or its
  # flow's type keeps it closed
  defp row_status(%{word: :reopened, form: %{status: :in_progress}}), do: :reopened

  defp row_status(%{editable?: false, form: %{status: :available, instance: nil}}), do: :pending

  defp row_status(%{form: %{status: status}}), do: status

  defp row_badge(:reopened), do: FormStatus.label(:reopened)
  defp row_badge(status), do: Progress.badge(status)

  defp done(rows), do: Enum.count(rows, &(&1.form.status == :completed))

  # The ring's three numbers for a list of rows: done in the brand colour,
  # in progress tinted, the percentage done inside
  defp ring_assigns(rows) do
    total = length(rows)
    behind = round(done(rows) / total * 100)
    each = round(Enum.count(rows, &(&1.form.status == :in_progress)) / total * 100)
    %{percent: behind, behind: behind, each: each}
  end
end
