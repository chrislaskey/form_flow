defmodule FormFlow.Web.Instances.SharedTest do
  @moduledoc """
  The state each page computes, asked directly.

  Both functions are pure and take a plain map, so every state — and, more
  to the point, every ordering between two of them — is one assertion here
  rather than a page mounted into it.
  """

  use ExUnit.Case, async: true

  alias FormFlow.Data.Instances
  alias FormFlow.Web.Instances.Shared

  # A page that is drawing itself: an instance, a gate that said nothing, a
  # visible form with answers that parse
  defp ready(overrides \\ %{}) do
    Map.merge(
      %{
        flow_instance: %Instances.Flow{id: "flow-1"},
        navigate_to: nil,
        mount_error: nil,
        visible?: true,
        form: %Instances.FormProgress{path: ["a"]},
        form_instance: %Instances.Form{id: "form-1", status: "in_progress"},
        parse_error: nil
      },
      overrides
    )
  end

  describe "page_state/1" do
    test "a page drawing itself is ready" do
      assert Shared.page_state(ready()) == :ready
    end

    test "a gone flow instance is flow_not_found" do
      assert Shared.page_state(ready(%{flow_instance: nil})) == :flow_not_found
    end

    test "assigns with no flow_instance key at all are ready, not flow_not_found" do
      # This is what the listing looks like: no instance is in scope there,
      # which is a different thing from an instance that is gone
      assert Shared.page_state(%{navigate_to: nil, mount_error: nil}) == :ready
    end

    test "a redirecting gate is redirecting" do
      assert Shared.page_state(ready(%{navigate_to: "/elsewhere"})) == :redirecting
    end

    test "a refusing gate is refused" do
      assert Shared.page_state(ready(%{mount_error: "No."})) == :refused
    end

    test "flow_not_found beats everything" do
      assigns = ready(%{flow_instance: nil, navigate_to: "/elsewhere", mount_error: "No."})

      assert Shared.page_state(assigns) == :flow_not_found
    end

    test "redirecting beats refused" do
      assert Shared.page_state(ready(%{navigate_to: "/elsewhere", mount_error: "No."})) ==
               :redirecting
    end

    test "the form's own states are not its business" do
      assigns = ready(%{visible?: false, form_instance: nil, parse_error: "boom"})

      assert Shared.page_state(assigns) == :ready
    end
  end

  describe "form_page_state/1" do
    test "a page drawing its answers is ready" do
      assert Shared.form_page_state(ready()) == :ready
    end

    test "a submitted form is completed" do
      form_instance = %Instances.Form{id: "form-1", status: "completed"}

      assert Shared.form_page_state(ready(%{form_instance: form_instance})) == :completed
    end

    test "a form the type keeps from this viewer is not_visible" do
      assert Shared.form_page_state(ready(%{visible?: false})) == :not_visible
    end

    test "a position with no instance is not_started" do
      assert Shared.form_page_state(ready(%{form_instance: nil})) == :not_started
    end

    test "a definition that will not parse is a broken_definition" do
      assert Shared.form_page_state(ready(%{parse_error: "boom"})) == :broken_definition
    end

    test "every page_state outranks every form state" do
      for over <- [
            {%{flow_instance: nil}, :flow_not_found},
            {%{navigate_to: "/elsewhere"}, :redirecting},
            {%{mount_error: "No."}, :refused}
          ] do
        {assigns, expected} = over

        # Refused and not started is refused: a refused viewer cannot learn
        # from the page whether the form was started
        under = %{visible?: false, form_instance: nil, parse_error: "boom"}

        assert Shared.form_page_state(ready(Map.merge(under, assigns))) == expected
      end
    end

    test "not visible outranks a broken definition" do
      assert Shared.form_page_state(ready(%{visible?: false, parse_error: "boom"})) ==
               :not_visible
    end

    test "a broken definition outranks completed" do
      form_instance = %Instances.Form{id: "form-1", status: "completed"}

      assert Shared.form_page_state(ready(%{form_instance: form_instance, parse_error: "boom"})) ==
               :broken_definition
    end

    test "a stranded position with no answers is not_started, not not_visible" do
      # A position the tree no longer has is answered `{false, false}`, so
      # every stranded position arrives here with `visible?: false`. Without
      # a form it is the one the pages call "not part of this flow"…
      assigns = ready(%{visible?: false, form: nil, form_instance: nil})

      assert Shared.form_page_state(assigns) == :not_started
    end

    test "a stranded position that has answers is ready, not not_visible" do
      # …and with answers it still shows them. This is the ordering that
      # would change silently.
      assert Shared.form_page_state(ready(%{visible?: false, form: nil})) == :ready
    end
  end
end
