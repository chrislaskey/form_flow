defmodule DemoWeb.FormFlowLive.Reviewers do
  @moduledoc """
  The dedicated page for the reviewer's side of FormFlow: the pet license
  reviews.

  Mounted on `live "/demo/pet-licenses/reviews/*path", FormFlowLive.Reviewers`,
  the same shape as `DemoWeb.FormFlowLive.Users` — FormFlow's router dispatches
  the remaining path to the right LiveComponent, and
  `base="/demo/pet-licenses/reviews"` is what makes every link the components
  build carry the mount prefix.

  What separates it from the applications is who is looking: `user_id` is the
  reviewer's, so the listing is the instances the reviewer owns rather than
  an applicant's. The review flows themselves are still to come — the page
  exists now so the reviewer persona has somewhere of its own to land.
  """

  use DemoWeb, :live_view

  import DemoWeb.PersonaComponents

  alias DemoWeb.Experiences

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Pet License Reviews")
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
        <.persona_gate
          current_user={@current_user}
          roles={Experiences.roles(:reviewer)}
          page="the pet license reviews"
        >
          <div id="reviewers-pages">
            <FormFlow.Web.router
              user_id="demo-reviewer"
              uri={@uri}
              params={@params}
              path={@path}
              base="/demo/pet-licenses/reviews"
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
