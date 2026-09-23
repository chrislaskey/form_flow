defmodule FormFlow.Web.Instances.Components.Flows.StatusTest do
  @moduledoc """
  The status of a flow instance for one viewer - its perspective status -
  from the rows the page drew for them: attention outranks the rest, a
  done part waits, a workable form is their turn, and a completed instance
  is completed whoever looks.
  """

  use ExUnit.Case, async: true

  alias FormFlow.Data.Instances
  alias FormFlow.Web.Instances.Components.Flows.Status

  @open %Instances.Flow{id: "flow-1", status: "in_progress"}
  @completed %Instances.Flow{id: "flow-1", status: "completed"}

  defp row(status, opts \\ []) do
    instance = if status == :completed or status == :in_progress, do: %Instances.Form{}, else: nil

    %{
      form: %Instances.FormProgress{
        path: [Atom.to_string(status)],
        status: status,
        instance: instance
      },
      editable?: Keyword.get(opts, :editable?, false),
      word: Keyword.get(opts, :word, nil),
      last: nil
    }
  end

  test "a completed instance is completed, whatever the rows say" do
    assert Status.status([row(:in_progress)], @completed) == :completed
    assert Status.status([], @completed) == :completed
  end

  test "no rows is no status: the page says nothing is for the viewer" do
    assert Status.status([], @open) == nil
  end

  test "a form sent back since it was submitted is attention, over everything else" do
    rows = [row(:in_progress, word: :reopened), row(:available, editable?: true), row(:completed)]
    assert Status.status(rows, @open) == :attention
  end

  test "a reopened word on a form since resubmitted is not attention" do
    assert Status.status([row(:completed, word: :submitted)], @open) == :waiting
  end

  test "every form done is waiting on others" do
    assert Status.status([row(:completed), row(:completed)], @open) == :waiting
  end

  test "a form in progress, or one the flow lets the viewer start, is their turn" do
    assert Status.status([row(:in_progress, word: :draft), row(:pending)], @open) == :your_turn
    assert Status.status([row(:available, editable?: true)], @open) == :your_turn
  end

  test "nothing workable and nothing done yet is waiting too" do
    assert Status.status([row(:pending), row(:available)], @open) == :waiting
  end

  test "every perspective status has words and a palette" do
    for status <- [:your_turn, :attention, :waiting, :completed] do
      assert {text, kind} = Status.label(status)
      assert is_binary(text) and is_atom(kind)
    end
  end
end
