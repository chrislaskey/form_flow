defmodule FormFlow.Web.Instances.Shared do
  @moduledoc """
  `FormFlow.Web.Instances.Shared` names what an instance page decided, once:
  the state it is in, computed where the decisions were made and read by
  everything downstream of them.

  A LiveComponent's `handle_event/3` is reachable whenever the component is
  mounted, and these pages are mounted even when they drew a refusal instead
  of themselves — the host's `on_mount` said no, the flow's type says this
  form is another perspective's work, the flow instance is gone. Which
  buttons were rendered gates nothing. So the page computes the state once,
  every `render/1` clause matches on it, and every `handle_event/3` guards on
  it.

  Two functions, because two kinds of page ask. `page_state/1` is every
  instance page's half — the flow instance and the host's gate.
  `form_page_state/1` is that plus the states only a page showing one form
  can be in. The flow instance's page and the listing have no form in scope
  and no page-level `visible?`, so they ask the narrower one.

  ## The states

  | State | Meaning | Pages |
  |---|---|---|
  | `:flow_not_found` | the flow instance is gone | form pages, `FormFlow.Web.Instances.Flows.Show` |
  | `:redirecting` | the host's `on_mount` is sending the user elsewhere | all four |
  | `:refused` | the host's `on_mount` said no | all four |
  | `:not_visible` | the flow's type says this form is not this viewer's work | form pages |
  | `:not_started` | the position has no instance yet | form pages |
  | `:broken_definition` | the pinned definition will not parse | form pages |
  | `:completed` | the form is submitted | form pages |
  | `:ready` | the page draws its own content | all four |

  ## Precedence is part of the definition

  The order the two `cond`s test in is the order the states outrank each
  other, and it is deliberate: `:refused` outranks `:not_started`, so a
  refused viewer cannot learn from the page whether a form was started.
  `:broken_definition` outranks `:completed`, so a submitted form whose
  definition no longer parses says the more informative of the two — there
  is nothing to edit either way.

  `:not_visible` asks for a `:form` as well as a false `:visible?`, and that
  is not a detail. `FormFlow.Web.Instances.Forms.Shared` answers
  `{false, false}` for a position the tree no longer has, so **every
  stranded position is `visible?: false`**. The `:form` test is what sends a
  stranded position with no answers to `:not_started` — where the pages say
  "This form is not part of this flow." — and lets a stranded one that has
  answers still show them.

  ## Two rules, not one

  The state answers **"may this page act"**. It cannot answer **"may it act
  on *this thing*"**, and an event that takes its target from the client
  needs both: `FormFlow.Web.Instances.Flows.Show`'s Reopen checks the state
  and then that the position is one of the rows it drew, and
  `FormFlow.Web.Instances.Flows.Index`'s Start checks the state and then
  that the flow is one it offered.

  ## An invariant, not a branch

  There is no state for "the definition is missing". A form instance always
  has a version — the pin is `on_delete: :restrict` — so the branch could
  not fire, and an unreachable branch is an untestable one. If that ever
  breaks, a crash is more traceable than a silent "can't be rendered".
  `:broken_definition` is a different thing and does fire: a stored
  definition that will not parse.
  """

  @type page_state ::
          :flow_not_found
          | :redirecting
          | :refused
          | :not_visible
          | :not_started
          | :broken_definition
          | :completed
          | :ready

  @doc """
  The state of any instance page, from its assigns.

  Whether `:flow_instance` is there at all is the question, not what it
  holds: that is what lets one function serve both the listing, which has no
  instance in scope, and a page whose instance is gone.
  """
  @spec page_state(map()) :: page_state()
  def page_state(assigns) do
    cond do
      Map.has_key?(assigns, :flow_instance) and is_nil(assigns.flow_instance) ->
        :flow_not_found

      is_binary(assigns[:navigate_to]) ->
        :redirecting

      is_binary(assigns[:mount_error]) ->
        :refused

      true ->
        :ready
    end
  end

  @doc """
  The state of a page showing one form: `page_state/1` first, then the
  states only that kind of page can be in.
  """
  @spec form_page_state(map()) :: page_state()
  def form_page_state(assigns) do
    with :ready <- page_state(assigns) do
      cond do
        assigns[:visible?] == false and assigns[:form] -> :not_visible
        is_nil(assigns[:form_instance]) -> :not_started
        is_binary(assigns[:parse_error]) -> :broken_definition
        assigns[:form_instance].status == "completed" -> :completed
        true -> :ready
      end
    end
  end
end
