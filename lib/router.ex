defmodule FormFlow.Router do
  @moduledoc """
  `FormFlow.Router` module provides the routes for FormFlow. For example, a
  user's downloads and printable documents controller are served from here.

  Each macro declares one group of routes, and a host imports this module
  once and calls the groups it wants. Both groups must come **before** any
  catch-all route in the host's router, which would otherwise swallow them.
  """

  @doc """
  Declares the route FormFlow's editor bundle is served from.

  Add it to your router, outside any pipeline — the asset needs no session,
  and it skips CSRF protection:

      # lib/my_app_web/router.ex
      import FormFlow.Router

      scope "/" do
        form_flow_router_asset_routes()
      end

  ## Options

    * `:at` - the path to mount at. Defaults to
      `FormFlow.Web.Assets.mount_path/0`, which reads
      `config :form_flow, asset_path: "..."`. Prefer configuring it, so the
      route and the URL the editor is fetched from stay in sync.

  Apps that would rather not import a macro can declare the route
  themselves, keeping the path in agreement with
  `FormFlow.Web.Assets.mount_path/0`:

      get "/form-flow/editor-:md5", FormFlow.Web.Assets, :editor
  """
  defmacro form_flow_router_asset_routes(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      # Fully qualified on purpose: this expands inside the host's router, where
      # an alias from this module would not exist
      # credo:disable-for-next-line Credo.Check.Design.AliasUsage
      scope Keyword.get(opts, :at, FormFlow.Web.Assets.mount_path()),
        alias: false,
        as: false do
        get("/editor-:md5", FormFlow.Web.Assets, :editor)
      end
    end
  end

  @doc """
  Declares the route a user's downloads and printable documents are served
  from.

  Add it to your router inside a pipeline that authenticates — the route
  sends a form's answers, and FormFlow does not yet authorize it itself
  (see `FormFlow.Web.Controllers.Downloads`):

      # lib/my_app_web/router.ex
      import FormFlow.Router

      scope "/" do
        pipe_through [:browser, :require_authenticated_user]

        form_flow_router_download_routes()
      end

  One route answers both Download and Print: which of the two is a query
  param, as is the resource, so the path itself carries nothing. Mount it
  wherever you like, however deeply nested — and tell the pages where it is
  with `FormFlow.Web.router/1`'s `download_path` attr, or with the config
  below, which both the route and the links fall back to.

  ## Options

    * `:at` - the path to mount at. Defaults to
      `FormFlow.Web.Controllers.Downloads.mount_path/0`, which reads
      `config :form_flow, download_path: "..."` and falls back to
      `/form-flow/downloads`. Configure it rather than passing it here: the
      pages draw their Download and Print links only when they know where
      downloads live, and the config is what tells them.
    * `:renderer` - the `FormFlow.Web.Downloads.Renderer` that turns a
      document into bytes. Defaults to `FormFlow.Web.Downloads.Renderer.PDF`,
      which needs nothing installed.
      `FormFlow.Web.Downloads.Renderer.HTML` prints through the browser
      instead, and a host wanting its own typography passes its own module.
    * `:callback_data` - the host's own map, handed to the renderer as the
      third argument every FormFlow callback takes. A literal: this is
      evaluated where the route is declared, at compile time, so it holds
      what is true of the application rather than of a request.

  A host that would rather generate the document itself declares no route
  here at all: it points `download_path` at an endpoint of its own and reads
  `flow_instance_id`, `path[]`, and `disposition` off the query string.

  Apps that would rather not import a macro can declare the route
  themselves, keeping the path in agreement with whatever the pages link to:

      get "/form-flow/downloads", FormFlow.Web.Controllers.Downloads, []
  """
  defmacro form_flow_router_download_routes(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      # Fully qualified on purpose: this expands inside the host's router, where
      # an alias from this module would not exist
      # credo:disable-for-next-line Credo.Check.Design.AliasUsage
      scope Keyword.get(opts, :at, FormFlow.Web.Controllers.Downloads.mount_path()),
        alias: false,
        as: false do
        get(
          "/",
          FormFlow.Web.Controllers.Downloads,
          Keyword.take(opts, [:renderer, :callback_data])
        )
      end
    end
  end
end
