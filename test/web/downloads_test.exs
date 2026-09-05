defmodule FormFlow.Web.DownloadsTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias FormFlow.Downloads.Renderer
  alias FormFlow.Web.Downloads

  setup do
    on_exit(fn -> Application.delete_env(:form_flow, :download_path) end)
  end

  describe "mount_path/0" do
    test "defaults to /form-flow/downloads" do
      assert Downloads.mount_path() == "/form-flow/downloads"
    end

    test "is configurable, the way the asset path is" do
      Application.put_env(:form_flow, :download_path, "/files/form-flow")

      assert Downloads.mount_path() == "/files/form-flow"
    end
  end

  describe "the URLs" do
    test "address a form by its position, the chain of node ids the pages use" do
      assert Downloads.download_path("flow-1", ["a", "b"]) ==
               "/form-flow/downloads/download/instances/flow-1/forms/a/b"

      assert Downloads.print_path("flow-1", ["a", "b"]) ==
               "/form-flow/downloads/print/instances/flow-1/forms/a/b"
    end

    test "follow the configured mount, so the routes and the links cannot drift" do
      Application.put_env(:form_flow, :download_path, "/files/form-flow")

      assert Downloads.download_path("flow-1", ["a"]) ==
               "/files/form-flow/download/instances/flow-1/forms/a"
    end

    test "differ only in the verb — the same document, one header apart" do
      download = Downloads.download_path("flow-1", ["a"])
      print = Downloads.print_path("flow-1", ["a"])

      assert String.replace(download, "/download/", "/print/") == print
    end
  end

  describe "init/1" do
    test "requires the disposition, which is the whole difference between the two routes" do
      assert %{disposition: :attachment} = Downloads.init(disposition: :attachment)
      assert %{disposition: :inline} = Downloads.init(disposition: :inline)

      assert_raise KeyError, fn -> Downloads.init([]) end
    end

    test "falls back to the PDF renderer, so a mount needs nothing installed" do
      assert %{renderer: Renderer.PDF} = Downloads.init(disposition: :inline)
    end

    test "takes the renderer and callback_data a mount names" do
      opts = Downloads.init(disposition: :inline, renderer: Renderer.HTML, callback_data: %{a: 1})

      assert opts.renderer == Renderer.HTML
      assert opts.callback_data == %{a: 1}
    end
  end

  describe "call/2" do
    test "a request naming no position is not a download" do
      conn =
        conn(:get, "/x")
        |> Map.put(:params, %{"flow_instance_id" => "flow-1", "path" => []})
        |> Downloads.call(Downloads.init(disposition: :attachment))

      assert conn.status == 404
      assert conn.halted
      assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]
    end
  end
end
