defmodule FormFlow.Config.Forms.TypesTest do
  use ExUnit.Case, async: true

  alias FormFlow.Config.Forms.Type
  alias FormFlow.Context
  alias FormFlow.Data.Instances

  # A host's own type: prefills around the stored answers by reaching the
  # defaults from its override, the way a custom config module extends
  # FormFlow.Config.
  defmodule Prefill do
    use FormFlow.Config.Forms.Type

    @impl true
    def initial_data(context, config_data) do
      Map.merge(
        %{"name" => "Prefilled", "email" => "p@example.com"},
        Type.Default.initial_data(context, config_data)
      )
    end
  end

  defp context(data) do
    %Context{form_instance: data && %Instances.Form{data: data}}
  end

  describe "Type.Default.initial_data/2" do
    test "renders the user's stored answers" do
      assert Type.Default.initial_data(context(%{"name" => "Grace"}), %{}) == %{
               "name" => "Grace"
             }
    end

    test "renders nothing for a form with no instance yet" do
      assert Type.Default.initial_data(context(nil), %{}) == %{}
    end
  end

  describe "a custom type" do
    test "prefills what the user hasn't answered and keeps what they have" do
      assert Prefill.initial_data(context(%{"name" => "Grace"}), %{}) ==
               %{"name" => "Grace", "email" => "p@example.com"}

      assert Prefill.initial_data(context(%{}), %{}) ==
               %{"name" => "Prefilled", "email" => "p@example.com"}
    end
  end
end
