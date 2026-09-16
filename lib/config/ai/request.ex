defmodule FormFlow.Config.AI.Request do
  @moduledoc """
  One request to a language model, in the terms every provider shares: the
  standing instruction, the thing being asked, and how much answer to allow.

  Built by the page that wants something - `FormFlow.Web.Templates.Forms.Edit`
  builds the one that writes a form definition - and handed to the
  `FormFlow.Config.AI` module the host configured.

  `:model` rides on the request rather than on the config because it is the
  admin's choice at the moment of asking, out of what the config offers
  (`FormFlow.Config.AI.model_options/1`). A page that offers no choice puts
  `FormFlow.Config.AI.default_model/1` here, which is the same value.

  `:max_tokens` is a property of what is being asked for - a form is big, a
  one-line summary is not - which is why it sits here and not on the config,
  which is a property of the host's account. The default is a ceiling a
  non-streaming request can reach without the provider's own HTTP timeout
  arriving first.
  """

  defstruct [:system, :prompt, :model, max_tokens: 16_000]

  @type t :: %__MODULE__{
          system: String.t() | nil,
          prompt: String.t(),
          model: String.t() | nil,
          max_tokens: pos_integer()
        }
end
