defmodule DemoWeb.FormFlowLive.AI do
  @moduledoc """
  What the demo passes as `build_with_ai` — a `FormFlow.Config.AI` built from
  the environment, or `nil` when there is no key, which is the state the
  panel explains rather than hides.

  Application env first, `System.get_env/1` behind it, so a test can put a
  stub module in front of the real thing — the demo is where the wiring is
  exercised, and a test that pressed Build without one would reach
  OpenRouter.

  Three models across three vendors when a key is there, because that is the
  point of OpenRouter: a host adds a model to the list and nothing else
  changes. Two cheap ones and one that costs fifty times as much, so the
  select is a real choice and not decoration.
  """

  def config, do: Application.get_env(:demo, :build_with_ai) || from_env()

  defp from_env do
    case System.get_env("OPENROUTER_API_KEY") do
      nil ->
        nil

      key ->
        %FormFlow.Config.AI{
          api_key: key,
          available_models: [
            {"Qwen3.8 Flash — the default", "qwen/qwen3.8-flash"},
            {"DeepSeek V4 Flash — the cheap one", "deepseek/deepseek-v4-flash"},
            {"Claude Sonnet 5 — the expensive one", "anthropic/claude-sonnet-5"}
          ]
        }
    end
  end
end
