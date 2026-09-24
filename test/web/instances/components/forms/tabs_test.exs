defmodule FormFlow.Web.Instances.Components.Forms.TabsTest do
  @moduledoc """
  Which of `FormFlow.Web.Components.Tabs`'s two navigation styles these
  three pages get.

  They want ordinary links, plus the one Edit tab that asks to reopen a
  submitted form. They never want the other style - every tab pushing
  `"navigate"` at the page - because none of the three pages handles that
  event. `target` reaching `Tabs` without an event alongside it is what
  picks the style they do not want.
  """

  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias FormFlow.Web.Instances.Components.Forms.Tabs

  @assigns %{
    base: "",
    flow_instance_id: "22a2a2a2-0000-4000-8000-000000000001",
    path: ["11a1a1a1-0000-4000-8000-000000000001"],
    active: :show,
    target: %Phoenix.LiveComponent.CID{cid: 1}
  }

  test "an unsubmitted form's tabs are plain links, not the \"navigate\" event" do
    html = render_component(&Tabs.tabs/1, @assigns)

    refute html =~ ~s(phx-click="navigate")
    assert html =~ ~s(/forms/11a1a1a1-0000-4000-8000-000000000001/edit)
    assert html =~ ~s(/forms/11a1a1a1-0000-4000-8000-000000000001/history)
  end

  test "a reopenable form's Edit tab asks the page, and the rest stay links" do
    html = render_component(&Tabs.tabs/1, Map.put(@assigns, :reopen_first?, true))

    refute html =~ ~s(phx-click="navigate")
    assert html =~ ~s(phx-click="request_reopen")
    assert html =~ ~s(/forms/11a1a1a1-0000-4000-8000-000000000001/history)
  end
end
