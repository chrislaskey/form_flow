defmodule FormFlow.Web.Instances.Forms.SharedTest do
  use ExUnit.Case, async: true

  alias FormFlow.Context
  alias FormFlow.Data.Templates.Flow
  alias FormFlow.Web.Components.Flows.Types
  alias FormFlow.Web.Instances.Forms.Shared

  # The assigns a page passed no type lists carries: the library's defaults
  @defaults %{
    flow_types: FormFlow.Config.Flows.Type.defaults(),
    form_types: FormFlow.Config.Forms.Type.defaults(),
    callback_data: %{}
  }

  defmodule Checklist do
    use FormFlow.Config.Flows.Type
  end

  defmodule Prefill do
    use FormFlow.Config.Forms.Type
  end

  # A host's lists: its own flow type beside the defaults, and only its own
  # form type
  @host %{
    flow_types:
      FormFlow.Config.Flows.Type.defaults() ++
        [%FormFlow.Config.Flows.Type{id: "demo_checklist", module: Checklist, name: "Checklist"}],
    form_types: [
      %FormFlow.Config.Forms.Type{id: "demo_prefill", module: Prefill, name: "Prefill"}
    ],
    callback_data: %{}
  }

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

    test "a \"subflows\" flow has no types, so it falls back to the library's default" do
      subflows = %Flow{id: Ecto.UUID.generate(), label: "subflows"}

      assert %{id: nil, module: FormFlow.Config.Flows.Type.Default} =
               Shared.flow_type(%Context{subflow: subflows}, @defaults)
    end

    test "a host's list resolves its own type and still the defaults" do
      assert %{module: Checklist} =
               Shared.flow_type(%Context{subflow: flow("demo_checklist")}, @host)

      assert %{module: Types.WizardAnyOrder} =
               Shared.flow_type(%Context{subflow: flow("wizard_any_order")}, @host)
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

    test "a host's list resolves its own type; unset or unknown falls back to its first" do
      assert %{module: Prefill} = Shared.form_type(%Context{form: form("demo_prefill")}, @host)
      assert %{module: Prefill} = Shared.form_type(%Context{form: form(nil)}, @host)
      assert %{module: Prefill} = Shared.form_type(%Context{form: form("nonsense")}, @host)
    end
  end

  describe "the library's defaults" do
    test "flow types: the in-order wizard first, then any order, none with perspectives" do
      assert [%{id: "wizard_in_order", perspectives: []}, %{id: "wizard_any_order"}] =
               FormFlow.Config.Flows.Type.defaults()
    end

    test "form types: the default first, then review with its properties" do
      assert [%{id: "default"}, %{id: "review", properties: [_ | _]}] =
               FormFlow.Config.Forms.Type.defaults()
    end
  end

  # A host's gate: refuses one user, decorates the rest with what the page
  # handed it as callback_data
  defp gate(%Context{user_id: "stranger"}, _callback_data),
    do: {:error, "This flow is not yours."}

  defp gate(%Context{}, %{greeting: greeting}), do: {:ok, %{greeting: greeting}}
  defp gate(%Context{}, _callback_data), do: {:ok, %{}}

  defp socket(on_mount, user_id \\ "stranger", callback_data \\ %{}) do
    %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        context: %Context{user_id: user_id},
        on_mount: on_mount,
        callback_data: callback_data
      }
    }
  end

  describe "on_mount/2 applies the host's gate to the page" do
    test "a refusal lands in :mount_error and skips the continuation" do
      socket = Shared.on_mount(socket(&gate/2), fn _socket -> flunk("started anyway") end)

      assert socket.assigns.mount_error == "This flow is not yours."
    end

    test "an allowance runs the continuation first, then merges the assigns" do
      socket =
        Shared.on_mount(
          socket(&gate/2, "owner", %{greeting: "hi"}),
          &Phoenix.Component.assign(&1, :started?, true)
        )

      assert socket.assigns.started? == true
      assert socket.assigns.greeting == "hi"
      refute Map.has_key?(socket.assigns, :mount_error)
    end

    test "no gate allows, running the continuation" do
      socket = Shared.on_mount(socket(nil), &Phoenix.Component.assign(&1, :started?, true))

      assert socket.assigns.started? == true
    end

    test "a malformed answer fails closed" do
      assert_raise ArgumentError, ~r/on_mount returned :whatever/, fn ->
        Shared.on_mount(socket(fn _context, _callback_data -> :whatever end))
      end
    end
  end
end
