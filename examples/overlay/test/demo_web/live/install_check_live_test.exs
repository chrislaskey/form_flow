defmodule DemoWeb.InstallCheckLiveTest do
  use DemoWeb.ConnCase

  import Phoenix.LiveViewTest

  # Each library derives its own DOM ids from the id attribute it is passed:
  # PhoenixSelect renders "#status-select", DynamicForm renders the <form> as
  # "<id>-form", and Slab keeps its id on the LiveComponent and derives ids for
  # the parts it renders ("#flows-table-share").
  @select "#status-select"
  @dynamic_form "#contact-form-form"
  @slab_share "#flows-table-share"

  test "renders a component from each dependency", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/install-check")

    assert has_element?(view, @select)
    assert has_element?(view, @dynamic_form)
    assert has_element?(view, @slab_share)
  end

  test "phoenix_select drives the form", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/install-check")

    assert render(element(view, "#selected-status")) =~ "published"

    view
    |> element("#status-form")
    |> render_change(%{"install_check" => %{"status" => "draft"}})

    assert render(element(view, "#selected-status")) =~ "draft"
  end

  test "dynamic_form validates before it submits", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/install-check")

    html =
      view
      |> form(@dynamic_form, %{"dynamic_form" => %{"name" => "", "email" => "nope"}})
      |> render_submit()

    refute html =~ "Submitted:"

    view
    |> form(@dynamic_form, %{
      "dynamic_form" => %{"name" => "Ada", "email" => "ada@example.com"}
    })
    |> render_submit()

    # The library messages the parent LiveView, which flashes on handle_info;
    # re-render so that message is processed first
    assert render(view) =~ "Submitted:"
  end

  test "slab renders the seeded rows", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/install-check")

    html = render(element(view, "#slab-check"))

    assert html =~ "Enrollment"
    assert html =~ "Health check"
    assert html =~ "Tour request"
  end
end
