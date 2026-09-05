defmodule FormFlow do
  @moduledoc """
  `FormFlow` module has two primary parts:

  - `FormFlow.Data` for all backend and data related code
  - `FormFlow.Web`  for all UI, UX, presentation, and web related code
  """

  def app_config(key), do: Application.get_env(:form_flow, key)

  @doc """
  Reads back a download token FormFlow minted — what a host's own download
  endpoint calls to find out who asked for what.

  The stable name for `FormFlow.Web.Downloads.Token.decode/3`; see there for
  the payload, the lifetime, and what a token does and does not prove.

      def show(conn, %{"token" => token}) do
        case FormFlow.decode_token(conn, token) do
          {:ok, %{flow_instance_id: id, path: path, user_id: user_id}} -> ...
          {:error, :expired} -> ...
          {:error, :invalid} -> ...
        end
      end
  """
  defdelegate decode_token(context, token, opts \\ []),
    to: FormFlow.Web.Downloads.Token,
    as: :decode
end
