defmodule FormFlow.Web.Downloads.Router do
  @moduledoc """
  `FormFlow.Web.Downloads.Router` module provides the routes a user's
  downloads and printable documents are served from.
  """

  @doc """
  Declares FormFlow's download and print routes.

  Add them to your router inside a pipeline that authenticates — the routes
  send a form's answers, and FormFlow does not yet authorize them itself
  (see `FormFlow.Web.Downloads`):

      # lib/my_app_web/router.ex
      import FormFlow.Web.Downloads.Router

      scope "/" do
        pipe_through [:browser, :require_authenticated_user]

        form_flow_downloads()
      end

  ## Options

    * `:at` - the path to mount at. Defaults to
      `FormFlow.Web.Downloads.mount_path/0`, which reads
      `config :form_flow, download_path: "..."`. Prefer configuring it, so
      the routes and the links the pages build stay in sync.
    * `:renderer` - the `FormFlow.Downloads.Renderer` that turns a document
      into bytes. Defaults to `FormFlow.Downloads.Renderer.PDF`, which needs
      nothing installed. `FormFlow.Downloads.Renderer.HTML` prints through
      the browser instead, and a host wanting its own typography passes its
      own module.
    * `:callback_data` - the host's own map, handed to the renderer as the
      third argument every FormFlow callback takes. A literal: this is
      evaluated where the route is declared, at compile time, so it holds
      what is true of the application rather than of a request.

  Apps that would rather not import a macro can declare the routes
  themselves, keeping the path in agreement with
  `FormFlow.Web.Downloads.mount_path/0`:

      get "/form-flow/downloads/download/instances/:flow_instance_id/forms/*path",
          FormFlow.Web.Downloads,
          disposition: :attachment

      get "/form-flow/downloads/print/instances/:flow_instance_id/forms/*path",
          FormFlow.Web.Downloads,
          disposition: :inline
  """
  defmacro form_flow_downloads(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      # Fully qualified on purpose: this expands inside the host's router, where
      # an alias from this module would not exist
      # credo:disable-for-next-line Credo.Check.Design.AliasUsage
      scope Keyword.get(opts, :at, FormFlow.Web.Downloads.mount_path()),
        alias: false,
        as: false do
        get(
          "/download/instances/:flow_instance_id/forms/*path",
          FormFlow.Web.Downloads,
          [disposition: :attachment] ++ Keyword.take(opts, [:renderer, :callback_data])
        )

        get(
          "/print/instances/:flow_instance_id/forms/*path",
          FormFlow.Web.Downloads,
          [disposition: :inline] ++ Keyword.take(opts, [:renderer, :callback_data])
        )
      end
    end
  end
end
