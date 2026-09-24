defmodule DemoWeb.FormFlowLive.Reviewers do
  @moduledoc """
  The dedicated page for the reviewer's side of FormFlow: the pet license
  reviews.

  Mounted on `live "/demo/pet-licenses/reviews/*path", FormFlowLive.Reviewers`,
  the same shape as `DemoWeb.FormFlowLive.Users` — FormFlow's router dispatches
  the remaining path to the right LiveComponent, and
  `base="/demo/pet-licenses/reviews"` is what makes every link the components
  build carry the mount prefix.

  What separates it from the applications is who is looking. `perspectives`
  is the reviewer's, so FormFlow shows them the reviewer subflows of a
  journey and hides the applicant's. `instances` is every journey rather
  than the default of the viewer's own (`Demo.Users.instances/1`), because
  a reviewer starts none: without it this page is an empty table.

  `flows` names the two pet licenses with `start: false` on each
  (`Demo.Users.flows/1`), so this page has no Start section at all — a
  reviewer who could start an application would be filing one in their own
  name. The applications page leaves the attr unset and is about every flow
  the tenant holds; naming them here is also what keeps a flow the admin
  authors at run time from quietly becoming a reviewer's work.

  `actionable_only` is what makes this a queue rather than a list: only the
  journeys whose flow is open at one of the reviewer's forms - the applicant
  has finished, the review has not - are listed. An application the
  applicant is still filling in, or one waiting on its closing feedback, is
  not a reviewer's to act on and is not here. FormFlow reads that off the
  cache each form submit keeps (`FormFlow.Data.Instances.Flows.update_next_positions/2`),
  so the queue costs one indexed query however many applications there are.

  Listing is not access control. FormFlow opens any journey by id for
  anyone who reaches its URL, so what keeps an applicant off this page is
  `persona_gate` and the `:reviewer` role, not the query.
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
              user_id={@current_user.id}
              perspectives={@current_user.perspectives}
              instances={Demo.Users.instances(@current_user)}
              flows={Demo.Users.flows(@current_user)}
              actionable_only
              uri={@uri}
              params={@params}
              path={@path}
              base="/demo/pet-licenses/reviews"
              flow_types={DemoWeb.FormFlowLive.Types.flow_types()}
              form_types={DemoWeb.FormFlowLive.Types.form_types()}
              callback_data={%{hello: "world"}}
              pre_release_user_ids={Enum.map(Demo.Users.with_roles([:reviewer]), & &1.id)}
            />
          </div>
        </.persona_gate>
      </div>
    </Layouts.app>
    """
  end
end
