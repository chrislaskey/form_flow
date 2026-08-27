defmodule FormFlow.Flows.Types.WizardAnyOrderTest do
  use ExUnit.Case, async: true

  alias FormFlow.Data.Instances.FormProgress
  alias FormFlow.Flows.Types.WizardAnyOrder

  defp form(name, status), do: %FormProgress{path: [name], label: name, status: status}

  describe "show_progress?/1" do
    test "the same answer as every type: a lone form is no sequence" do
      refute WizardAnyOrder.show_progress?([form("one", :available)])
      assert WizardAnyOrder.show_progress?([form("one", :available), form("two", :pending)])
    end
  end

  describe "openable?/2" do
    test "every form that isn't done — a filler can jump ahead" do
      forms = [
        available = form("one", :available),
        pending = form("two", :pending),
        started = form("three", :in_progress),
        done = form("four", :completed)
      ]

      assert WizardAnyOrder.openable?(available, forms)
      assert WizardAnyOrder.openable?(pending, forms)
      assert WizardAnyOrder.openable?(started, forms)
      refute WizardAnyOrder.openable?(done, forms)
    end
  end

  describe "next_form/2" do
    test "the next open form after the one just submitted" do
      forms = [form("one", :completed), form("two", :pending), form("three", :pending)]

      assert WizardAnyOrder.next_form(forms, ["one"]).label == "two"
    end

    test "skips what is already done" do
      forms = [form("one", :completed), form("two", :completed), form("three", :pending)]

      assert WizardAnyOrder.next_form(forms, ["one"]).label == "three"
    end

    test "wraps back to the beginning — a skipped form is still waiting there" do
      forms = [form("one", :pending), form("two", :in_progress), form("three", :completed)]

      assert WizardAnyOrder.next_form(forms, ["three"]).label == "one"
      assert WizardAnyOrder.next_form(forms, ["two"]).label == "one"
    end

    test "the last form submitted with earlier ones open comes back to them" do
      forms = [form("one", :completed), form("two", :pending), form("three", :completed)]

      assert WizardAnyOrder.next_form(forms, ["three"]).label == "two"
    end

    test "all done: nothing left here, so the journey decides — the end" do
      forms = [form("one", :completed), form("two", :completed)]

      assert is_nil(WizardAnyOrder.next_form(forms, ["two"]))
      assert is_nil(WizardAnyOrder.next_form([], ["two"]))
    end

    test "a position no longer in this flow starts from the top" do
      forms = [form("one", :completed), form("two", :pending)]

      assert WizardAnyOrder.next_form(forms, ["gone"]).label == "two"
    end
  end
end
