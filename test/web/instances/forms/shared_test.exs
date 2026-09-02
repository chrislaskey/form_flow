defmodule FormFlow.Web.Instances.Forms.SharedTest do
  use ExUnit.Case, async: true

  alias FormFlow.Context
  alias FormFlow.Data.Templates.Flow
  alias FormFlow.Web.Components.Flows.Types
  alias FormFlow.Web.Instances.Forms.Shared

  # The assigns a page without a host config carries
  @defaults %{config: nil, config_data: %{}}

  defmodule Checklist do
    use FormFlow.Config.Flows.Type
  end

  defmodule Prefill do
    use FormFlow.Config.Forms.Type
  end

  # A host's config, offering its own type beside the defaults.
  defmodule Config do
    use FormFlow.Config

    @impl true
    def enabled_flow_types(context, config_data) do
      FormFlow.Config.Default.enabled_flow_types(context, config_data) ++
        [%FormFlow.Config.Flows.Type{id: "demo_checklist", module: Checklist, name: "Checklist"}]
    end

    @impl true
    def enabled_form_types(_context, _config_data) do
      [%FormFlow.Config.Forms.Type{id: "demo_prefill", module: Prefill, name: "Prefill"}]
    end
  end

  defp flow(type) do
    properties = if type, do: %{"form_flow_type" => type}, else: %{}

    %Flow{id: Ecto.UUID.generate(), label: "forms", properties: properties}
  end

  describe "flow_type/2" do
    test "a flow's stored form_flow_type picks its type" do
      assert %{module: Types.WizardInOrder} =
               Shared.flow_type(%Context{subflow: flow("wizard_in_order")}, @defaults)

      assert %{module: Types.WizardAnyOrder} =
               Shared.flow_type(%Context{subflow: flow("wizard_any_order")}, @defaults)
    end

    test "unset, unknown, and no flow all resolve to the first enabled type" do
      for subflow <- [flow(nil), flow("nonsense")] do
        assert %{id: "wizard_in_order"} =
                 Shared.flow_type(%Context{subflow: subflow}, @defaults)
      end
    end

    test "a context with no enabled types falls back to the library's defaults" do
      subflows = %Flow{id: Ecto.UUID.generate(), label: "subflows"}

      assert %{id: nil, module: FormFlow.Config.Flows.Type.Default} =
               Shared.flow_type(%Context{subflow: subflows}, @defaults)
    end

    test "a host's config resolves its own type and still the defaults" do
      host = %{config: Config, config_data: %{}}

      assert %{module: Checklist} =
               Shared.flow_type(%Context{subflow: flow("demo_checklist")}, host)

      assert %{module: Types.WizardAnyOrder} =
               Shared.flow_type(%Context{subflow: flow("wizard_any_order")}, host)
    end
  end

  describe "form_type/2" do
    defp form(type) do
      properties = if type, do: %{"form_type" => type}, else: %{}

      %FormFlow.Data.Templates.Form{
        id: Ecto.UUID.generate(),
        name: "Name",
        properties: properties
      }
    end

    test "the library's own types: review by its id, the default for everything else" do
      assert %{id: "review", module: FormFlow.Web.Components.Forms.Types.Review} =
               Shared.form_type(%Context{form: form("review")}, @defaults)

      assert %{id: "default", module: FormFlow.Config.Forms.Type.Default} =
               Shared.form_type(%Context{form: form("anything")}, @defaults)

      assert %{id: "default", module: FormFlow.Config.Forms.Type.Default} =
               Shared.form_type(%Context{form: nil}, @defaults)
    end

    test "a host's config resolves its own type; unset or unknown falls back to its first" do
      host = %{config: Config, config_data: %{}}

      assert %{module: Prefill} = Shared.form_type(%Context{form: form("demo_prefill")}, host)
      assert %{module: Prefill} = Shared.form_type(%Context{form: form(nil)}, host)
      assert %{module: Prefill} = Shared.form_type(%Context{form: form("nonsense")}, host)
    end
  end
end
