defmodule DemoWeb.FormFlowLive.OtherForms do
  @moduledoc """
  The catch-all user page: every flow outside the pet licensing group.

  Mounted on `live "/demo/other-forms/*path", FormFlowLive.OtherForms`, the
  same shape as `DemoWeb.FormFlowLive.Users` — FormFlow's router dispatches
  the remaining path to the right LiveComponent, and `base="/demo/other-forms"`
  is what makes every link the components build carry the mount prefix.

  What separates it from the applications page is its group. `flows` is
  every root flow in no group (`Demo.Users.flows/2` with `:none`), which is
  where a flow the admin builds lands until it is given one: the admin
  authors a flow, switches to a pet owner, and finds it here to start.
  Giving it the pet licensing group on its edit page moves it to the
  applications page instead, with no change to either page.

  The user is a pet owner all the same - the demo has no other kind of
  applicant - so `perspectives` and `instances` are theirs, and the gate
  admits the owners alone.
  """

  use DemoWeb, :live_view

  import DemoWeb.PersonaComponents

  alias DemoWeb.Experiences

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Other Forms")
     |> assign(:current_nav, :other_forms)}
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
          roles={Experiences.roles(:other)}
          page="the other forms"
        >
          <div id="other-forms-pages">
            <FormFlow.Web.router
              user_id={@current_user.id}
              perspectives={@current_user.perspectives}
              instances={Demo.Users.instances(@current_user)}
              flows={Demo.Users.flows(@current_user, :none)}
              uri={@uri}
              params={@params}
              path={@path}
              base="/demo/other-forms"
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
