defmodule FormFlow.Web.Instances.Components.Flows.Status do
  @moduledoc """
  `FormFlow.Web.Instances.Components.Flows.Status` says where one viewer
  stands in a flow instance, as the **standing badge** after the flow's
  name on its two pages: **Your turn**, **Needs your attention**, **Waiting
  on others**, **Completed**.

  The instance's row holds two words, `in_progress` and `completed`, and
  the listing shows those. This is a third reading, per viewer, derived
  from the rows the page drew for them - the forms their perspectives are
  for, each with the state the flow derives and the word the form pages
  give it (`FormFlow.Web.Instances.Components.Forms.Status.status/2`):

    * `:completed` - the instance is completed, whoever is looking
    * `:attention` - one of the viewer's forms was reopened since it was
      last submitted: someone sent it back to them
    * `:waiting` - every form of theirs is done, or none of them can be
      worked on now; what remains is someone else's
    * `:your_turn` - a form of theirs is in progress or ready to start
    * `nil` - nothing in the flow is for them; the page says so itself

  Attention outranks the rest because a form sent back is work the viewer
  did not know they had. Nothing stores the standing: it is the rows read
  again, so it cannot drift from what the page lists under it.

  Pure function first (`standing/2`, `label/1`), then the badge.
  """

  use Phoenix.Component

  alias FormFlow.Data.Instances
  alias FormFlow.Web.Components.Core

  @type standing :: :your_turn | :attention | :waiting | :completed

  @doc """
  The viewer's standing from their rows and the instance. Each row is the
  flow page's: `form` a `FormFlow.Data.Instances.FormProgress`, `editable?`
  the flow type's answer, and `word` the form pages' status of its
  instance - `:draft`, `:submitted`, `:reopened`, or nil before it starts.
  """
  @spec standing([map()], Instances.Flow.t()) :: standing() | nil
  def standing(_rows, %Instances.Flow{status: "completed"}), do: :completed
  def standing([], _flow_instance), do: nil

  def standing(rows, _flow_instance) do
    cond do
      Enum.any?(rows, &(&1.word == :reopened and &1.form.status == :in_progress)) -> :attention
      Enum.all?(rows, &(&1.form.status == :completed)) -> :waiting
      Enum.any?(rows, &workable?/1) -> :your_turn
      true -> :waiting
    end
  end

  # A form the viewer can pick up now: one of theirs in progress, or one
  # the flow lets them start
  defp workable?(%{form: %{status: :in_progress}}), do: true
  defp workable?(%{form: %{instance: nil}, editable?: true}), do: true
  defp workable?(_row), do: false

  @doc "A standing as `{text, kind}` - the words and the `Core.badge/1` palette."
  @spec label(standing()) :: {String.t(), atom()}
  def label(:your_turn), do: {"Your turn", :info}
  def label(:attention), do: {"Needs your attention", :warning}
  def label(:waiting), do: {"Waiting on others", :neutral}
  def label(:completed), do: {"Completed", :success}

  attr(:standing, :atom, default: nil, doc: "`standing/2`'s answer; nothing is drawn for nil")
  attr(:components, :atom, default: nil)
  attr(:class, :any, default: nil)

  @doc "The standing badge, for the header's `status` slot."
  def badge(assigns) do
    ~H"""
    <%= if @standing do %>
      <% {text, kind} = label(@standing) %>
      <Core.badge components={@components} kind={kind} class={@class}>{text}</Core.badge>
    <% end %>
    """
  end
end
