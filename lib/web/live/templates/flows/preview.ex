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
  form step in the order the Text layout of
  `FormFlow.Web.Templates.Flows.Overview` lists them: depth first from Start,
  following the edges, a subflow's forms where its step sits. A step
  reached twice - a loop back, two choices meeting again - is listed once.

  Then it draws one step at a time: the step's name and the subflows it
  sits in, the perspectives of the form subflow it belongs to when that
  names any, a select to jump to any step, Back and Forward, and the ring
  the instances index draws for flow progress, with "3 of 7" beside it.

  The form is `FormFlow.Web.Templates.Forms.Preview`, the same child
  LiveView the form template pages draw, mounted on the forms Canvas with
  the version the form's own page opens on - the latest published, else
  the newest draft - and no answers. Its `live_render` id is
  keyed by the step, so moving to another step remounts it fresh. It draws
  the form alone, not the instance page around it - the header, the
  progress card, the tabs - because the form is what this page is for and
  the instance page needs a journey to draw against. A step whose form has
  no version yet gets the Canvas's empty message in its place.

  The step is the `step` query param, a node id, so every step is a URL
  someone can be sent. Back, Forward, and the select all patch it. No
  param, or one naming a step the walk does not reach, is the first step.
  """

  use Phoenix.LiveComponent

  alias FormFlow.Data.Templates.Flows
  alias FormFlow.Data.Templates.Forms
  alias FormFlow.Web.Components.Core
  alias FormFlow.Web.Instances.Components.Flows.Progress
  alias FormFlow.Web.Templates.Components.Flows.Tabs
  alias FormFlow.Web.Templates.Components.Header
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
    steps = form_steps(tree)
    index = step_index(steps, socket.assigns.params["step"])
    current = index && Enum.at(steps, index)

    {:ok,
     assign(socket,
       flow: tree && tree.flow,
       steps: steps,
       index: index,
       current: current,
       version: current && current.form_id && preview_version(current.form_id),
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
          <Tabs.tabs base={@base} flow={@flow} active={:preview} />
        </:actions>
      </Header.header>

      <div :if={@steps == []} class="rounded-lg border border-zinc-300 bg-white px-6 py-5 text-sm">
        <p class="italic text-zinc-500">Nothing is connected to Start yet.</p>
      </div>

      <div :if={@current}>
        <div class="mb-4 flex flex-wrap items-center gap-6 rounded-lg border border-zinc-300 bg-white px-6 py-4">
          <span class="inline-flex items-center gap-3">
            <Progress.ring
              percent={round((@index + 1) / length(@steps) * 100)}
              behind={round(@index / length(@steps) * 100)}
              each={round((@index + 1) / length(@steps) * 100) - round(@index / length(@steps) * 100)}
              size={:lg}
            />
            <span class="text-sm text-zinc-500 tabular-nums">
              {@index + 1} of {length(@steps)}
            </span>
          </span>

          <div class="min-w-0 flex-1">
            <p :if={@current.trail != []} class="text-xs text-zinc-500">
              {Enum.join(@current.trail, " › ")}
            </p>
            <h2 class="text-lg font-semibold text-zinc-900">{@current.label}</h2>
            <p :if={@current.perspectives != []} class="text-xs text-zinc-500">
              Perspectives: {perspective_names(@current.perspectives, @perspective_options)}
            </p>
          </div>

          <form id={"#{@id}-jump"} phx-change="jump" phx-target={@myself} class="w-64">
            <PhoenixSelect.select
              id={"#{@id}-step"}
              name="step"
              value={@current.id}
              options={Enum.map(@steps, &{step_option_label(&1), &1.id})}
              placeholder="Jump to a form"
            />
          </form>

          <div class="flex items-center gap-2">
            <Core.button
              :if={@index > 0}
              patch={step_path(assigns, Enum.at(@steps, @index - 1).id)}
              components={@components}
            >
              Back
            </Core.button>
            <Core.button :if={@index == 0} disabled components={@components}>
              Back
            </Core.button>
            <Core.button
              :if={@index < length(@steps) - 1}
              patch={step_path(assigns, Enum.at(@steps, @index + 1).id)}
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
            id: "#{@id}-form-#{@current.id}",
            session: %{
              "id" => "#{@id}-form-#{@current.id}",
              "version_id" => @version && @version.id,
              "data" => %{}
            }
          )}
        </Canvas.canvas>
      </div>
    </div>
    """
  end

  # The version the form template's Show page opens on: the latest
  # published one, else the newest version there is - a draft, for a form
  # nobody has published yet
  defp preview_version(form_id) do
    Forms.get_latest_version(form_id) || List.first(Forms.list_versions(form_id))
  end

  defp step_path(assigns, node_id),
    do: "#{assigns.base}/flows/#{assigns.flow.id}/preview?step=#{node_id}"

  # "Application › Intake" - the step's name after the subflows it sits in
  defp step_option_label(%{trail: [], label: label}), do: label
  defp step_option_label(%{trail: trail, label: label}), do: Enum.join(trail ++ [label], " › ")

  defp perspective_names(ids, options) do
    Enum.map_join(ids, ", ", fn id ->
      Enum.find_value(options, fn {name, value} -> value == id && name end) || id
    end)
  end

  # The index of the step the URL names; the first step when it names none
  # or one the walk does not reach; nil when there are no steps at all
  defp step_index([], _node_id), do: nil

  defp step_index(steps, node_id) do
    Enum.find_index(steps, &(&1.id == node_id)) || 0
  end

  # Every form step of the tree in order, each as a map: the node's `id`
  # and `label`, its `form_id`, the `trail` of subflow names above it, and
  # the `perspectives` of the form subflow it belongs to
  defp form_steps(nil), do: []

  defp form_steps(tree) do
    tree
    |> walk_level([], MapSet.new())
    |> elem(0)
  end

  # One level from its Start, following the edges. `seen` is every node id
  # already listed, across levels - node ids are unique across the tree.
  defp walk_level(tree, trail, seen) do
    ctx = %{
      tree: tree,
      trail: trail,
      nodes: Map.new(tree.nodes, &{&1.id, &1}),
      next: Enum.group_by(tree.relationships, & &1.source_id, & &1.target_id),
      perspectives: level_perspectives(tree.flow)
    }

    case Enum.find(tree.nodes, &(kind(&1) == "start")) do
      nil -> {[], seen}
      start -> visit(Map.get(ctx.next, start.id, []), ctx, MapSet.put(seen, start.id))
    end
  end

  # A form subflow, or a root that is one, names who its forms are for;
  # a complex flow names nobody
  defp level_perspectives(%{label: "forms", properties: properties}),
    do: properties["perspectives"] || []

  defp level_perspectives(_flow), do: []

  # The targets in order: each one's own steps, then everything after it,
  # then the next target - so a branch is walked to its end before the
  # next branch starts, as the Text layout lists it
  defp visit([], _ctx, seen), do: {[], seen}

  defp visit([id | rest], ctx, seen) do
    if MapSet.member?(seen, id) or not Map.has_key?(ctx.nodes, id) do
      visit(rest, ctx, seen)
    else
      seen = MapSet.put(seen, id)
      {here, seen} = step_entries(ctx.nodes[id], ctx, seen)
      {following, seen} = visit(Map.get(ctx.next, id, []), ctx, seen)
      {later, seen} = visit(rest, ctx, seen)
      {here ++ following ++ later, seen}
    end
  end

  defp step_entries(node, ctx, seen) do
    cond do
      Map.has_key?(ctx.tree.subflows || %{}, node.id) ->
        walk_level(ctx.tree.subflows[node.id], ctx.trail ++ [label(node)], seen)

      kind(node) == "form" ->
        {[
           %{
             id: node.id,
             label: label(node),
             form_id: node.form_id,
             trail: ctx.trail,
             perspectives: ctx.perspectives
           }
         ], seen}

      true ->
        {[], seen}
    end
  end

  defp kind(node), do: get_in(node.properties, ["data", "kind"])
  defp label(node), do: get_in(node.properties, ["data", "label"]) || "Untitled"
end
