defmodule FormFlow.Web.Downloads.Token do
  @moduledoc """
  The short-lived token that authorizes one download.

  A download leaves the LiveView for an ordinary `GET`, and that request
  arrives with none of what the page had: no `callback_data`, no `flows`
  scope, no host `on_mount` to ask. Re-deciding there would mean the host
  handing its gate to a route as well as to a page, and the two answering
  differently the first time one of them changed.

  So the decision is not made twice. The page already ran the gate to
  render; when the user clicks, it mints a token saying *this user may take
  this form away*, and the request carries that instead of an argument.
  `FormFlow.Web.Instances.Forms.Show` will only mint one for a page the gate
  let it draw.

  ## What is in it, and what is not

  Everything the request is: who, what, and which of Download and Print.
  Nothing rides beside it — the endpoint reads the token and ignores the
  rest of the query string, so swapping a `path` param for another form's
  cannot widen what a token was minted for.

  It is encrypted rather than signed, so the ids inside it stay out of
  browser history, referrer headers, and access logs.

  ## What it does not defend against

  Anyone holding the URL can redeem it until it expires — the token is a
  capability, and FormFlow cannot bind it to a session without knowing the
  host's current user, which is the thing tokens exist here to avoid. Two
  things keep that small: the route sits inside the host's own pipeline, so
  an anonymous holder is turned away before FormFlow sees the token, and a
  user who can mint a link can already save the file and send that instead.
  A host wanting more layers its own checks in front of the route, or serves
  downloads from an endpoint of its own (`decode/3` is public for exactly
  that).

  ## Lifetime

  60 seconds, which is a browser round trip and no more:

      config :form_flow, download_token_max_age: 30

  The window that matters is minting to redeeming, not how long the page has
  been open: the token is minted by the click, so a tab left open for days
  prints as readily as a fresh one.
  """

  # A purpose of its own, so that a second kind of FormFlow token — whenever
  # there is one — can never be redeemed as a download
  @salt "form_flow:download:v1"

  @default_max_age 60

  @type payload :: %{
          user_id: String.t() | nil,
          tenant_id: String.t() | nil,
          flow_instance_id: String.t(),
          path: [String.t()],
          disposition: :download | :print
        }

  @doc """
  How long a token stays good for, in seconds.
  """
  @spec max_age() :: pos_integer()
  def max_age, do: Application.get_env(:form_flow, :download_token_max_age, @default_max_age)

  @doc """
  Mints a token for one download.

  `context` is anything `Phoenix.Token` reads a `secret_key_base` from — a
  `Plug.Conn`, a LiveView socket, an endpoint module, or the secret itself.
  """
  @spec encode(term(), payload()) :: String.t()
  def encode(context, %{} = payload) do
    Phoenix.Token.encrypt(context, @salt, payload)
  end

  @doc """
  Reads a token back, or says why it cannot.

  `{:error, :expired}` for one past `max_age/0`, `{:error, :invalid}` for
  one this application did not mint, was minted for another purpose, or that
  has been tampered with.

  Public because a host serving downloads from its own endpoint — see
  `FormFlow.Web.router/1`'s `download_path` attr — still receives FormFlow's
  token and needs to know what it says. `FormFlow.decode_token/3` is the
  stable name for it.
  """
  @spec decode(term(), String.t(), keyword()) :: {:ok, payload()} | {:error, :expired | :invalid}
  def decode(context, token, opts \\ [])

  def decode(context, token, opts) when is_binary(token) do
    age = Keyword.get(opts, :max_age, max_age())

    case Phoenix.Token.decrypt(context, @salt, token, max_age: age) do
      {:ok, %{flow_instance_id: _, path: _, disposition: _} = payload} -> {:ok, payload}
      {:ok, _other} -> {:error, :invalid}
      {:error, :expired} -> {:error, :expired}
      {:error, _reason} -> {:error, :invalid}
    end
  end

  def decode(_context, _token, _opts), do: {:error, :invalid}
end
