defmodule FormFlow.Data.Clients.AI.OpenRouter do
  @moduledoc """
  The OpenRouter client behind `FormFlow.Config.AI.OpenRouter`: one POST to
  the chat-completions endpoint, the answer's text back.

  Reached through the `FormFlow.Config` name, never named by a host directly.
  It reads the key from the `FormFlow.Config.AI` struct it is handed, or from
  `OPENROUTER_API_KEY` when that struct has none, and nothing else from the
  environment.

  One request, no streaming, no retry: an admin pressing Build waits once and
  reads an error if it fails. A host that wants retries, a proxy, a spend cap,
  or a provider's own API writes its own module - that is what
  `FormFlow.Config.AI`'s behaviour is for.
  """

  require Logger

  alias FormFlow.Config.AI
  alias FormFlow.Config.AI.Request

  @endpoint "https://openrouter.ai/api/v1/chat/completions"

  # Sent so a host's usage shows up as this library rather than as an
  # unnamed key. Neither header is required, and neither identifies the host.
  @referer "https://github.com/chrislaskey/form_flow"
  @title "FormFlow"

  @doc """
  Send one request and return the answer's text, or a sentence an admin can
  read.
  """
  def submit(%Request{} = request, %AI{} = config) do
    case api_key(config) do
      nil ->
        {:error, "No API key is configured for Build with AI."}

      key ->
        @endpoint
        |> Req.post(
          headers: [
            {"authorization", "Bearer #{key}"},
            {"http-referer", @referer},
            {"x-openrouter-title", @title}
          ],
          json: body(request, config),
          receive_timeout: config.timeout
        )
        |> handle_response()
    end
  end

  @doc """
  The request body: the OpenAI chat-completions shape, which is what
  OpenRouter takes and what a host's own gateway most likely takes too. The
  system instruction is its own message rather than a top-level field, which
  is the one place this differs from Anthropic's API.

  No `temperature`, no `response_format`, no provider routing preferences -
  each is a parameter some model behind OpenRouter rejects, and none of them
  buys anything here.
  """
  def body(%Request{} = request, %AI{} = config) do
    %{
      model: request.model || AI.default_model(config),
      max_tokens: request.max_tokens,
      messages: messages(request)
    }
  end

  @doc """
  What `Req.post/2` came back with, as the answer's text or a sentence.

  An error can arrive as a 200 with an `error` object as easily as with a
  status, because OpenRouter is relaying somebody else's failure - so the
  body is read before the status is trusted. `finish_reason` is read next:
  "length" means the answer is cut off mid-JSON and would otherwise fail to
  decode with a message that blamed the wrong thing.
  """
  def handle_response({:ok, %{body: %{"error" => error}}}),
    do: {:error, "The request failed. #{error_message(error)}"}

  def handle_response({:ok, %{status: 200, body: %{"choices" => [choice | _rest]}}}) do
    case choice do
      %{"finish_reason" => "length"} ->
        {:error, "The answer was too long to finish. Ask for a smaller change."}

      %{"finish_reason" => "content_filter"} ->
        {:error, "The model declined to answer that prompt. Try describing the form differently."}

      %{"message" => %{"content" => content}} when is_binary(content) ->
        {:ok, content}

      _other ->
        {:error, "The model returned no answer. Please try again."}
    end
  end

  # A 200 with a body in no shape this understands is still the model failing
  # to answer; "the request failed (200)" would blame the wrong thing
  def handle_response({:ok, %{status: 200}}),
    do: {:error, "The model returned no answer. Please try again."}

  def handle_response({:ok, %{status: status}}),
    do: {:error, "The request failed (#{status}). Please try again."}

  # The one failure a host, rather than an admin, has to debug: a bad key, a
  # blocked egress, a DNS failure. The admin gets the sentence; the log gets
  # the exception (`FormFlow.Web.Instances.Forms.Edit` logs the same way).
  def handle_response({:error, exception}) do
    Logger.warning("FormFlow Build with AI request failed: #{Exception.message(exception)}")
    {:error, "Could not reach the model: #{Exception.message(exception)}"}
  end

  defp api_key(%AI{api_key: nil}), do: System.get_env("OPENROUTER_API_KEY")
  defp api_key(%AI{api_key: key}), do: key

  defp messages(%Request{system: nil, prompt: prompt}),
    do: [%{role: "user", content: prompt}]

  defp messages(%Request{system: system, prompt: prompt}),
    do: [%{role: "system", content: system}, %{role: "user", content: prompt}]

  defp error_message(%{"message" => message}) when is_binary(message), do: message
  defp error_message(_error), do: "Please try again."
end
