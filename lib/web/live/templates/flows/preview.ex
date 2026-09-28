defmodule FormFlow.Web.Templates.Flows.Preview do
  @moduledoc """
  `FormFlow.Web.Templates.Flows.Preview` LiveComponent walks one root flow's
  forms from end to end, every one of them empty, at `/flows/:id/preview`.
  A template page, so admins alone reach it.

  A pre-release flow is walked for real: a journey, records, prefills,
  every gate. This page is the fast look instead - what does each form look
  like, one after the other, with nothing filled in. It resolves the tree
  (`FormFlow.Data.Templates.Flows.resolve_tree/1`), keeps the steps
  connected to each level's Start (`connected_tree/1`), and lists every
  form step the way the instance pages do
  (`FormFlow.Data.Instances.FlowProgress.forms/2`): the order a user works
  them, a subflow's forms where its step sits, each step once. So "3 of 7"
  here is the same 3 of 7 a journey's progress card shows, and the select
  lists the steps the way a form's "Form to review" setting offers them.

  Then it draws one step at a time: the step's name under the subflows it
  sits in, the perspectives of the form subflow it belongs to when that
  names any, the form's type properties as a small table, one row each -
  every one with a value, as the form template's own page lists them in
  its fact sheet (`FormFlow.Web.Templates.Shared.display_value/2`), a Review's
  "Form to review" among them, that one a link that jumps to the step it
  names, and a pointer at a form no longer offered marked as missing, so a
  mis-set review is seen here before release - a select to jump to any
  step, Back and Forward, and the ring the instances index draws for flow
  progress, with "3 of 7" beside it.

  The form is `FormFlow.Web.Templates.Forms.Preview`, the same child
  LiveView the form template pages draw, mounted on the forms Canvas with
  the version the form's own page opens on - the latest published, else
  the newest draft - and no answers. Its `live_render` id is keyed by the
  step, so moving to another step remounts it fresh. It draws the form
  alone, not the instance page around it - the header, the progress card,
  the tabs - because the form is what this page is for and the instance
  page needs a journey to draw against. A step whose form has no version
  yet gets the Canvas's empty message in its place.

  Two query params say which step:

    * `step` - a form step's node id. Back, Forward, and the select all
      patch it, so every step is a URL someone can be sent.
    * `node` - any node id: a form step, or a subflow step, at any depth.
      The page opens on the first form step at or inside it. This is how
      the Preview tab on a subflow's own View and Edit pages
      (`/flows/:root/nodes/:node_id`) opens the preview where the admin
      is, without those pages knowing which form comes first.

  Neither, or one naming a step the walk does not reach, is the first
  step. The page's View and Edit tabs go to the canvas the current step
  sits on - the subflow's, or the root's - never to the form template's
  own pages.
  """

  use Phoenix.LiveComponent

  alias FormFlow.Config.Forms.Type
  alias FormFlow.Config.Property
  alias FormFlow.Data.Instances.FlowProgress
  alias FormFlow.Data.Instances.FormProgress
  alias FormFlow.Data.Templates.Flows
  alias FormFlow.Data.Templates.Forms
  alias FormFlow.Web.Components.Core
  alias FormFlow.Web.Instances.Components.Flows.Progress
  alias FormFlow.Web.Templates.Components.Flows.Tabs
  alias FormFlow.Web.Templates.Components.Header
  alias FormFlow.Web.Templates.Components.Health
  alias FormFlow.Web.Templates.Forms.Components.Canvas
  alias FormFlow.Web.Templates.Forms.Preview, as: FormPreview
  alias FormFlow.Web.Templates.Shared

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:base, fn -> "" end)
      |> assign_new(:flow_types, fn -> FormFlow.Config.Flows.Type.defaults() end)
      |> assign_new(:form_types, fn -> FormFlow.Config.Forms.Type.defaults() end)
      |> assign_new(:components, fn -> nil end)
      |> assign_new(:params, fn -> %{} end)

    tree = socket.assigns.flow_id |> Flows.resolve_tree() |> Flows.connected_tree()
    steps = if tree, do: FlowProgress.forms(tree, []), else: []
    index = step_index(steps, socket.assigns.params)
    current = index && Enum.at(steps, index)
    form = current && current.node.form_id && Forms.get(current.node.form_id)

    {:ok,
     assign(socket,
       flow: tree && tree.flow,
       steps: steps,
       index: index,
       current: current,
       form: form,
       version: form && preview_version(form.id),
       properties: property_values(socket.assigns.form_types, form, current, tree, steps),
       perspective_options:
         socket.assigns.flow_types
         |> Shared.all_perspectives()
         |> Shared.perspective_options()
     )}
  end

  # The select's choice: patch the URL to that step
  @impl true
  def handle_event("jump", %{"step" => node_id}, socket) do
    {:noreply, push_patch(socket, to: step_path(socket.assigns, node_id))}
  end

  @impl true
  def render(%{flow: nil} = assigns) do
    ~H"""
    <div>
      <Core.alert components={@components}>
        <span>Flow not found.</span>
        <.link navigate={"#{@base}/flows"} class="link link-primary">Back to flows</.link>
      </Core.alert>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div>
      <Header.header
        base={@base}
        section="flows"
        root={@flow}
        name="Preview"
        components={@components}
      >
        <:crumb>Preview</:crumb>
        <:actions>
          <Health.health base={@base} flow={@flow} components={@components} />
          <%!-- View and Edit go to the canvas the current step sits on --%>
          <Tabs.tabs
            base={@base}
            flow={@flow}
            root_id={@flow.id}
            node_id={@current && level_node_id(@current)}
            active={:preview}
            class="ml-2"
          />
        </:actions>
      </Header.header>

      <div :if={@steps == []} class="rounded-lg border border-zinc-300 bg-white px-6 py-5 text-sm">
        <p class="italic text-zinc-500">Nothing is connected to Start yet.</p>
      </div>

      <div :if={@current}>
        <div class="mb-4 flex flex-wrap items-center gap-6 rounded-lg border border-zinc-300 bg-white px-6 py-4">
          <span class="inline-flex items-center gap-3">
            <Progress.ring
              percent={percent(@index + 1, @steps)}
              behind={percent(@index, @steps)}
              each={percent(@index + 1, @steps) - percent(@index, @steps)}
              size={:lg}
            />
            <span class="text-sm text-zinc-500 tabular-nums">
              {@index + 1} of {length(@steps)}
            </span>
          </span>

          <div class="min-w-0 flex-1">
            <p :if={@current.ancestors != []} class="text-xs text-zinc-500">
              {Enum.join(FlowProgress.ancestor_labels(@current), " / ")}
            </p>
            <h2 class="text-lg font-semibold text-zinc-900">{@current.label}</h2>
            <p :if={perspectives(@current) != []} class="text-xs text-zinc-500">
              Perspectives: {perspective_names(perspectives(@current), @perspective_options)}
            </p>
            <%!-- The type's properties with a value, as the form template's
                  fact sheet lists them; a form pointer links to its step --%>
            <table :if={@properties != []} class="mt-1 text-xs">
              <tbody>
                <tr :for={entry <- @properties}>
                  <th scope="row" class="pr-3 text-left font-normal text-zinc-500">
                    {entry.property.name}
                  </th>
                  <td class={["text-zinc-700", entry.missing? && "text-error"]}>
                    <.link
                      :if={entry.step}
                      patch={step_path(assigns, node_id(entry.step))}
                      class="link link-primary"
                    >
                      {entry.text}
                    </.link>
                    <span :if={!entry.step}>{entry.text}</span>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <form id={"#{@id}-jump"} phx-change="jump" phx-target={@myself} class="w-64">
            <PhoenixSelect.select
              id={"#{@id}-step"}
              name="step"
              value={node_id(@current)}
              options={Enum.map(@steps, &{FlowProgress.qualified_label(&1), node_id(&1)})}
              placeholder="Jump to a form"
            />
          </form>

          <div class="flex items-center gap-2">
            <Core.button
              :if={@index > 0}
              patch={step_path(assigns, node_id(Enum.at(@steps, @index - 1)))}
              components={@components}
            >
              Back
            </Core.button>
            <Core.button :if={@index == 0} disabled components={@components}>
              Back
            </Core.button>
            <Core.button
              :if={@index < length(@steps) - 1}
              patch={step_path(assigns, node_id(Enum.at(@steps, @index + 1)))}
              variant="primary"
              components={@components}
            >
              Forward
            </Core.button>
            <Core.button
              :if={@index == length(@steps) - 1}
              disabled
              variant="primary"
              components={@components}
            >
              Forward
            </Core.button>
          </div>
        </div>

        <Canvas.canvas definition={(@version && @version.definition) || %{}} components={@components}>
          <:empty>This step's form has no version to preview yet.</:empty>
          {live_render(@socket, FormPreview,
            id: "#{@id}-form-#{node_id(@current)}",
            session: %{
              "id" => "#{@id}-form-#{node_id(@current)}",
              "version_id" => @version && @version.id,
              "data" => %{}
            }
          )}
        </Canvas.canvas>
      </div>
    </div>
    """
  end

  # The stored type's property values with the properties that declare
  # them, the way the form template's Show page lists them - only those
  # with a value - each as `%{property, text, step, missing?}`: `text` is
  # `FormFlow.Web.Templates.Shared.display_value/2`'s, with the form
  # pointers' choices filled in for this step's place in the flow
  # (`fill_related_forms/2`); `step` is the form step a `:related_form`
  # value names, when it is among the forms offered - the value is the
  # step's path, node ids joined by "/"; `missing?` marks a pointer at a
  # form no longer offered.
  defp property_values(_types, nil, _current, _tree, _steps), do: []

  defp property_values(types, form, current, tree, steps) do
    values = Type.property_values(form)

    types =
      Shared.fill_related_forms(types,
        root_id: tree.flow.id,
        node_id: node_id(current),
        tenant_id: form.tenant_id,
        property_values: values
      )

    for property <- Shared.properties(types, form.properties["form_type"]),
        value <- [values[property.id]],
        value not in [nil, "", []] do
      offered? = not Property.choice?(property) or offered?(property, value)

      %{
        property: property,
        text: Shared.display_value(property, value),
        step: offered? && related_step(property, value, steps),
        missing?: property.type in [:related_form, :related_form_in_any_flow] and not offered?
      }
    end
  end

  # Whether a choice's value is among the property's options - a list value
  # (a checkbox group's) when every one is
  defp offered?(%Property{options: options}, value) when is_list(value),
    do: Enum.all?(value, &List.keymember?(options || [], &1, 1))

  defp offered?(%Property{options: options}, value), do: List.keymember?(options || [], value, 1)

  defp related_step(%Property{type: :related_form}, value, steps),
    do: Enum.find(steps, &(Enum.join(&1.path, "/") == value))

  defp related_step(_property, _value, _steps), do: nil

  # The version the form template's Show page opens on: the latest
  # published one, else the newest version there is - a draft, for a form
  # nobody has published yet
  defp preview_version(form_id) do
    Forms.get_latest_version(form_id) || List.first(Forms.list_versions(form_id))
  end

  defp step_path(assigns, node_id),
    do: "#{assigns.base}/flows/#{assigns.flow.id}/preview?step=#{node_id}"

  # A step's own node: the last of its path
  defp node_id(%FormProgress{path: path}), do: List.last(path)

  # The subflow step the form sits in - the canvas its View and Edit are -
  # or nil for a form in the root itself
  defp level_node_id(%FormProgress{ancestors: []}), do: nil
  defp level_node_id(%FormProgress{ancestors: ancestors}), do: List.last(ancestors).id

  defp percent(count, steps), do: round(count / length(steps) * 100)

  # A form subflow, or a root that is one, names who its forms are for;
  # a complex flow names nobody
  defp perspectives(%FormProgress{flow: %{label: "forms", properties: properties}}),
    do: properties["perspectives"] || []

  defp perspectives(_step), do: []

  defp perspective_names(ids, options) do
    Enum.map_join(ids, ", ", fn id ->
      Enum.find_value(options, fn {name, value} -> value == id && name end) || id
    end)
  end

  # The index of the step the URL names: `step` a form step's own node,
  # `node` any node the first form at or inside it. The first step when
  # neither names one the walk reaches; nil when there are no steps at all.
  defp step_index([], _params), do: nil

  defp step_index(steps, params) do
    Enum.find_index(steps, &(node_id(&1) == params["step"])) ||
      Enum.find_index(steps, &(is_binary(params["node"]) and params["node"] in &1.path)) ||
      0
  end
end
