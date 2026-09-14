defmodule FormFlow.Web.Templates.Forms.PreviewTest do
  @moduledoc """
  What the preview does with a definition it cannot draw.

  The page renders arbitrary admin-authored JSON, so a definition it chokes
  on is expected input rather than a bug — and `mount/3` is where that has to
  be settled. A definition left to fail at render takes the preview's process
  with it, and the client answers by remounting, which fails again: the
  crash-remount loop these tests exist to keep closed.

  `mount/3` is called directly, with a bare socket: nothing here needs an
  endpoint, and what is under test is the assigns it comes back with.
  """

  use ExUnit.Case, async: true

  alias FormFlow.Web.Templates.Forms.Builder
  alias FormFlow.Web.Templates.Forms.Preview

  defp mount(json) do
    {:ok, socket} =
      Preview.mount(
        :not_mounted_at_router,
        %{"id" => "preview", "definition" => json, "data" => %{}},
        %Phoenix.LiveView.Socket{}
      )

    socket.assigns
  end

  describe "a definition the renderer would raise on" do
    test "an unknown groupType is an inline error, not a crash" do
      json =
        ~s({"elements":[{"type":"panel","name":"who","groupType":"row","elements":[{"type":"text","name":"a","title":"A"}]}]})

      assigns = mount(json)

      assert assigns.instance == nil

      assert assigns.parse_error ==
               ~s("who" has a groupType of "row". The preview draws "horizontal" and "vertical".)
    end

    test "one inside a nested form's template is caught too" do
      json =
        ~s({"elements":[{"type":"paneldynamic","name":"addresses","templateElements":[{"type":"panel","name":"inner","groupType":"row","elements":[]}]}]})

      assert %{instance: nil, parse_error: error} = mount(json)
      assert error =~ ~s("inner" has a groupType of "row".)
    end

    test "every layout the form builder offers is one the preview draws" do
      for {_label, group_type} <- Builder.group_type_options() do
        json =
          ~s({"elements":[{"type":"panel","name":"who","groupType":"#{group_type}","elements":[{"type":"text","name":"a","title":"A"}]}]})

        assert %{parse_error: nil, instance: %DynamicForm.Instance{}} = mount(json)
      end
    end

    test "a definition with no groups at all is untouched" do
      assert %{parse_error: nil, instance: %DynamicForm.Instance{}} =
               mount(~s({"elements":[{"type":"text","name":"a","title":"A"}]}))
    end
  end

  describe "a definition that never parses" do
    test "unparseable JSON is an inline error" do
      assert %{instance: nil, parse_error: error} = mount("{nope")
      assert is_binary(error)
    end

    test "an element with no name is an inline error" do
      assert %{instance: nil, parse_error: error} = mount(~s({"elements":[{"type":"text"}]}))
      assert is_binary(error)
    end
  end
end
