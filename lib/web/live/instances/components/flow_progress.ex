defmodule FormFlow.Web.Instances.Components.Flows.Progress do
  @moduledoc """
  `FormFlow.Web.Instances.Components.Flows.Progress` function component renders
  a "forms" flow's forms and their state — the sequence a user is working
  through, above the form they are filling.

  The component is type-agnostic: it draws what it is given. Whether to draw
  it at all and which forms can be jumped to (`clickable`) are the flow
  type's decisions — `progress_component/1` and `editable?/2` of
  `FormFlow.Config.Flows.Type` — asked by `FormFlow.Web.Instances.Forms.Shared`.

  A jumpable form is a link to that position's fill page — which is the page
  that starts it, so jumping needs no event of its own — and every other one
  is the same badge as plain text. The badge itself is identical either way,
  so the row doesn't shift as forms become reachable; the link only wraps it.

  `badge/1` lives here too: the wording and the palette of a form's state,
  shared with the flow instance page's listing so the two can't drift.
  """

  use Phoenix.Component

  alias FormFlow.Web.Components.Core
  alias FormFlow.Web.Instances.Paths

  attr(:id, :string, required: true)
  attr(:base, :string, required: true, doc: "the router's mount prefix, for the links")
  attr(:flow_instance_id, :string, required: true)
  attr(:forms, :list, required: true, doc: "one \"forms\" flow's forms, in order")
  attr(:current_path, :list, default: nil, doc: "the form being filled, if any")
  attr(:components, :atom, default: nil)

  attr(:clickable, :any,
    default: nil,
    doc:
      "a MapSet of the paths that can be navigated to — the current form " <>
        "belongs in it only if navigating to it would do something; nil for none"
  )

  def flow_progress(assigns) do
    ~H"""
    <ol id={@id} class="mb-6 flex flex-wrap items-center gap-2">
      <li :for={{form, index} <- Enum.with_index(@forms, 1)} class="flex items-center gap-2">
        <span :if={index > 1} aria-hidden="true" class="text-base-content/30 text-sm">→</span>
        <.link
          :if={clickable?(@clickable, form)}
          navigate={Paths.form_edit_path(@base, @flow_instance_id, form.path)}
          class="hover:opacity-70"
        >
          <.entry
            form={form}
            index={index}
            current_path={@current_path}
            components={@components}
          />
        </.link>
        <.entry
          :if={not clickable?(@clickable, form)}
          form={form}
          index={index}
          current_path={@current_path}
          components={@components}
          aria-current={form.path == @current_path && "step"}
        />
      </li>
    </ol>
    """
  end

  @doc false
  attr(:form, :map, required: true)
  attr(:index, :integer, required: true)
  attr(:current_path, :list, default: nil)
  attr(:components, :atom, default: nil)
  attr(:rest, :global)

  def entry(assigns) do
    ~H"""
    <Core.badge
      components={@components}
      kind={elem(badge(@form.status), 1)}
      class={[
        "badge-lg gap-2",
        @form.path == @current_path && "font-semibold ring-2 ring-primary ring-offset-1"
      ]}
      {@rest}
    >
      <span class="font-mono">{marker(@form.status, @index)}</span>
      <span>{@form.label}</span>
      <span class="sr-only">— {elem(badge(@form.status), 0)}</span>
    </Core.badge>
    """
  end

  @doc """
  A form's derived status as `{text, kind}` — the wording and the
  `FormFlow.Web.CoreComponents.badge/1` palette every surface showing
  progress uses.
  """
  def badge(:completed), do: {"Done", :success}
  def badge(:in_progress), do: {"In progress", :warning}
  def badge(:available), do: {"Available", :info}
  def badge(_pending), do: {"Pending", :neutral}

  defp clickable?(nil, _form), do: false
  defp clickable?(clickable, form), do: MapSet.member?(clickable, form.path)

  defp marker(:completed, _index), do: "✓"
  defp marker(_status, index), do: index
end
