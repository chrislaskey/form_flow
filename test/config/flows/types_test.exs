defmodule FormFlow.Config.Flows.TypesTest do
  use ExUnit.Case, async: true

  alias FormFlow.Config.Flows.Type
  alias FormFlow.Context
  alias FormFlow.Data.Instances.FormProgress
  alias FormFlow.Data.Instances.SubflowProgress
  alias FormFlow.Web.Components.Flows.Types

  # A host's own type: overrides one callback and inherits the rest, the way
  # a host's type list extends the library's defaults.
  defmodule Checklist do
    use FormFlow.Config.Flows.Type

    @impl true
    def editable?(_context, _callback_data), do: true
  end

  defp form(name, status), do: %FormProgress{path: [name], label: name, status: status}

  defp context(forms, current \\ nil) do
    %Context{
      flow_progress: forms,
      form_progress: current && Enum.find(forms, &(&1.path == [current]))
    }
  end

  describe "a custom type" do
    test "overrides one callback and inherits the rest" do
      forms = [form("one", :completed), form("two", :pending)]

      assert Checklist.editable?(context(forms, "two"), %{})
      refute Types.WizardInOrder.editable?(context(forms, "two"), %{})

      assert is_nil(Checklist.handle_complete(context(forms, "one"), %{}))
      assert is_nil(Checklist.progress_component(%{forms: [form("one", :available)]}))
    end
  end

  # A host's type that shows every flow to every viewer, whatever the flow's
  # perspectives say — the property states, the type decides
  defmodule Open do
    use FormFlow.Config.Flows.Type

    @impl true
    def visible?(_context, _callback_data), do: true
  end

  describe "visible?/2" do
    defp reviewer_flow do
      %FormFlow.Data.Templates.Flow{label: "forms", properties: %{"perspectives" => ["reviewer"]}}
    end

    test "the default reads the flow's perspectives against the viewer's" do
      context = %Context{subflow: reviewer_flow(), perspectives: ["reviewer"]}
      assert Types.WizardInOrder.visible?(context, %{})
      assert Types.WizardAnyOrder.visible?(context, %{})

      other = %Context{subflow: reviewer_flow(), perspectives: ["applicant"]}
      refute Types.WizardInOrder.visible?(other, %{})
      refute Checklist.visible?(other, %{})
    end

    test "a flow for everyone is visible to anyone; a viewer with no perspective sees it alone" do
      everyone = %FormFlow.Data.Templates.Flow{label: "forms", properties: %{}}
      assert Types.WizardInOrder.visible?(%Context{subflow: everyone, perspectives: ["x"]}, %{})

      assert Types.WizardInOrder.visible?(%Context{subflow: everyone, perspectives: []}, %{})

      refute Types.WizardInOrder.visible?(
               %Context{subflow: reviewer_flow(), perspectives: []},
               %{}
             )
    end

    test "a type overrides it like any other callback, and editable? is unaffected" do
      other = %Context{subflow: reviewer_flow(), perspectives: ["applicant"]}
      assert Open.visible?(other, %{})

      forms = [form("next", :available)]
      assert Open.editable?(context(forms, "next"), %{})
      assert Types.WizardInOrder.editable?(context(forms, "next"), %{})
    end
  end

  describe "Types.Default / WizardInOrder" do
    test "editable? is where the flow allows work: an available or started form" do
      forms = [
        form("done", :completed),
        form("started", :in_progress),
        form("next", :available),
        form("later", :pending)
      ]

      assert Types.WizardInOrder.editable?(context(forms, "started"), %{})
      assert Types.WizardInOrder.editable?(context(forms, "next"), %{})
      refute Types.WizardInOrder.editable?(context(forms, "later"), %{})
      refute Types.WizardInOrder.editable?(context(forms, "done"), %{})
    end

    test "handle_complete moves to the first form the flow allows work on" do
      forms = [form("one", :completed), form("two", :available), form("three", :pending)]
      assert Types.WizardInOrder.handle_complete(context(forms, "one"), %{}).label == "two"

      # A form still open earlier in the flow wins over pressing forward
      forms = [form("one", :in_progress), form("two", :completed), form("three", :available)]
      assert Types.WizardInOrder.handle_complete(context(forms, "two"), %{}).label == "one"
    end

    test "handle_complete hands back to the flow instance when nothing is actionable" do
      assert is_nil(
               Types.WizardInOrder.handle_complete(context([form("one", :completed)], "one"), %{})
             )

      assert is_nil(
               Types.WizardInOrder.handle_complete(context([form("one", :pending)], "one"), %{})
             )

      assert is_nil(Types.WizardInOrder.handle_complete(context([]), %{}))
    end

    test "progress_component draws nothing for a lone form" do
      assert is_nil(Types.WizardInOrder.progress_component(%{forms: [form("one", :available)]}))

      assert is_nil(Types.WizardInOrder.progress_component(%{forms: []}))
    end
  end

  describe "WizardAnyOrder" do
    test "editable? is every form that isn't done" do
      forms = [
        form("done", :completed),
        form("started", :in_progress),
        form("next", :available),
        form("later", :pending)
      ]

      assert Types.WizardAnyOrder.editable?(context(forms, "next"), %{})
      assert Types.WizardAnyOrder.editable?(context(forms, "later"), %{})
      assert Types.WizardAnyOrder.editable?(context(forms, "started"), %{})
      refute Types.WizardAnyOrder.editable?(context(forms, "done"), %{})
    end

    test "handle_complete moves to the next open form, skipping done ones" do
      forms = [form("one", :completed), form("two", :pending), form("three", :pending)]
      assert Types.WizardAnyOrder.handle_complete(context(forms, "one"), %{}).label == "two"

      forms = [form("one", :completed), form("two", :completed), form("three", :pending)]
      assert Types.WizardAnyOrder.handle_complete(context(forms, "one"), %{}).label == "three"
    end

    test "handle_complete wraps around to a form skipped earlier" do
      forms = [form("one", :pending), form("two", :completed), form("three", :completed)]
      assert Types.WizardAnyOrder.handle_complete(context(forms, "three"), %{}).label == "one"
      assert Types.WizardAnyOrder.handle_complete(context(forms, "two"), %{}).label == "one"
    end

    test "handle_complete hands back to the flow instance when every form is done" do
      forms = [form("one", :completed), form("two", :completed)]
      assert is_nil(Types.WizardAnyOrder.handle_complete(context(forms, "two"), %{}))
      assert is_nil(Types.WizardAnyOrder.handle_complete(context([]), %{}))
    end

    test "handle_complete from a position the flow no longer has starts from the top" do
      forms = [form("one", :completed), form("two", :pending)]
      assert Types.WizardAnyOrder.handle_complete(context(forms, "gone"), %{}).label == "two"
    end
  end

  describe "defaults/0 and for_kind/2" do
    test "four built-ins, each kind's fallback first" do
      assert [
               %Type{id: "wizard_in_order", kind: :forms, module: Types.WizardInOrder},
               %Type{id: "wizard_any_order", kind: :forms, module: Types.WizardAnyOrder},
               %Type{id: "in_order", kind: :subflows, module: Types.InOrder},
               %Type{id: "any_order", kind: :subflows, module: Types.AnyOrder}
             ] = Type.defaults()
    end

    test "for_kind/2 is the types for a flow of a label, in order; none for any other" do
      assert Enum.map(Type.for_kind(Type.defaults(), "forms"), & &1.id) ==
               ["wizard_in_order", "wizard_any_order"]

      assert Enum.map(Type.for_kind(Type.defaults(), "subflows"), & &1.id) ==
               ["in_order", "any_order"]

      assert Type.for_kind(Type.defaults(), "other") == []
      assert Type.for_kind(Type.defaults(), nil) == []
    end

    test "kind defaults to :forms" do
      assert %Type{kind: :forms} = %Type{id: "mine", module: Checklist, name: "Mine"}
    end
  end

  # The step-level questions, asked of a "subflows" flow's type
  defp step(name, status), do: %SubflowProgress{path: [name], label: name, status: status}

  defp step_context(steps, current \\ nil) do
    %Context{
      complex_progress: steps,
      subflow_progress: current && Enum.find(steps, &(&1.label == current))
    }
  end

  describe "InOrder, the :subflows default" do
    test "a step can be entered when the steps before it are done - its status says so" do
      steps = [step("done", :completed), step("next", :available), step("later", :pending)]

      refute Types.InOrder.enterable?(step_context(steps, "done"), %{})
      assert Types.InOrder.enterable?(step_context(steps, "next"), %{})
      refute Types.InOrder.enterable?(step_context(steps, "later"), %{})

      assert Types.InOrder.enterable?(step_context([step("open", :in_progress)], "open"), %{})
      refute Types.InOrder.enterable?(%Context{subflow_progress: nil}, %{})
    end

    test "handle_complete moves to the first step the flow allows work in" do
      steps = [step("one", :completed), step("two", :available), step("three", :pending)]
      assert Types.InOrder.handle_complete(step_context(steps, "one"), %{}).label == "two"

      # A step still open earlier wins over pressing forward
      steps = [step("one", :in_progress), step("two", :completed), step("three", :available)]
      assert Types.InOrder.handle_complete(step_context(steps, "two"), %{}).label == "one"

      assert is_nil(
               Types.InOrder.handle_complete(step_context([step("one", :completed)], "one"), %{})
             )
    end

    test "Type.Default answers the step question when the context carries steps" do
      steps = [step("later", :pending)]
      refute Type.Default.enterable?(step_context(steps, "later"), %{})
      assert is_nil(Type.Default.handle_complete(step_context(steps, "later"), %{}))

      # and the form question otherwise - a context with neither answers nil
      assert is_nil(Type.Default.handle_complete(%Context{}, %{}))
      refute Type.Default.enterable?(%Context{}, %{})
    end

    test "a :forms type inherits enterable? too, so any type can be asked" do
      assert Checklist.enterable?(step_context([step("next", :available)], "next"), %{})
    end
  end

  describe "AnyOrder" do
    test "any unfinished step can be entered" do
      steps = [step("done", :completed), step("next", :available), step("later", :pending)]

      refute Types.AnyOrder.enterable?(step_context(steps, "done"), %{})
      assert Types.AnyOrder.enterable?(step_context(steps, "next"), %{})
      assert Types.AnyOrder.enterable?(step_context(steps, "later"), %{})
      refute Types.AnyOrder.enterable?(%Context{subflow_progress: nil}, %{})
    end

    test "handle_complete moves to the next unfinished step after the current one, wrapping" do
      steps = [step("one", :pending), step("two", :completed), step("three", :pending)]
      assert Types.AnyOrder.handle_complete(step_context(steps, "two"), %{}).label == "three"

      steps = [step("one", :pending), step("two", :completed), step("three", :completed)]
      assert Types.AnyOrder.handle_complete(step_context(steps, "three"), %{}).label == "one"

      steps = [step("one", :completed), step("two", :completed)]
      assert is_nil(Types.AnyOrder.handle_complete(step_context(steps, "two"), %{}))

      # No current step: the first unfinished
      steps = [step("one", :completed), step("two", :pending)]
      assert Types.AnyOrder.handle_complete(step_context(steps), %{}).label == "two"
    end
  end

  describe "FormFlow.Config.Flows.Type.property_values/1" do
    test "reads what an admin entered for the flow's type, under the type's own key" do
      flow = %FormFlow.Data.Templates.Flow{
        properties: %{
          "flow_type" => "typed",
          "flow_type_property_values" => %{"limit" => "3"}
        }
      }

      assert FormFlow.Config.Flows.Type.property_values(flow) == %{"limit" => "3"}
      assert FormFlow.Config.Flows.Type.property_values(%FormFlow.Data.Templates.Flow{}) == %{}
      assert FormFlow.Config.Flows.Type.property_values(nil) == %{}
    end
  end
end
