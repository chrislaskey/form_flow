defmodule FormFlow.Web.Controllers.Downloads do
  @moduledoc """
  `FormFlow.Web.Controllers.Downloads` is the controller behind FormFlow's
  download and print routes, and the module that builds the URLs pointing at
  them.

  A LiveView cannot send a file: it holds a websocket, not a response. So a
  download is an ordinary link out of the page to an ordinary `GET`, which
  is what these routes are — mounted once in the host's router, and pointed
  at from wherever a download makes sense. Today that is the user-facing
  form page (`FormFlow.Web.Instances.Forms.Show`); the routes are shaped so
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

  ## The URLs

      <mount>/download/instances/:flow_instance_id/forms/*path
      <mount>/print/instances/:flow_instance_id/forms/*path

  The verb comes first because Phoenix's catch-all must be the last segment
  and a form's address ends in one: `*path` is the chain of node ids that
  names a position, exactly as `FormFlow.Web.Instances.Paths` builds it. The
  `instances` segment says which world the resource is from — the same split
  as `FormFlow.Data.Instances` and `FormFlow.Data.Templates` — so a template
  download later is a sibling route rather than a second mount.

  `<mount>` defaults to `/form-flow/downloads` and is read from one place,
  `mount_path/0`, so the routes and the links cannot drift.

  ## Authorization

  **These routes are not authorized yet.** Anyone who can reach the URL and
  knows a flow instance id can read that form's answers. Mounting them
  inside a pipeline that authenticates is the whole of what a host can do
  today:

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
  alias FormFlow.Web.Instances.Forms.Shared

  @default_mount_path "/form-flow/downloads"

  @doc """
  The path FormFlow's download routes are mounted at.

  Defaults to `#{@default_mount_path}`. Both the routes and the links the
  pages build come from this, so they cannot drift:

      config :form_flow, download_path: "/files/form-flow"
  """
  @spec mount_path() :: String.t()
  def mount_path do
    Application.get_env(:form_flow, :download_path, @default_mount_path)
  end

  @doc """
  The URL that saves the form at a position as a file.

  Takes the same arguments as `FormFlow.Web.Instances.Paths.form_path/3`
  minus the page's `base` — a download hangs off its own mount, not off
  whatever prefix the user-facing pages were mounted under.
  """
  @spec download_path(String.t(), [String.t()]) :: String.t()
  def download_path(flow_instance_id, path) do
    "#{mount_path()}/download#{form_suffix(flow_instance_id, path)}"
  end

  @doc """
  The URL that opens the form at a position in the browser's own document
  viewer, to read or print.
  """
  @spec print_path(String.t(), [String.t()]) :: String.t()
  def print_path(flow_instance_id, path) do
    "#{mount_path()}/print#{form_suffix(flow_instance_id, path)}"
  end

  defp form_suffix(flow_instance_id, path) do
    "/instances/#{flow_instance_id}/forms/#{Enum.join(path, "/")}"
  end

  @doc false
  # Phoenix calls this once, at compile time, with whatever the route was
  # declared with; `FormFlow.Router` is what declares them.
  def init(opts) do
    %{
      disposition: Keyword.fetch!(opts, :disposition),
      renderer: Keyword.get(opts, :renderer) || Downloads.default_renderer(),
      callback_data: Keyword.get(opts, :callback_data, %{})
    }
  end

  @doc false
  def call(conn, %{disposition: disposition} = opts) do
    case document(conn.params) do
      {:ok, document, context} ->
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

  # The position is resolved exactly as the Show page resolves it, so what a
  # download says and what that page shows are the same answers. The request
  # carries no host identity yet (see the moduledoc), so the resolution runs
  # with none and the library's default types.
  defp document(%{"flow_instance_id" => flow_instance_id, "path" => path})
       when is_list(path) and path != [] do
    case Instances.Flows.get(flow_instance_id) do
      nil ->
        {:error, 404, "This flow no longer exists."}

      flow_instance ->
        resolved =
          Shared.resolve(%{
            flow_instance: flow_instance,
            path: path,
            user_id: nil,
            tenant_id: nil,
            perspectives: [],
            flow_types: FormFlow.Config.Flows.Type.defaults()
          })

        build(resolved.context)
    end
  end

  defp document(_params), do: {:error, 404, "Not found."}

  defp build(context) do
    case Parsers.FormInstance.document(context) do
      {:ok, document} -> {:ok, document, context}
      {:error, :not_started} -> {:error, 404, "This form hasn't been started yet."}
      {:error, :no_definition} -> {:error, 422, "This form can't be rendered."}
    end
  end
end
