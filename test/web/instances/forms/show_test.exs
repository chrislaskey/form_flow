defmodule FormFlow.Web.Instances.Forms.ShowTest do
  @moduledoc """
  The page's events, asked directly.

  A LiveComponent's `handle_event/3` is reachable whenever the component is
  mounted, and this one is mounted even when the page drew a refusal — the
  host's `on_mount` said no, or the flow's type says this form is another
  perspective's work. Which buttons were rendered gates nothing, so the
  events are tested against the page's state
  (`FormFlow.Web.Instances.Shared.form_page_state/1`) rather than against
  the markup.
  """

  use ExUnit.Case, async: true

  alias FormFlow.Data.Instances
  alias FormFlow.Web.Downloads.Token
  alias FormFlow.Web.Instances.Forms.Show

  defmodule TestEndpoint do
    @moduledoc false
    def config(:secret_key_base), do: String.duplicate("a", 64)
  end

  defp socket(assigns) do
    %Phoenix.LiveView.Socket{
      assigns: Map.merge(%{__changed__: %{}, page_state: :refused}, assigns)
    }
  end

  describe "reopen" do
    test "does nothing when the gate refused the page" do
      socket = socket(%{page_state: :refused})

      assert {:noreply, ^socket} = Show.handle_event("reopen", %{}, socket)
    end

    test "does nothing when the page has no state at all" do
      # The guard is positive, so a missing assign fails it and falls to the
      # refusal rather than reaching the write
      socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}

      assert {:noreply, ^socket} = Show.handle_event("reopen", %{}, socket)
    end

    test "is refused before it reads a thing, so a refused page cannot reach the data" do
      # No repo is configured in the library's own tests: reaching the write
      # would raise rather than return, which is what makes this meaningful
      socket =
        socket(%{
          page_state: :not_visible,
          flow_instance: %Instances.Flow{id: "flow-1"},
          form_instance: %Instances.Form{id: "form-1", path: ["a"]},
          user_id: "user-1",
          tenant_id: nil,
          base: ""
        })

      assert {:noreply, ^socket} = Show.handle_event("reopen", %{}, socket)
    end

    test "the state is what decides it, not the assigns the write would use" do
      # Same assigns, the state flipped: now it gets as far as the repo, which
      # is absent here. That the two differ is the guard doing its job.
      assigns = %{
        page_state: :completed,
        flow_instance: %Instances.Flow{id: "flow-1"},
        form_instance: %Instances.Form{id: "form-1", path: ["a"]},
        user_id: "user-1",
        tenant_id: nil,
        base: ""
      }

      assert_raise UndefinedFunctionError, fn ->
        Show.handle_event("reopen", %{}, socket(assigns))
      end
    end
  end

  describe "minting a download" do
    # `endpoint` is a field on the socket, not an assign: it is where
    # Phoenix.Token reads the application's secret from
    defp minting_socket(overrides) do
      %{
        socket(
          Map.merge(
            %{
              page_state: :ready,
              download_path: "/form-flow/downloads",
              user_id: "user-1",
              tenant_id: "acme",
              perspectives: ["reviewer"],
              flow_instance: %Instances.Flow{id: "flow-1"},
              path: ["node-1", "node-2"]
            },
            overrides
          )
        )
        | endpoint: TestEndpoint
      }
    end

    test "refuses when the gate refused the page, however the event arrived" do
      socket = minting_socket(%{page_state: :refused})

      assert {:noreply, ^socket} = Show.handle_event("form_flow:download", %{}, socket)
    end

    test "a submitted form's answers are as downloadable as one still in progress" do
      assert {:reply, %{url: _url}, _socket} =
               Show.handle_event(
                 "form_flow:download",
                 %{},
                 minting_socket(%{page_state: :completed})
               )
    end

    test "refuses in every state that is not the page drawing its answers" do
      for state <- [
            :flow_not_found,
            :redirecting,
            :refused,
            :not_visible,
            :not_started,
            :broken_definition
          ] do
        socket = minting_socket(%{page_state: state})

        assert {:noreply, ^socket} = Show.handle_event("form_flow:download", %{}, socket)
      end
    end

    test "replies with a URL carrying everything the request is" do
      socket = minting_socket(%{})

      assert {:reply, %{url: url}, ^socket} =
               Show.handle_event("form_flow:download", %{"disposition" => "print"}, socket)

      assert %URI{path: "/form-flow/downloads", query: query} = URI.parse(url)
      assert %{"token" => token} = Plug.Conn.Query.decode(query)

      assert {:ok, payload} = Token.decode(TestEndpoint, token)

      assert payload == %{
               user_id: "user-1",
               tenant_id: "acme",
               perspectives: ["reviewer"],
               flow_instance_id: "flow-1",
               path: ["node-1", "node-2"],
               disposition: :print
             }
    end

    test "the token is the only thing in the URL" do
      {:reply, %{url: url}, _socket} =
        Show.handle_event(
          "form_flow:download",
          %{"disposition" => "download"},
          minting_socket(%{})
        )

      assert Plug.Conn.Query.decode(URI.parse(url).query) |> Map.keys() == ["token"]
    end

    test "anything but an explicit print is a download, which never navigates the page away" do
      for params <- [%{}, %{"disposition" => "download"}, %{"disposition" => "nonsense"}] do
        {:reply, %{url: url}, _socket} =
          Show.handle_event("form_flow:download", params, minting_socket(%{}))

        %{"token" => token} = Plug.Conn.Query.decode(URI.parse(url).query)

        assert {:ok, %{disposition: :download}} = Token.decode(TestEndpoint, token)
      end
    end

    test "mints against the page it was clicked on, so a link cannot outlive its page" do
      {:reply, %{url: first}, _} =
        Show.handle_event("form_flow:download", %{}, minting_socket(%{}))

      {:reply, %{url: second}, _} =
        Show.handle_event("form_flow:download", %{}, minting_socket(%{path: ["other"]}))

      refute first == second
    end
  end
end
