defmodule FormFlow.Config.Flows.TypesTest do
  use ExUnit.Case, async: true

  alias FormFlow.Context
  alias FormFlow.Data.Instances.FormProgress
  alias FormFlow.Web.Components.Flows.Types

  # A host's own type: overrides one callback and inherits the rest, the way
  # a custom config module extends FormFlow.Config.
  defmodule Checklist do
    use FormFlow.Config.Flows.Type

    @impl true
    def editable?(_context, _config_data), do: true
  end

  # A host's config, offering its own type beside the defaults.
  defmodule Config do
    use FormFlow.Config

    @impl true
    def enabled_flow_types(context, config_data) do
      FormFlow.Config.Default.enabled_flow_types(context, config_data) ++
        [%FormFlow.Config.Flows.Type{id: "demo_checklist", module: Checklist, name: "Checklist"}]
    end
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

  describe "FormFlow.Config.Flows.Type.property_values/1" do
    test "reads what an admin entered for the flow's type, under the type's own key" do
      flow = %FormFlow.Data.Templates.Flow{
        properties: %{
          "form_flow_type" => "typed",
          "form_flow_type_property_values" => %{"limit" => "3"}
        }
      }

      assert FormFlow.Config.Flows.Type.property_values(flow) == %{"limit" => "3"}
      assert FormFlow.Config.Flows.Type.property_values(%FormFlow.Data.Templates.Flow{}) == %{}
      assert FormFlow.Config.Flows.Type.property_values(nil) == %{}
    end
  end
end
