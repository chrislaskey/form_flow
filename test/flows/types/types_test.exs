defmodule FormFlow.Flows.TypesTest do
  use ExUnit.Case, async: true

  alias FormFlow.Context
  alias FormFlow.Data.Instances.FormProgress
  alias FormFlow.Data.Templates.Flow
  alias FormFlow.Flows.Types

  # A host's own type: overrides one callback and inherits the rest, the way
  # a custom config module extends FormFlow.Config.
  defmodule Checklist do
    use FormFlow.Flows.Types

    @impl true
    def openable?(_form, _forms), do: true
  end

  # A host's config, pointing its own type string at the module above.
  defmodule Config do
    use FormFlow.Config

    @impl true
    def form_flow_type_module("demo_checklist", _context, _config_data) do
      FormFlow.Flows.TypesTest.Checklist
    end

    def form_flow_type_module(value, context, config_data) do
      FormFlow.Config.form_flow_type_module(value, context, config_data)
    end
  end

  defp flow(type) do
    properties = if type, do: %{"form_flow_type" => type}, else: %{}

    %Flow{id: Ecto.UUID.generate(), label: "forms", properties: properties}
  end

  describe "for_flow/4" do
    test "a flow's stored form_flow_type picks its module" do
      context = %Context{}

      assert Types.for_flow(flow("wizard_in_order"), context, nil, %{}) ==
               Types.WizardInOrder

      assert Types.for_flow(flow("wizard_any_order"), context, nil, %{}) ==
               Types.WizardAnyOrder
    end

    test "unset, unrecognized, and flow-less all fall back to the in-order baseline" do
      context = %Context{}

      assert Types.for_flow(flow(nil), context, nil, %{}) == Types.WizardInOrder
      assert Types.for_flow(flow("nonsense"), context, nil, %{}) == Types.WizardInOrder
      assert Types.for_flow(nil, context, nil, %{}) == Types.WizardInOrder
    end

    test "a host's config module answers instead, defaults included" do
      context = %Context{}

      assert Types.for_flow(flow("demo_checklist"), context, Config, %{}) == Checklist

      assert Types.for_flow(flow("wizard_any_order"), context, Config, %{}) ==
               Types.WizardAnyOrder
    end
  end

  describe "a custom type" do
    test "keeps the callbacks it doesn't override" do
      forms = [
        %FormProgress{path: ["one"], status: :completed},
        pending = %FormProgress{path: ["two"], status: :pending}
      ]

      assert Checklist.openable?(pending, forms)
      refute Types.WizardInOrder.openable?(pending, forms)

      assert Checklist.show_progress?(forms)
      assert is_nil(Checklist.next_form(forms, ["one"]))
    end
  end
end
