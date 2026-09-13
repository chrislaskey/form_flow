defmodule FormFlow.Config.AI do
  @moduledoc """
  How a page reaches a language model: the module that makes the call, and
  the model, key, and timeout it makes it with.

  A host passes one of these as the `build_with_ai` attr of
  `FormFlow.Web.router/1` and `FormFlow.Web.Templates.Forms.Edit`. The struct
  is deliberately generic and the **attr is not**: a later AI-backed feature
  gets its own attr holding one of these, named for whatever the screen calls
  it, rather than widening `build_with_ai` into a general `ai` attr and
  breaking that name's tie to the card an admin reads. The struct is the
  configuration, and its `:module` — `use`ing this behaviour — is what talks
  to the provider. `FormFlow.Config.AI.OpenRouter` is the one the library
  ships, and the default; a host with its own gateway, a provider's own API,
  or a stub for tests names its own.

  Nothing here is specific to building a form. The same struct is what a
  later instance-side feature would take, which is why the callback speaks
  in prompts and text rather than in definitions — what to ask for and what
  to do with the answer belong to the page asking.

      # config/runtime.exs — the host's own settings, read by the host
      config :my_app, :build_with_ai,
        api_key: System.get_env("OPENROUTER_API_KEY")

      # the host's function, passed to the router
      def build_with_ai do
        %FormFlow.Config.AI{
          api_key: Application.get_env(:my_app, :build_with_ai)[:api_key]
        }
      end

  ## Fields

    * `:module` - the module making the call, `use FormFlow.Config.AI`.
      Defaults to `FormFlow.Config.AI.OpenRouter`
    * `:available_models` - the models an admin may pick from, each a model
      id as the provider spells it or a `{label, id}` pair. Defaults to the
      one the library recommends, `qwen/qwen3.8-flash`. More than one draws a
      select beside the prompt; one draws none
    * `:default_model` - the one selected before anybody picks, or `nil` for
      the first of `:available_models`
    * `:api_key` - the credential, or `nil` to let the module find its own
      (the shipped one falls back to `OPENROUTER_API_KEY`)
    * `:timeout` - milliseconds the **shipped client** waits for the answer,
      default `120_000`. A form is a big answer and these calls take tens of
      seconds. A host's own module decides its own waiting; nothing in
      FormFlow bounds it, and a module that never returns leaves the page
      saying "Building…"
  """

  # The struct holds a credential and lives in a LiveView's assigns, so a
  # crash report, a telemetry handler, or a stray `dbg` would otherwise print
  # the key
  @derive {Inspect, except: [:api_key]}

  # The default model, chosen from OpenRouter's catalogue on the day this was
  # written and worth re-checking: writing a definition is following a list
  # of rules and emitting a couple of thousand tokens of JSON, which a cheap
  # current model does well and a frontier model does no better for roughly
  # twenty-five times the price. A host that disagrees names its own; that is
  # what the list is for.
  defstruct module: FormFlow.Config.AI.OpenRouter,
            available_models: ["qwen/qwen3.8-flash"],
            default_model: nil,
            api_key: nil,
            timeout: 120_000

  @type model :: String.t() | {String.t(), String.t()}

  @type t :: %__MODULE__{
          module: module(),
          available_models: [model()],
          default_model: String.t() | nil,
          api_key: String.t() | nil,
          timeout: pos_integer()
        }

  @doc """
  The models as `{label, id}` options, for a select. A bare id is its own
  label, the way `FormFlow.Config.Property` takes `{label, value}` pairs and
  the pages render them.
  """
  @spec model_options(t()) :: [{String.t(), String.t()}]
  def model_options(%__MODULE__{available_models: models}) do
    Enum.map(models, fn
      {label, id} -> {label, id}
      id -> {id, id}
    end)
  end

  @doc """
  The model a build uses when nobody picked one: `:default_model`, or the
  first offered. `nil` only when a host passed an empty list, which is a
  configuration with nothing to run.
  """
  @spec default_model(t()) :: String.t() | nil
  def default_model(%__MODULE__{default_model: nil} = config) do
    case model_options(config) do
      [{_label, id} | _rest] -> id
      [] -> nil
    end
  end

  def default_model(%__MODULE__{default_model: model}), do: model

  @doc """
  Submit one request and return what the model said.

  `request` is a `FormFlow.Config.AI.Request`: a `:system` instruction, the
  `:prompt` itself, the `:model` the admin picked, and a `:max_tokens`
  ceiling. `config` is the struct the host passed, so the module reads its
  `:api_key` and `:timeout` from it rather than from anywhere else — and the
  models it may be asked for are the ones that config offered.

  Returns `{:ok, text}` with the model's answer as it came back — no
  parsing, no trimming of code fences; the caller decides what the text
  means. `{:error, message}` is a sentence to show an admin: a failed
  request, a refusal, an answer cut off by the token ceiling. It is shown on
  the page, so it says what happened without a stack trace and without the
  key.
  """
  @callback submit(FormFlow.Config.AI.Request.t(), t()) ::
              {:ok, String.t()} | {:error, String.t()}

  defmacro __using__(_opts) do
    quote do
      @behaviour FormFlow.Config.AI
    end
  end
end
