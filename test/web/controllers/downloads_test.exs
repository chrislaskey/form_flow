defmodule FormFlow.Web.Controllers.DownloadsTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias FormFlow.Web.Controllers.Downloads
  alias FormFlow.Web.Downloads.Renderer
  alias FormFlow.Web.Downloads.Token

  defmodule TestEndpoint do
    @moduledoc false
    def config(:secret_key_base), do: String.duplicate("a", 64)
  end

  setup do
    on_exit(fn -> Application.delete_env(:form_flow, :download_path) end)
  end

  describe "path/0" do
    test "is nothing until an application says it serves downloads" do
      assert Downloads.path() == nil
    end

    test "is what the application configured" do
      Application.put_env(:form_flow, :download_path, "/files/form-flow")

      assert Downloads.path() == "/files/form-flow"
    end
  end

  describe "mount_path/0" do
    test "falls back to /form-flow/downloads, since a declared route must answer somewhere" do
      assert Downloads.mount_path() == "/form-flow/downloads"
    end

    test "follows the configured path, so the route and the links agree" do
      Application.put_env(:form_flow, :download_path, "/files/form-flow")

      assert Downloads.mount_path() == "/files/form-flow"
    end
  end

  describe "form_path/2" do
    test "carries the token and nothing else — the token is the request" do
      assert Downloads.form_path("/form-flow/downloads", "abc123") ==
               "/form-flow/downloads?token=abc123"
    end

    test "hangs off whatever base it is given, however deeply nested" do
      assert Downloads.form_path("/app/tenants/9/files", "abc") ==
               "/app/tenants/9/files?token=abc"
    end

    test "escapes a token's base64 rather than assuming it is URL-safe" do
      url = Downloads.form_path("/d", "a+b/c=")

      assert Plug.Conn.Query.decode(URI.parse(url).query) == %{"token" => "a+b/c="}
    end

    test "has no clause for nowhere to link — a page with no path draws no link" do
      assert_raise FunctionClauseError, fn -> Downloads.form_path(nil, "abc") end
    end
  end

  describe "the token is the whole request" do
    defp token(payload), do: Token.encode(TestEndpoint, payload)

    # A request as the router hands it over: the endpoint is where
    # Phoenix.Token reads the secret from a conn
    defp call(params) do
      conn(:get, "/x")
      |> Plug.Conn.put_private(:phoenix_endpoint, TestEndpoint)
      |> Map.put(:params, params)
      |> Downloads.call(Downloads.init([]))
    end

    test "a request with no token is not a download" do
      assert call(%{}).status == 404
    end

    test "a token this application did not mint is refused" do
      assert %{status: 403, resp_body: body} = call(%{"token" => "not-a-token"})
      assert body =~ "not valid"
    end

    test "a token minted for another purpose is refused" do
      other = Phoenix.Token.encrypt(TestEndpoint, "something:else", %{flow_instance_id: "f"})

      assert call(%{"token" => other}).status == 403
    end

    test "an expired token says so, since the fix is to click again" do
      Application.put_env(:form_flow, :download_token_max_age, -1)
      on_exit(fn -> Application.delete_env(:form_flow, :download_token_max_age) end)

      payload = %{flow_instance_id: "f", path: ["a"], disposition: :download}

      assert %{status: 403, resp_body: body} = call(%{"token" => token(payload)})
      assert body =~ "expired"
    end

    test "params beside the token are not read, so one cannot widen what it grants" do
      # The token names no position, so the request stops before it looks
      # anything up. Query params naming one would carry it past that point
      # if they were read at all — they are not, so it stops all the same.
      payload = %{flow_instance_id: "f", path: [], disposition: :download}

      assert %{status: 404, resp_body: body} =
               call(%{
                 "token" => token(payload),
                 "flow_instance_id" => "some-other-flow",
                 "path" => ["b"]
               })

      assert body =~ "Not found."
    end

    test "a token naming no position is not a download" do
      payload = %{flow_instance_id: "f", path: [], disposition: :download}

      assert call(%{"token" => token(payload)}).status == 404
    end
  end

  describe "init/1" do
    test "needs nothing: one route answers both, and the verb comes with the request" do
      assert %{renderer: Renderer.PDF, callback_data: %{}} = Downloads.init([])
    end

    test "takes the renderer and callback_data a mount names" do
      opts = Downloads.init(renderer: Renderer.HTML, callback_data: %{a: 1})

      assert opts.renderer == Renderer.HTML
      assert opts.callback_data == %{a: 1}
    end
  end

  describe "call/2" do
    test "a request naming no position is not a download" do
      conn =
        conn(:get, "/x")
        |> Map.put(:params, %{"flow_instance_id" => "flow-1", "path" => []})
        |> Downloads.call(Downloads.init([]))

      assert conn.status == 404
      assert conn.halted
      assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]
    end

    test "a request naming no resource at all is not a download either" do
      conn = conn(:get, "/x") |> Map.put(:params, %{}) |> Downloads.call(Downloads.init([]))

      assert conn.status == 404
    end
  end
end
