defmodule FormFlow.Flows.Types.WizardInOrderTest do
  use ExUnit.Case, async: true

  alias FormFlow.Data.Instances.FormProgress
  alias FormFlow.Flows.Types.WizardInOrder

  defp form(name, status), do: %FormProgress{path: [name], label: name, status: status}

  describe "show_progress?/1" do
    test "a lone form is not a sequence worth drawing" do
      refute WizardInOrder.show_progress?([form("one", :available)])
      assert WizardInOrder.show_progress?([form("one", :available), form("two", :pending)])
      refute WizardInOrder.show_progress?([])
    end
  end

  describe "openable?/2" do
    test "only where the flow allows work — no jumping ahead, no reopening" do
      forms = [
        available = form("one", :available),
        pending = form("two", :pending),
        started = form("three", :in_progress),
        done = form("four", :completed)
      ]

      assert WizardInOrder.openable?(available, forms)
      assert WizardInOrder.openable?(started, forms)
      refute WizardInOrder.openable?(pending, forms)
      refute WizardInOrder.openable?(done, forms)
    end
  end

  describe "next_form/2" do
    test "the nearest form work can happen at, which for a chain is the next one" do
      forms = [form("one", :completed), form("two", :available), form("three", :pending)]

      assert WizardInOrder.next_form(forms, ["one"]).label == "two"
    end

    test "an in-progress form counts — a submit can land back on unfinished work" do
      forms = [form("one", :in_progress), form("two", :pending)]

      assert WizardInOrder.next_form(forms, ["two"]).label == "one"
    end

    test "nothing left, so the journey decides where the filler goes" do
      assert is_nil(WizardInOrder.next_form([form("one", :completed)], ["one"]))
      assert is_nil(WizardInOrder.next_form([form("one", :pending)], ["one"]))
      assert is_nil(WizardInOrder.next_form([], ["one"]))
    end
  end
end
