defmodule FormFlow.Web.CoreComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias FormFlow.Web.CoreComponents

  test "error/1 is public, so a host's override can be dispatched to the same way" do
    Code.ensure_loaded!(CoreComponents)
    assert function_exported?(CoreComponents, :error, 1)
  end

  describe "button/1" do
    test "renders a button with the primary-soft default class" do
      html = render_component(&CoreComponents.button/1, %{inner_block: text_slot("Save")})

      assert html =~ "btn"
      assert html =~ "btn-primary"
      assert html =~ "Save"
    end

    test "keeps type and disabled when called with an explicit rest, as DynamicForm does" do
      html =
        render_component(&CoreComponents.button/1, %{
          type: "button",
          disabled: true,
          rest: %{"phx-click" => "add_nested_entry"},
          inner_block: text_slot("Add")
        })

      assert html =~ ~s(type="button")
      assert html =~ "disabled"
      assert html =~ ~s(phx-click="add_nested_entry")
    end

    test "renders a link instead of a button when given navigate" do
      html =
        render_component(&CoreComponents.button/1, %{
          navigate: "/somewhere",
          inner_block: text_slot("Go")
        })

      assert html =~ "href=\"/somewhere\""
    end
  end

  describe "input/1" do
    test "marks a required field's label, as DynamicForm asks it to" do
      html =
        render_component(&CoreComponents.input/1, %{
          id: "name",
          name: "name",
          label: "Name",
          value: "",
          required: true,
          required_label: "*",
          rest: %{}
        })

      assert html =~ ~s(Name<span class="ml-0.5 text-red-500">*</span>)
      assert html =~ ~s(required)
    end

    test "a required select with a value offers no blank option; otherwise the prompt stays" do
      render = fn assigns ->
        render_component(
          &CoreComponents.input/1,
          Map.merge(
            %{
              id: "t",
              name: "t",
              type: "select",
              options: [{"A", "a"}],
              prompt: "Pick…",
              rest: %{}
            },
            assigns
          )
        )
      end

      refute render.(%{value: "a", required: true}) =~ ~s(<option value="">)
      assert render.(%{value: "", required: true}) =~ "Pick…"
      assert render.(%{value: "a", required: false}) =~ "Pick…"
    end

    test "shows no mark for an optional field, or a blanked mark" do
      optional =
        render_component(&CoreComponents.input/1, %{id: "a", name: "a", label: "A", value: ""})

      refute optional =~ "text-red-500"

      blanked =
        render_component(&CoreComponents.input/1, %{
          id: "a",
          name: "a",
          label: "A",
          value: "",
          required: true,
          required_label: false,
          rest: %{}
        })

      refute blanked =~ "text-red-500"
      assert blanked =~ "required"
    end
  end

  test "header/1 renders the title and subtitle slots" do
    html =
      render_component(&CoreComponents.header/1, %{
        inner_block: text_slot("Title"),
        subtitle: text_slot("Subtitle"),
        actions: []
      })

    assert html =~ "Title"
    assert html =~ "Subtitle"
  end

  test "list/1 renders each item's title and body" do
    html =
      render_component(&CoreComponents.list/1, %{
        item: [%{__slot__: :item, title: "Views", inner_block: fn _changed, _arg -> "42" end}]
      })

    assert html =~ "Views"
    assert html =~ "42"
  end

  test "table/1 renders a header per :col slot and one row per item" do
    html =
      render_component(&CoreComponents.table/1, %{
        id: "rows",
        rows: [%{name: "Ada"}],
        row_id: nil,
        row_item: &Function.identity/1,
        col: [
          %{__slot__: :col, label: "Name", inner_block: fn _changed, row -> row.name end}
        ],
        action: []
      })

    assert html =~ "Name"
    assert html =~ "Ada"
  end

  test "icon/1 renders the heroicon class name" do
    html = render_component(&CoreComponents.icon/1, %{name: "hero-x-mark"})

    assert html =~ "hero-x-mark"
  end

  describe "translate_error/1" do
    test "substitutes opts into the message" do
      assert CoreComponents.translate_error({"must be %{count} characters", count: 5}) ==
               "must be 5 characters"
    end
  end

  defp text_slot(text) do
    [%{__slot__: :inner_block, inner_block: fn _changed, _arg -> text end}]
  end
end
