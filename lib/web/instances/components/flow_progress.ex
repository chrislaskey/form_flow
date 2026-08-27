defmodule FormFlow.Web.Instances.Components.FlowProgress do
  @moduledoc """
  `FormFlow.Web.Instances.Components.FlowProgress` function component renders
  a "forms" flow's forms and their state — the sequence a filler is working
  through, above the form they are filling.

  The component is type-agnostic: it draws what it is given. Whether to show
  it at all (`FormFlow.Flows.Types.show_progress?/1` — a single-form flow
  isn't a sequence) and which forms can be jumped to (`clickable`, from
  `FormFlow.Flows.Types.openable?/2`) are the caller's questions to ask its
  `FormFlow.Flows.Types` module. A jumpable form is a button sending
  `"open_form"` to `target`; every other one renders as the same button,
  disabled — one element either way, so the row doesn't shift as forms become
  reachable.

  `badge/1` lives here too: the wording and colors of a form's state, shared
  with the journey page's listing so the two can't drift.
  """

  use Phoenix.Component

  attr(:id, :string, required: true)
  attr(:forms, :list, required: true, doc: "one \"forms\" flow's forms, in order")
  attr(:current_path, :list, default: nil, doc: "the form being filled, if any")

  attr(:clickable, :any,
    default: nil,
    doc:
      "a MapSet of the paths that can be navigated to — the current form " <>
        "belongs in it only if navigating to it would do something; nil for none"
  )

  attr(:target, :any, default: nil, doc: "the LiveComponent receiving open_form")

  def flow_progress(assigns) do
    ~H"""
    <ol id={@id} class="mb-4 flex flex-wrap items-center gap-1 text-xs">
      <li :for={{form, index} <- Enum.with_index(@forms, 1)} class="flex items-center gap-1">
        <% {text, classes} = badge(form.status) %>
        <span :if={index > 1} aria-hidden="true" class="text-zinc-300">→</span>
        <button
          type="button"
          disabled={not clickable?(@clickable, form)}
          phx-click="open_form"
          phx-value-path={Enum.join(form.path, ",")}
          phx-target={@target}
          aria-current={form.path == @current_path && "step"}
          class={[
            "flex items-center gap-1.5 rounded-full border px-2 py-0.5",
            classes,
            form.path == @current_path && "font-semibold ring-1 ring-cyan-500",
            if(clickable?(@clickable, form), do: "hover:border-zinc-400", else: "cursor-default")
          ]}
        >
          <span class="font-mono">{marker(form.status, index)}</span>
          <span>{form.label}</span>
          <span class="sr-only">— {text}</span>
        </button>
      </li>
    </ol>
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

  defp clickable?(nil, _form), do: false
  defp clickable?(clickable, form), do: MapSet.member?(clickable, form.path)

  defp marker(:completed, _index), do: "✓"
  defp marker(_status, index), do: index
end
