defmodule FormFlow.Web.Instances.Forms.EditTest do
  @moduledoc """
  The submit, asked directly.

  It is the one write on this page and it does not arrive through
  `handle_event/3`: DynamicForm's success message targets the parent
  LiveView, so `on_success` routes it back here as
  `update(%{event: "submitted"}, socket)`. That is where it is guarded, and
  the guard is tested the way the pages' events are — against the page's
  state, not against the markup, because a component is reachable whenever
  it is mounted.
  """

  use ExUnit.Case, async: true

  alias FormFlow.Data.Instances
  alias FormFlow.Web.Instances.Forms.Edit

  defp socket(overrides) do
    assigns =
      Map.merge(
        %{
          __changed__: %{},
          page_state: :ready,
          flow_instance: %Instances.Flow{id: "flow-1"},
          form_instance: %Instances.Form{id: "form-1", path: ["a"], status: "in_progress"},
          context: %FormFlow.Context{},
          form_type: %FormFlow.Config.Forms.Type{
            id: "default",
            module: FormFlow.Config.Forms.Type.Default,
            name: "Default"
          },
          callback_data: %{},
          user_id: "user-1",
          base: "",
          error: nil
        },
        overrides
      )

    %Phoenix.LiveView.Socket{assigns: assigns}
  end

  defp submitted, do: %{event: "submitted", payload: %{data: %{"name" => "Ada"}}}

  describe "the submit" do
    test "is refused when the gate refused the page" do
      socket = socket(%{page_state: :refused})

      assert {:ok, ^socket} = Edit.update(submitted(), socket)
    end

    test "is refused in every state but the page drawing its form" do
      for state <- [
            :flow_not_found,
            :redirecting,
            :refused,
            :not_visible,
            :not_started,
            :broken_definition,
            :completed
          ] do
        socket = socket(%{page_state: state})

        assert {:ok, ^socket} = Edit.update(submitted(), socket)
      end
    end

    test "is refused when the page has no state at all" do
      # The guard is positive, so a missing assign fails it and falls to the
      # refusal rather than reaching the write
      socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}

      assert {:ok, ^socket} = Edit.update(submitted(), socket)
    end

    test "the state is what decides it, not the assigns the write would use" do
      # Same assigns, the state flipped: now it gets past the form type's
      # snapshot and as far as the repo, which is absent here. That the two
      # differ is the guard doing its job.
      assert_raise UndefinedFunctionError, fn ->
        Edit.update(submitted(), socket(%{}))
      end
    end
  end

  describe "save draft" do
    # The form as the browser serialises it, which is what the Capture
    # button pushes
    defp save_draft, do: %{"params" => "dynamic_form%5Bname%5D=Ad"}

    test "is refused in every state but the page drawing its form" do
      for state <- [
            :flow_not_found,
            :redirecting,
            :refused,
            :not_visible,
            :not_started,
            :broken_definition,
            :completed
          ] do
        socket = socket(%{page_state: state})

        assert {:noreply, ^socket} = Edit.handle_event("save_draft", save_draft(), socket)
      end
    end

    test "is refused when the page has no state at all" do
      socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}

      assert {:noreply, ^socket} = Edit.handle_event("save_draft", save_draft(), socket)
    end

    test "the state is what decides it: ready reaches the write" do
      # As far as the repo, which is absent here
      assert_raise UndefinedFunctionError, fn ->
        Edit.handle_event("save_draft", save_draft(), socket(%{}))
      end
    end
  end

  describe "discard changes" do
    test "asking and confirming are both refused outside the page drawing its form" do
      for state <- [:refused, :not_visible, :not_started, :broken_definition, :completed] do
        socket = socket(%{page_state: state})

        assert {:noreply, ^socket} = Edit.handle_event("request_discard", %{}, socket)
        assert {:noreply, ^socket} = Edit.handle_event("confirm_discard", %{}, socket)
      end
    end

    test "asking opens the dialog; confirming reaches the write" do
      assert {:noreply, %{assigns: %{confirming_discard?: true}}} =
               Edit.handle_event("request_discard", %{}, socket(%{}))

      assert {:noreply, %{assigns: %{confirming_discard?: false}}} =
               Edit.handle_event("cancel_discard", %{}, socket(%{confirming_discard?: true}))

      # As far as the repo, which is absent here
      assert_raise UndefinedFunctionError, fn ->
        Edit.handle_event("confirm_discard", %{}, socket(%{}))
      end
    end
  end
end
