defmodule FormFlow.Web.Instances.Flows.ShowTest do
  @moduledoc """
  Reopen, asked directly, against both of the rules it needs.

  The page's state says whether the page may act at all. It cannot say
  whether the page may act on *this* position — the position arrives from
  the client — so the event also has to find the row it names among the ones
  the page drew. Reaching the write is what a failure here looks like: no
  repo is configured in the library's own tests, so a call that gets that
  far raises rather than returning.
  """

  use ExUnit.Case, async: true

  alias FormFlow.Data.Instances
  alias FormFlow.Web.Instances.Flows.Show

  defp socket(overrides) do
    assigns =
      Map.merge(
        %{
          __changed__: %{},
          page_state: :ready,
          flow_instance: %Instances.Flow{id: "flow-1"},
          flow_instance_id: "flow-1",
          user_id: "user-1",
          tenant_id: nil,
          rows: [row("done", :completed, %Instances.Form{id: "form-1", path: ["done"]})],
          error: nil
        },
        overrides
      )

    %Phoenix.LiveView.Socket{assigns: assigns}
  end

  defp row(segment, status, instance) do
    %{
      form: %Instances.FormProgress{path: [segment], status: status, instance: instance},
      editable?: false
    }
  end

  describe "reopen" do
    test "refuses when the gate refused the page" do
      socket = socket(%{page_state: :refused})

      assert {:noreply, ^socket} = Show.handle_event("reopen", %{"path" => "done"}, socket)
    end

    test "refuses in every state but the page drawing its rows" do
      for state <- [:flow_not_found, :redirecting, :refused] do
        socket = socket(%{page_state: state})

        assert {:noreply, ^socket} = Show.handle_event("reopen", %{"path" => "done"}, socket)
      end
    end

    test "refuses when the page has no state at all" do
      # The guard is positive, so a missing assign fails it and falls to the
      # refusal rather than reaching the write
      socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}

      assert {:noreply, ^socket} = Show.handle_event("reopen", %{"path" => "done"}, socket)
    end

    test "refuses a position the page never drew" do
      # The hole this closes: unguarded, the write creates an instance at
      # whatever position the client names, pinned to whatever form version
      # that node points at — anyone's
      socket = socket(%{})

      assert {:noreply, ^socket} =
               Show.handle_event("reopen", %{"path" => "somebody-elses-node"}, socket)
    end

    test "refuses a row it drew that has no instance — starting is not reopening" do
      socket = socket(%{rows: [row("available", :available, nil)]})

      assert {:noreply, ^socket} = Show.handle_event("reopen", %{"path" => "available"}, socket)
    end

    test "refuses a row it drew that is not completed" do
      instance = %Instances.Form{id: "form-1", path: ["open"]}
      socket = socket(%{rows: [row("open", :in_progress, instance)]})

      assert {:noreply, ^socket} = Show.handle_event("reopen", %{"path" => "open"}, socket)
    end

    test "a completed row the page drew is what gets as far as the write" do
      # Same event, the one row that passes both rules: it now reaches the
      # repo, which is absent here. That the two differ is the rules working.
      assert_raise UndefinedFunctionError, fn ->
        Show.handle_event("reopen", %{"path" => "done"}, socket(%{}))
      end
    end
  end
end
