defmodule FormFlow.Web.Controllers.Downloads do
  @moduledoc """
  `FormFlow.Web.Controllers.Downloads` is the controller behind FormFlow's
  download and print routes, and the module that builds the URLs pointing at
  them.

  A LiveView cannot send a file: it holds a websocket, not a response. So a
  download is an ordinary link out of the page to an ordinary `GET`, which
  is what this route is — mounted once in the host's router, and pointed at
  from wherever a download makes sense. Today that is the user-facing
  form page (`FormFlow.Web.Instances.Forms.Show`); the route is shaped so
  the other resources the library will let people take away hang off the
  same mount.

  ## Download and print

  Two actions, the same bytes, one header apart:

    * `:download` sends `content-disposition: attachment`, which is a
      browser saving a file
    * `:print` sends `content-disposition: inline`, which is a browser
      opening the document in its own viewer, where the user reads it,
      prints it, and saves it if they want to

  Which of the two a browser honours exactly, and how, differs between
  Chrome, Firefox and Safari; the header is the whole of what a server can
  say about it.

  ## The URL

      <download_path>?disposition=download|print
                     &flow_instance_id=<id>
                     &path[]=<node id>&path[]=<node id>

  One path, and everything the request is about in the query string. The
  path carries nothing, which is the point: a host can mount this anywhere,
  however deeply nested, and — more usefully — can point the pages at an
  endpoint of its own instead, generating the document itself with no route
  of FormFlow's involved. Nothing about the shape has to be matched but the
  three params.

  `path[]` repeated is the position — the chain of node ids from the root
  flow down to the form node, exactly as `FormFlow.Web.Instances.Paths`
  builds it — so it arrives as the list it is rather than a string with a
  separator a host has to know. `disposition` is the one difference between
  Download and Print; anything but `print` is a download.

  Where the links point is the router's `download_path` attr, per mount,
  falling back to `path/0` — what `config :form_flow, download_path:` says
  this application serves. Neither set, and the pages offer no download at
  all: it is a feature an application turns on. `form_path/4` builds the
  URLs and this module parses them, so the two cannot drift.

  ## Authorization

  **This route is not authorized yet.** Anyone who can reach the URL and
  knows a flow instance id can read that form's answers. Mounting it inside
  a pipeline that authenticates is the whole of what a host can do today:

      scope "/" do
        pipe_through [:browser, :require_authenticated_user]
        form_flow_router_download_routes()
      end

  Per-resource authorization — the `on_mount` gate the instance pages ask
  before they render anything, asked here too, with the request's `user_id`
  and `tenant_id` reaching the context — is the next piece of this work.
  Until then the request is resolved with no user: the document is built
  from the stored answers alone, and no `FormFlow.Config` callback that
  reads `:user_id` sees one.
  """

  import Plug.Conn

  alias FormFlow.Data.Instances
  alias FormFlow.Web.Components.Forms.Downloads.Parsers
  alias FormFlow.Web.Downloads
  alias FormFlow.Web.Downloads.Token
  alias FormFlow.Web.Instances.Forms.Shared

  @default_mount "/form-flow/downloads"

  @doc """
  Where this application serves downloads from, or `nil` if it does not
  serve them at all.

  Nothing by default — taking a form away is a feature an application opts
  into, and one that does not want it should not have pages offering it:

      config :form_flow, download_path: "/form-flow/downloads"

  This is what the pages link to, unless a mount overrides it with
  `FormFlow.Web.router/1`'s `download_path` attr. Both `nil` and the pages
  draw no Download or Print link at all.
  """
  @spec path() :: String.t() | nil
  def path, do: Application.get_env(:form_flow, :download_path)

  @doc """
  Where `FormFlow.Router.form_flow_router_download_routes/1` mounts the route
  when it is not told: `path/0` when the application configured one, and
  `#{@default_mount}` otherwise.

  Unlike `path/0` this never returns `nil` — a declared route has to answer
  somewhere. An application that mounts the route but configures no path is
  serving downloads nothing links to until a page passes `download_path`
  itself, which is a legitimate way to offer them on one page only.
  """
  @spec mount_path() :: String.t()
  def mount_path, do: path() || @default_mount

  @doc """
  The URL that carries one minted token to the download endpoint.

  `base` is where downloads are served — the router's `download_path` attr,
  or `path/0` behind it. The token is the whole request: who, which form,
  and which of Download and Print, all inside it, so nothing rides beside it
  and nothing beside it is read:

      iex> FormFlow.Web.Controllers.Downloads.form_path("/files", "abc123")
      "/files?token=abc123"

  `FormFlow.Web.Instances.Forms.Show` mints the token when the user clicks
  and builds this with it; there is no clause for a `nil` base, because a
  page with nowhere to link draws no link.
  """
  @spec form_path(String.t(), String.t()) :: String.t()
  def form_path(base, token) when is_binary(base) and is_binary(token) do
    "#{base}?#{Plug.Conn.Query.encode(%{"token" => token})}"
  end

  @doc false
  # Phoenix calls this once, at compile time, with whatever the route was
  # declared with; `FormFlow.Router` is what declares it.
  def init(opts) do
    %{
      renderer: Keyword.get(opts, :renderer) || Downloads.default_renderer(),
      callback_data: Keyword.get(opts, :callback_data, %{})
    }
  end

  @doc false
  def call(conn, opts) do
    case document(conn) do
      {:ok, document, context, disposition} ->
        send_rendered(conn, document, context, disposition, opts)

      {:error, status, message} ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(status, message)
        |> halt()
    end
  end

  defp send_rendered(conn, document, context, disposition, opts) do
    case Downloads.render(document, context, opts.callback_data, opts.renderer) do
      {:ok, body, content_type, filename} ->
        conn
        |> Phoenix.Controller.send_download({:binary, body},
          filename: filename,
          content_type: content_type,
          disposition: disposition
        )
        |> halt()

      {:error, message} ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(500, message)
        |> halt()
    end
  end

  # The token is the request. Nothing else in the query string is read, so a
  # swapped `path` param cannot widen what a token was minted for, and the
  # identity the page had reaches the context rather than being guessed at
  # here.
  defp document(conn) do
    with {:ok, token} <- fetch_token(conn),
         {:ok, payload} <- decode(conn, token) do
      resolve(payload)
    end
  end

  defp fetch_token(%{params: %{"token" => token}}) when is_binary(token), do: {:ok, token}
  defp fetch_token(_conn), do: {:error, 404, "Not found."}

  defp decode(conn, token) do
    case Token.decode(conn, token) do
      {:ok, payload} -> {:ok, payload}
      {:error, :expired} -> {:error, 403, "This download link has expired. Try again."}
      {:error, :invalid} -> {:error, 403, "This download link is not valid."}
    end
  end

  defp resolve(%{flow_instance_id: flow_instance_id, path: path} = payload)
       when is_list(path) and path != [] do
    case Instances.Flows.get(flow_instance_id) do
      nil ->
        {:error, 404, "This flow no longer exists."}

      flow_instance ->
        resolved =
          Shared.resolve(%{
            flow_instance: flow_instance,
            path: path,
            user_id: payload[:user_id],
            tenant_id: payload[:tenant_id],
            perspectives: payload[:perspectives] || [],
            flow_types: FormFlow.Config.Flows.Type.defaults()
          })

        build(resolved.context, disposition(payload))
    end
  end

  defp resolve(_payload), do: {:error, 404, "Not found."}

  # The two words the page mints with, mapped to the header that makes a
  # browser save or show
  defp disposition(%{disposition: :print}), do: :inline
  defp disposition(_payload), do: :attachment

  defp build(context, disposition) do
    case Parsers.FormInstance.document(context) do
      {:ok, document} -> {:ok, document, context, disposition}
      {:error, :not_started} -> {:error, 404, "This form hasn't been started yet."}
      {:error, :no_definition} -> {:error, 422, "This form can't be rendered."}
    end
  end
end
