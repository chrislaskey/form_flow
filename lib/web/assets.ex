defmodule FormFlow.Web.Assets do
  @moduledoc """
  `FormFlow.Web.Assets` module serves FormFlow's prebuilt JavaScript.

  The flow editor is React and ReactFlow, ~390 KB of it. That is far too much to
  put in a host application's `app.js`, where every page would pay for it, so it
  isn't bundled at all: it is served from here and fetched at runtime by the
  colocated hook in `FormFlow.Web.Templates.Forms.Index`, only on pages that
  actually render the editor.

  The file is read into a module attribute at compile time and served with an
  MD5 of its contents in the path, so it can be cached immutably and never needs
  `mix phx.digest`.

  ## Installation

  Declare the route once, outside any pipeline:

      # lib/my_app_web/router.ex
      import FormFlow.Router

      form_flow_router_asset_routes()

  See `FormFlow.Router.form_flow_router_asset_routes/1`.
  """

  import Plug.Conn

  editor_path = Path.expand("../../priv/static/form_flow_editor.mjs", __DIR__)

  @external_resource editor_path

  @editor File.read!(editor_path)
  @hash Base.encode16(:crypto.hash(:md5, @editor), case: :lower)

  @default_mount_path "/form-flow"

  @doc """
  The path FormFlow's assets are mounted at.

  Defaults to `#{@default_mount_path}`. Both the route and the URL the hook
  fetches are derived from this, so they cannot drift:

      config :form_flow, asset_path: "/assets/form-flow"
  """
  def mount_path do
    Application.get_env(:form_flow, :asset_path, @default_mount_path)
  end

  @doc """
  The URL the editor bundle is served from, including its content hash.

  There is no file extension because Phoenix does not allow a suffix after a
  dynamic path segment. It makes no difference to the browser: a module's type
  comes from the `content-type` response header, not the path.
  """
  def editor_path do
    "#{mount_path()}/editor-#{@hash}"
  end

  @doc """
  The MD5 of the editor bundle.
  """
  def hash, do: @hash

  @doc false
  def init(asset) when asset in [:editor], do: asset

  @doc false
  def call(conn, :editor) do
    conn
    |> put_resp_header("content-type", "text/javascript")
    |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
    |> put_private(:plug_skip_csrf_protection, true)
    |> send_resp(200, @editor)
    |> halt()
  end
end
