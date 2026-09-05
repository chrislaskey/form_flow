defmodule FormFlow.Web.Instances.Flows.IndexTest do
  @moduledoc """
  Start, asked directly.

  This page builds its listing *inside* the gate's `on_ok`, so a refused
  viewer has no `:page_flows` at all — which is what made the event a crash
  rather than a check. The state is the first of its two rules; the flows
  the page offered are the second.
  """

  use ExUnit.Case, async: true

  alias FormFlow.Data.Templates
  alias FormFlow.Web.Instances.Flows.Index

  defp socket(overrides) do
    assigns =
      Map.merge(
        %{
          __changed__: %{},
          page_state: :ready,
          page_flows: [%Templates.Flow{id: "flow-1"}],
          user_id: "user-1",
          tenant_id: nil,
          base: "",
          error: nil
        },
        overrides
      )

    %Phoenix.LiveView.Socket{assigns: assigns}
  end

  describe "start" do
    test "refuses when the gate refused the page, and does not look for a listing" do
      # A refusal means `load/1` never ran, so `:page_flows` is not there —
      # reading it is the KeyError the guard replaces
      socket =
        socket(%{page_state: :refused}) |> Map.update!(:assigns, &Map.delete(&1, :page_flows))

      assert {:noreply, ^socket} = Index.handle_event("start", %{"flow-id" => "flow-1"}, socket)
    end

    test "refuses while the gate is redirecting" do
      socket = socket(%{page_state: :redirecting})

      assert {:noreply, ^socket} = Index.handle_event("start", %{"flow-id" => "flow-1"}, socket)
    end

    test "refuses when the page has no state at all" do
      # The guard is positive, so a missing assign fails it and falls to the
      # refusal rather than reaching the write
      socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}

      assert {:noreply, ^socket} = Index.handle_event("start", %{"flow-id" => "flow-1"}, socket)
    end

    test "a flow the page did not offer is refused with the page's message" do
      assert {:noreply, socket} =
               Index.handle_event("start", %{"flow-id" => "another"}, socket(%{}))

      assert socket.assigns.error == "That flow is not available here."
    end

    test "a flow the page offered is what gets as far as the write" do
      # No repo is configured in the library's own tests, so reaching the
      # create raises. That this one differs from the refusals is the rules
      # doing their job.
      assert_raise UndefinedFunctionError, fn ->
        Index.handle_event("start", %{"flow-id" => "flow-1"}, socket(%{}))
      end
    end
  end
end
