defmodule FormFlow.Data.Clients.AI.OpenRouterTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias FormFlow.Config.AI
  alias FormFlow.Config.AI.Request
  alias FormFlow.Data.Clients.AI.OpenRouter

  describe "body/2" do
    test "names the request's model, its ceiling, and both messages" do
      request = %Request{system: "Write JSON.", prompt: "A dog form.", model: "openai/gpt-5"}

      assert OpenRouter.body(request, %AI{}) == %{
               model: "openai/gpt-5",
               max_tokens: 16_000,
               messages: [
                 %{role: "system", content: "Write JSON."},
                 %{role: "user", content: "A dog form."}
               ]
             }
    end

    test "falls back to the config's default model when the request names none" do
      request = %Request{prompt: "A dog form."}
      config = %AI{available_models: ["openai/gpt-5", "anthropic/claude-opus-5"]}

      assert %{model: "openai/gpt-5"} = OpenRouter.body(request, config)
    end

    test "sends one message when there is no system instruction" do
      request = %Request{prompt: "A dog form."}

      assert %{messages: [%{role: "user", content: "A dog form."}]} =
               OpenRouter.body(request, %AI{})
    end
  end

  describe "handle_response/1" do
    test "returns the answer's text as it came back" do
      response =
        {:ok,
         %{
           status: 200,
           body: %{"choices" => [%{"message" => %{"content" => ~s({"elements": []})}}]}
         }}

      assert OpenRouter.handle_response(response) == {:ok, ~s({"elements": []})}
    end

    test "reads a relayed failure out of a 200's body" do
      response = {:ok, %{status: 200, body: %{"error" => %{"message" => "No credits left."}}}}

      assert OpenRouter.handle_response(response) ==
               {:error, "The request failed. No credits left."}
    end

    test "an error body with no message still says something" do
      response = {:ok, %{status: 200, body: %{"error" => %{"code" => 402}}}}

      assert OpenRouter.handle_response(response) ==
               {:error, "The request failed. Please try again."}
    end

    test "an answer cut off by the ceiling is not a JSON error" do
      response =
        {:ok, %{status: 200, body: %{"choices" => [%{"finish_reason" => "length"}]}}}

      assert OpenRouter.handle_response(response) ==
               {:error, "The answer was too long to finish. Ask for a smaller change."}
    end

    test "a refusal says the model declined" do
      response =
        {:ok, %{status: 200, body: %{"choices" => [%{"finish_reason" => "content_filter"}]}}}

      assert {:error, "The model declined to answer that prompt." <> _rest} =
               OpenRouter.handle_response(response)
    end

    test "a choice with no content is an error rather than an empty answer" do
      response = {:ok, %{status: 200, body: %{"choices" => [%{"message" => %{}}]}}}

      assert OpenRouter.handle_response(response) ==
               {:error, "The model returned no answer. Please try again."}
    end

    test "a failing status names itself" do
      assert OpenRouter.handle_response({:ok, %{status: 429, body: ""}}) ==
               {:error, "The request failed (429). Please try again."}
    end

    test "a 200 carrying nothing this understands blames the answer, not the request" do
      assert OpenRouter.handle_response({:ok, %{status: 200, body: "not JSON at all"}}) ==
               {:error, "The model returned no answer. Please try again."}
    end

    test "a transport failure reaches the admin as a sentence and the host as a log line" do
      exception = %Mint.TransportError{reason: :nxdomain}

      log =
        capture_log(fn ->
          assert {:error, "Could not reach the model: non-existing domain"} =
                   OpenRouter.handle_response({:error, exception})
        end)

      assert log =~ "FormFlow Build with AI request failed: non-existing domain"
    end
  end

  # The only branch of `submit/2` worth a test is the one that never reaches
  # the network: a config with no key, and no `OPENROUTER_API_KEY` behind it
  # either. The developer running this suite may well have one set.
  describe "submit/2 without a key" do
    setup do
      key = System.get_env("OPENROUTER_API_KEY")
      System.delete_env("OPENROUTER_API_KEY")
      on_exit(fn -> key && System.put_env("OPENROUTER_API_KEY", key) end)
    end

    test "says so rather than posting without one" do
      assert OpenRouter.submit(%Request{prompt: "A dog form."}, %AI{}) ==
               {:error, "No API key is configured for Build with AI."}
    end

    test "FormFlow.Config.AI.OpenRouter is the default module, and delegates here" do
      assert %AI{}.module == AI.OpenRouter

      assert AI.OpenRouter.submit(%Request{prompt: "A dog form."}, %AI{}) ==
               {:error, "No API key is configured for Build with AI."}
    end
  end
end
