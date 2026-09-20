defmodule DemoWeb.FormFlowLive.Users do
  @moduledoc """
  The dedicated page for FormFlow's user-facing form instances: the pet
  license applications.

  Mounted on `live "/demo/pet-licenses/applications/*path",
  FormFlowLive.Users`, so `/demo/pet-licenses/applications` (the listing of
  the user's flow instances), `.../applications/:id` (one instance), and
  `.../applications/:id/forms/*` (a form inside it) all land here. FormFlow's
  router dispatches the remaining path to the right LiveComponent — this page
  just supplies the layout around it. `base="/demo/pet-licenses/applications"`
  is what makes every link the components build carry the mount prefix.

  `user_id`, `perspectives`, `instances` and `flows` are the current user's
  (`Demo.Users`): a pet owner is an applicant, so FormFlow shows them the
  applicant subflows of a journey and hides the reviewer's, and the listing
  is their own applications. `flows` is unset for a pet owner
  (`Demo.Users.flows/1`), which is FormFlow's "every root flow of the
  tenant": a flow the admin authors is there to start the moment they switch
  to this side. Only the pet owners reach this page - the gate turns
  everyone else away, the admin included.
  """

  use DemoWeb, :live_view

  import DemoWeb.PersonaComponents

  alias DemoWeb.Experiences

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Pet License Applications")
     |> assign(:current_nav, :users)}
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
          roles={Experiences.roles(:user)}
          page="the pet license applications"
        >
          <div id="users-pages">
            <FormFlow.Web.router
              user_id={@current_user.id}
              perspectives={@current_user.perspectives}
              instances={Demo.Users.instances(@current_user)}
              flows={Demo.Users.flows(@current_user)}
              uri={@uri}
              params={@params}
              path={@path}
              base="/demo/pet-licenses/applications"
              flow_types={DemoWeb.FormFlowLive.Types.flow_types()}
              form_types={DemoWeb.FormFlowLive.Types.form_types()}
              callback_data={%{hello: "world"}}
              pre_release_user_ids={Enum.map(Demo.Users.with_roles([:owner]), & &1.id)}
            />
          </div>
        </.persona_gate>
      </div>
    </Layouts.app>
    """
  end
end
