defmodule FormFlow.ConfigTest do
  use ExUnit.Case, async: true

  alias FormFlow.Context
  alias FormFlow.Web.Instances.Forms.Shared

  # A host's config that gates its pages: refuses one flow instance by its
  # user, decorates the rest, and inherits the type lists.
  defmodule Gated do
    use FormFlow.Config

    @impl true
    def handle_mount(%Context{user_id: "stranger"}, _config_data),
      do: {:error, "This flow is not yours."}

    def handle_mount(%Context{}, %{greeting: greeting}), do: {:ok, %{greeting: greeting}}
    def handle_mount(%Context{}, _config_data), do: {:ok, %{}}
  end

  defmodule Broken do
    use FormFlow.Config

    @impl true
    def handle_mount(_context, _config_data), do: :whatever
  end

  defp socket(config, user_id \\ "stranger", config_data \\ %{}) do
    %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        context: %Context{user_id: user_id},
        config: config,
        config_data: config_data
      }
    }
  end

  describe "flow_instances_query/2" do
    test "the default narrows the listing to the current user's own" do
      query = FormFlow.Config.Default.flow_instances_query(%Context{user_id: "u-1"}, %{})

      assert %Ecto.Query{} = query
      assert inspect(query) =~ ~s(user_id == ^"u-1")
    end

    test "a custom config inherits it like every other default" do
      assert inspect(Gated.flow_instances_query(%Context{user_id: "u-1"}, %{})) =~
               ~s(user_id == ^"u-1")
    end
  end

  describe "handle_mount/2" do
    test "the default allows every page, adding nothing" do
      assert FormFlow.Config.Default.handle_mount(%Context{}, %{}) == {:ok, %{}}
    end

    test "a custom config inherits the type lists and overrides only what it changes" do
      assert Gated.enabled_form_types(%Context{}, %{}) ==
               FormFlow.Config.Default.enabled_form_types(%Context{}, %{})

      assert Gated.handle_mount(%Context{user_id: "stranger"}, %{}) ==
               {:error, "This flow is not yours."}

      assert Gated.handle_mount(%Context{user_id: "owner"}, %{greeting: "hi"}) ==
               {:ok, %{greeting: "hi"}}
    end
  end

  describe "Shared.handle_mount/2 applies a config's answer to the page" do
    test "a refusal lands in :mount_error and skips the continuation" do
      socket = Shared.handle_mount(socket(Gated), fn _socket -> flunk("started anyway") end)

      assert socket.assigns.mount_error == "This flow is not yours."
    end

    test "an allowance runs the continuation first, then merges the assigns" do
      socket =
        Shared.handle_mount(
          socket(Gated, "owner", %{greeting: "hi"}),
          &Phoenix.Component.assign(&1, :started?, true)
        )

      assert socket.assigns.started? == true
      assert socket.assigns.greeting == "hi"
      refute Map.has_key?(socket.assigns, :mount_error)
    end

    test "no config means the library's default, which allows" do
      socket = Shared.handle_mount(socket(nil), &Phoenix.Component.assign(&1, :started?, true))

      assert socket.assigns.started? == true
    end

    test "a malformed answer fails closed, naming the module" do
      assert_raise ArgumentError, ~r/Broken.handle_mount\/2 returned :whatever/, fn ->
        Shared.handle_mount(socket(Broken))
      end
    end
  end
end
