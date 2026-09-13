defmodule FormFlow.Config.AITest do
  use ExUnit.Case, async: true

  alias FormFlow.Config.AI

  describe "defaults" do
    test "a struct with nothing set names the shipped module and one model" do
      config = %AI{}

      assert config.module == AI.OpenRouter
      assert config.available_models == ["qwen/qwen3.8-flash"]
      assert config.default_model == nil
      assert config.api_key == nil
      assert config.timeout == 120_000
    end

    test "the key is a value the host passes, and the only thing a struct needs" do
      assert %AI{api_key: "sk-test"}.module == AI.OpenRouter
    end
  end

  describe "model_options/1" do
    test "a bare id is its own label" do
      config = %AI{available_models: ["anthropic/claude-opus-5", "openai/gpt-5"]}

      assert AI.model_options(config) == [
               {"anthropic/claude-opus-5", "anthropic/claude-opus-5"},
               {"openai/gpt-5", "openai/gpt-5"}
             ]
    end

    test "a {label, id} pair keeps its label" do
      config = %AI{available_models: [{"The careful one", "anthropic/claude-opus-5"}]}

      assert AI.model_options(config) == [{"The careful one", "anthropic/claude-opus-5"}]
    end

    test "labelled and bare models mix" do
      config = %AI{
        available_models: [{"The careful one", "anthropic/claude-opus-5"}, "openai/gpt-5"]
      }

      assert AI.model_options(config) == [
               {"The careful one", "anthropic/claude-opus-5"},
               {"openai/gpt-5", "openai/gpt-5"}
             ]
    end
  end

  describe "default_model/1" do
    test "is the one set" do
      config = %AI{
        available_models: ["anthropic/claude-opus-5", "openai/gpt-5"],
        default_model: "openai/gpt-5"
      }

      assert AI.default_model(config) == "openai/gpt-5"
    end

    test "is the first offered when none is set" do
      config = %AI{
        available_models: [{"The careful one", "anthropic/claude-opus-5"}, "openai/gpt-5"]
      }

      assert AI.default_model(config) == "anthropic/claude-opus-5"
    end

    test "is nil when there are no models to offer" do
      assert AI.default_model(%AI{available_models: []}) == nil
    end
  end

  describe "inspect/1" do
    test "does not print the key" do
      inspected = inspect(%AI{api_key: "sk-secret-key"})

      refute inspected =~ "sk-secret-key"
      assert inspected =~ "FormFlow.Config.AI"
    end
  end
end
