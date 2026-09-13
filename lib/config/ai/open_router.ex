defmodule FormFlow.Config.AI.OpenRouter do
  @moduledoc """
  The `FormFlow.Config.AI` module the library ships, and the default: one
  POST to OpenRouter's chat-completions endpoint, the answer's text back.

      %FormFlow.Config.AI{api_key: System.get_env("OPENROUTER_API_KEY")}

  OpenRouter is one account in front of every provider's models, which is
  what makes `:available_models` a list a host can add to without touching
  code — the ids are its slugs, `"qwen/qwen3.8-flash"`,
  `"deepseek/deepseek-v4-flash"`, `"anthropic/claude-sonnet-5"`.

  Delegates to the private internal implementation in
  `FormFlow.Data.Clients.AI.OpenRouter`
  """

  @behaviour FormFlow.Config.AI

  alias FormFlow.Data.Clients

  defdelegate submit(request, config), to: Clients.AI.OpenRouter
end
