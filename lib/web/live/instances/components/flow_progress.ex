defmodule FormFlow.Web.Instances.Components.Flows.Progress do
  @moduledoc """
  `FormFlow.Web.Instances.Components.Flows.Progress` function component renders
  a "forms" flow's forms and their state — the sequence a filler is working
  through, above the form they are filling.

  The component draws what it is given. Whether to show it at all (a
  single-form flow isn't a sequence) and which forms can be jumped to
  (`clickable`, from `FormFlow.Data.Instances.Flows.Progress.actionable?/1`)
  are the caller's decisions — see `FormFlow.Web.Instances.Forms.Position`.

  A jumpable form is a link to that position's fill page — which is the page
  that opens it, so jumping needs no event of its own — and every other one
  is the same pill as plain text. Both carry identical classes, so the row
  doesn't shift as forms become reachable.

  `badge/1` lives here too: the wording and colors of a form's state, shared
  with the flow instance page's listing so the two can't drift.
  """

  use Phoenix.Component

  alias FormFlow.Web.Instances.Paths

  attr(:id, :string, required: true)
  attr(:base, :string, required: true, doc: "the router's mount prefix, for the links")
  attr(:flow_instance_id, :string, required: true)
  attr(:forms, :list, required: true, doc: "one \"forms\" flow's forms, in order")
  attr(:current_path, :list, default: nil, doc: "the form being filled, if any")

  attr(:clickable, :any,
    default: nil,
    doc:
      "a MapSet of the paths that can be navigated to — the current form " <>
        "belongs in it only if navigating to it would do something; nil for none"
  )

  def flow_progress(assigns) do
    ~H"""
    <ol id={@id} class="mb-4 flex flex-wrap items-center gap-1 text-xs">
      <li :for={{form, index} <- Enum.with_index(@forms, 1)} class="flex items-center gap-1">
        <% classes = classes(form, @current_path) %>
        <span :if={index > 1} aria-hidden="true" class="text-zinc-300">→</span>
        <.link
          :if={clickable?(@clickable, form)}
          navigate={Paths.form_edit_path(@base, @flow_instance_id, form.path)}
          class={[classes, "hover:border-zinc-400"]}
        >
          <.entry form={form} index={index} />
        </.link>
        <span
          :if={not clickable?(@clickable, form)}
          aria-current={form.path == @current_path && "step"}
          class={[classes, "cursor-default"]}
        >
          <.entry form={form} index={index} />
        </span>
      </li>
    </ol>
    """
  end

  @doc false
  attr(:form, :map, required: true)
  attr(:index, :integer, required: true)

  def entry(assigns) do
    ~H"""
    <span class="font-mono">{marker(@form.status, @index)}</span>
    <span>{@form.label}</span>
    <span class="sr-only">— {elem(badge(@form.status), 0)}</span>
    """
  end

  @doc """
  A form's derived status as `{text, classes}` — the wording and palette
  every surface showing progress uses.
  """
  def badge(:completed), do: {"Done", "bg-emerald-50 text-emerald-700 border-emerald-200"}
  def badge(:in_progress), do: {"In progress", "bg-amber-50 text-amber-700 border-amber-200"}
  def badge(:available), do: {"Available", "bg-cyan-50 text-cyan-700 border-cyan-200"}
  def badge(_pending), do: {"Pending", "bg-zinc-50 text-zinc-500 border-zinc-200"}

  defp classes(form, current_path) do
    [
      "flex items-center gap-1.5 rounded-full border px-2 py-0.5",
      elem(badge(form.status), 1),
      form.path == current_path && "font-semibold ring-1 ring-cyan-500"
    ]
  end

  defp clickable?(nil, _form), do: false
  defp clickable?(clickable, form), do: MapSet.member?(clickable, form.path)

  defp marker(:completed, _index), do: "✓"
  defp marker(_status, index), do: index
end
