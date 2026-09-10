defmodule DemoWeb.FormFlowLive.Reviewers do
  @moduledoc """
  The dedicated page for the reviewer's side of FormFlow.

  Mounted on `live "/reviewers/*path", FormFlowLive.Reviewers`, the same
  shape as `DemoWeb.FormFlowLive.Users` — FormFlow's router dispatches the
  remaining path to the right LiveComponent, and `base="/reviewers"` is what
  makes every link the components build carry the mount prefix.

  What separates it from the user pages is who is looking: `user_id` is the
  reviewer's, so the listing is the instances the reviewer owns rather than
  an applicant's. The review flows themselves are still to come — the page
  exists now so the reviewer persona has somewhere of its own to land.
  """

  use DemoWeb, :live_view

  import DemoWeb.PageComponents
  import DemoWeb.PersonaComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Reviewers")
     |> assign(:current_nav, :reviewers)}
  end

  @impl true
  def handle_params(params, uri, socket) do
    {:noreply,
     socket
     |> assign(:path, Map.get(params, "path", []))
     |> assign(:params, params)
     |> assign(:uri, uri)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_nav={@current_nav} current_user={@current_user}>
      <div class="space-y-6">
        <.h1>Reviewer pages</.h1>

        <.persona_gate
          current_user={@current_user}
          roles={[:reviewer]}
          page="the reviewer pages"
        >
          <div id="reviewers-pages">
            <FormFlow.Web.router
              user_id="demo-reviewer"
              uri={@uri}
              params={@params}
              path={@path}
              base="/reviewers"
              flow_types={DemoWeb.FormFlowLive.Types.flow_types()}
              form_types={DemoWeb.FormFlowLive.Types.form_types()}
              callback_data={%{hello: "world"}}
              pre_release_user_ids={["demo-reviewer"]}
            />
          </div>
        </.persona_gate>
      </div>
    </Layouts.app>
    """
  end
end
