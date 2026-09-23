defmodule FormFlow.Web.Instances.Components.Flows.Status do
  @moduledoc """
  `FormFlow.Web.Instances.Components.Flows.Status` is the status of a flow
  instance for one perspective - the viewer's - as the **status badge**
  after the flow's name on its two pages: **Your turn**, **Needs your
  attention**, **Waiting on others**, **Completed**.

  The instance's row holds two words, `in_progress` and `completed`, and
  the listing shows those. This is a third reading, per perspective: the
  same journey is Your turn for the reviewer and Waiting on others for the
  applicant. It is called a **perspective status** wherever the bare word
  would be read as the journey's own, and it is derived from the rows the
  page drew for the viewer - the forms their perspectives are for, each
  with the state the flow derives and the word the form pages give it
  (`FormFlow.Web.Instances.Components.Forms.Status.status/2`):

    * `:completed` - the instance is completed, whoever is looking
    * `:attention` - one of the viewer's forms was reopened since it was
      last submitted: someone sent it back to them
    * `:waiting` - every form of theirs is done, or none of them can be
      worked on now; what remains is someone else's
    * `:your_turn` - a form of theirs is in progress or ready to start
    * `nil` - nothing in the flow is for them; the page says so itself

  Attention outranks the rest because a form sent back is work the viewer
  did not know they had. Nothing stores the perspective status: it is the
  rows read again, so it cannot drift from what the page lists under it.

  Pure function first (`status/2`, `label/1`), then the badge - the
  sibling of `FormFlow.Web.Instances.Components.Forms.Status.status/2`,
  which is the same question asked of one form.
  """

  use Phoenix.Component

  alias FormFlow.Data.Instances
  alias FormFlow.Web.Components.Core

  @type status :: :your_turn | :attention | :waiting | :completed

  @doc """
  The perspective status from the viewer's rows and the instance. Each row is the
  flow page's: `form` a `FormFlow.Data.Instances.FormProgress`, `editable?`
  the flow type's answer, and `word` the form pages' status of its
  instance - `:draft`, `:submitted`, `:reopened`, or nil before it starts.
  """
  @spec status([map()], Instances.Flow.t()) :: status() | nil
  def status(_rows, %Instances.Flow{status: "completed"}), do: :completed
  def status([], _flow_instance), do: nil

  def status(rows, _flow_instance) do
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

  @doc "A perspective status as `{text, kind}` - the words and the `Core.badge/1` palette."
  @spec label(status()) :: {String.t(), atom()}
  def label(:your_turn), do: {"Your turn", :info}
  def label(:attention), do: {"Needs your attention", :warning}
  def label(:waiting), do: {"Waiting on others", :neutral}
  def label(:completed), do: {"Completed", :success}

  attr(:status, :atom, default: nil, doc: "`status/2`'s answer; nothing is drawn for nil")
  attr(:components, :atom, default: nil)
  attr(:class, :any, default: nil)

  @doc "The perspective status badge, for the header's `status` slot."
  def badge(assigns) do
    ~H"""
    <%= if @status do %>
      <% {text, kind} = label(@status) %>
      <Core.badge components={@components} kind={kind} class={@class}>{text}</Core.badge>
    <% end %>
    """
  end
end
