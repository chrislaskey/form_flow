defmodule FormFlow.Web.ComponentResolverTest do
  use ExUnit.Case, async: true
  use Phoenix.Component

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias FormFlow.Web.ComponentResolver

  # A host's own components module — defines only `button/1`, so dispatch for
  # anything else must fall back to FormFlow.Web.CoreComponents.
  defmodule Fake do
    use Phoenix.Component

    slot(:inner_block, required: true)

    def button(assigns) do
      ~H"""
      <button class="fake-button">{render_slot(@inner_block)}</button>
      """
    end
  end

  describe "resolve/1" do
    test "nil resolves to nil (built-ins only)" do
      assert ComponentResolver.resolve(nil) == nil
    end

    test "a loadable module resolves to itself" do
      assert ComponentResolver.resolve(Fake) == Fake
    end

    test "raises on a module that cannot be loaded" do
      assert_raise ArgumentError, ~r/could not be loaded/, fn ->
        ComponentResolver.resolve(:totally_bogus_module)
      end
    end
  end

  describe "provides?/2" do
    test "false for nil" do
      refute ComponentResolver.provides?(nil, :button)
    end

    test "true only for a function the module actually exports" do
      assert ComponentResolver.provides?(Fake, :button)
      refute ComponentResolver.provides?(Fake, :table)
    end
  end

  describe "render/3" do
    test "dispatches to the host module's own function when it provides one" do
      html = render_dispatch(Fake, :button, %{inner_block: text_slot("Save")})

      assert html =~ "fake-button"
    end

    test "falls back to FormFlow.Web.CoreComponents when the host doesn't provide it" do
      html =
        render_dispatch(Fake, :icon, %{name: "hero-x-mark"})

      assert html =~ "hero-x-mark"
    end

    test "renders the built-ins directly when no components module is given" do
      html = render_dispatch(nil, :button, %{inner_block: text_slot("Save")})

      assert html =~ "btn-primary"
    end
  end

  defp render_dispatch(components, fun, component_assigns) do
    render_component(&dispatch/1, %{
      components: components,
      fun: fun,
      component_assigns: component_assigns
    })
  end

  defp dispatch(assigns) do
    ~H"""
    {ComponentResolver.render(@components, @fun, @component_assigns)}
    """
  end

  defp text_slot(text) do
    [%{__slot__: :inner_block, inner_block: fn _changed, _arg -> text end}]
  end
end
