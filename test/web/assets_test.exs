defmodule FormFlow.Web.AssetsTest do
  use ExUnit.Case, async: false

  import Plug.Test
  import Plug.Conn

  alias FormFlow.Web.Assets

  setup do
    on_exit(fn -> Application.delete_env(:form_flow, :asset_path) end)
  end

  describe "mount_path/0" do
    test "defaults to /form-flow" do
      assert Assets.mount_path() == "/form-flow"
    end

    test "is configurable" do
      Application.put_env(:form_flow, :asset_path, "/assets/form-flow")

      assert Assets.mount_path() == "/assets/form-flow"
    end
  end

  describe "editor_path/0" do
    test "hangs off the mount path and carries the content hash" do
      assert Assets.editor_path() == "/form-flow/editor-#{Assets.hash()}"
    end

    test "follows the configured mount path, so the route cannot drift" do
      Application.put_env(:form_flow, :asset_path, "/assets/form-flow")

      assert Assets.editor_path() == "/assets/form-flow/editor-#{Assets.hash()}"
    end

    test "the hash is an md5 hex digest" do
      assert Assets.hash() =~ ~r/^[0-9a-f]{32}$/
    end
  end

  describe "call/2" do
    test "serves the editor bundle as a cacheable JavaScript module" do
      conn = Assets.call(conn(:get, Assets.editor_path()), Assets.init(:editor))

      assert conn.status == 200
      assert conn.halted
      assert get_resp_header(conn, "content-type") == ["text/javascript"]
      assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
    end

    test "the bundle exports what the colocated hook calls" do
      conn = Assets.call(conn(:get, Assets.editor_path()), Assets.init(:editor))

      for export <- ["injectStyles", "mount", "unmount"] do
        assert conn.resp_body =~ export
      end
    end

    test "the bundle carries its own stylesheet, so no CSS asset is needed" do
      conn = Assets.call(conn(:get, Assets.editor_path()), Assets.init(:editor))

      assert conn.resp_body =~ "ff-node"
      assert conn.resp_body =~ ".react-flow"
    end

    test "skips CSRF protection, since it is a static asset" do
      conn = Assets.call(conn(:get, Assets.editor_path()), Assets.init(:editor))

      assert conn.private[:plug_skip_csrf_protection]
    end
  end
end
