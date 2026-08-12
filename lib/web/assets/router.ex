defmodule FormFlow.Web.Assets.Router do
  @moduledoc """
  `FormFlow.Web.Assets.Router` module provides the route that serves FormFlow's
  prebuilt JavaScript.
  """

  @doc """
  Declares the route FormFlow's editor bundle is served from.

  Add it to your router, outside any pipeline — the asset needs no session, and
  it skips CSRF protection:

      # lib/my_app_web/router.ex
      import FormFlow.Web.Assets.Router

      scope "/" do
        form_flow_assets()
      end

  ## Options

    * `:at` - the path to mount at. Defaults to
      `FormFlow.Web.Assets.mount_path/0`, which reads
      `config :form_flow, asset_path: "..."`. Prefer configuring it, so the
      route and the URL the editor is fetched from stay in sync.

  Apps that would rather not import a macro can declare the route themselves,
  keeping the path in agreement with `FormFlow.Web.Assets.mount_path/0`:

      get "/form-flow/editor-:md5", FormFlow.Web.Assets, :editor
  """
  defmacro form_flow_assets(opts \\ []) do
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
end
