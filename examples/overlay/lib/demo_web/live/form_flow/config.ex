defmodule DemoWeb.FormFlowLive.Config do
  @moduledoc """
  The demo's `FormFlow.Config`, passed to both the admin and users pages:
  demonstrates extending a callback while keeping the library's defaults —
  the demo offers one custom flow type on top of the built-in wizards.
  `FormFlow.Config.Default` exists exactly for this, so an override doesn't
  have to restate the core options.

  One module serves both pages because a type is chosen on the admin side
  (the flow and form edit pages' dropdowns) and acted on in the users side
  (which forms a user may edit; what a form starts filled in with) — the same
  list has to answer in both places. What the types *do* is
  `DemoWeb.FormFlowLive.Checklist` and `DemoWeb.FormFlowLive.Prefill`.
  """

  use FormFlow.Config

  # The checklist joins the built-in types wherever they are offered; a flow
  # the defaults give no types (a "subflows" flow) gets none here either.
  # Every type, the built-in wizards included, is for the demo's two kinds of
  # user: a type's `perspectives` are the host's to set, and setting them on
  # the library's structs is how the wizards learn the host's roles.
  @impl true
  def enabled_flow_types(context, config_data) do
    case FormFlow.Config.Default.enabled_flow_types(context, config_data) do
      [] -> []
      types -> Enum.map(types ++ [checklist()], &%{&1 | perspectives: perspectives()})
    end
  end

  # The prefill type joins the library's Default and Review.
  @impl true
  def enabled_form_types(context, config_data) do
    FormFlow.Config.Default.enabled_form_types(context, config_data) ++ [prefill()]
  end

  # The kinds of user a "forms" flow can be for. The admin picks per subflow;
  # the users page then shows a viewer only the subflows for the
  # perspectives its `perspectives` attr names. The metadata is the host's
  # own — here, which desk a reviewer's work lands on.
  defp perspectives do
    [
      %FormFlow.Config.Flows.Perspective{
        id: "applicant",
        name: "Applicant",
        description: "The person the flow is about, filling in their own forms."
      },
      %FormFlow.Config.Flows.Perspective{
        id: "reviewer",
        name: "Reviewer",
        description: "Staff checking an applicant's answers.",
        metadata: %{desk: :regional}
      }
    ]
  end

  defp prefill do
    %FormFlow.Config.Forms.Type{
      id: "demo_prefill",
      module: DemoWeb.FormFlowLive.Prefill,
      name: "Demo prefill",
      description: "Starts with the name filled in from the host application.",
      properties: DemoWeb.FormFlowLive.Prefill.properties()
    }
  end

  defp checklist do
    %FormFlow.Config.Flows.Type{
      id: "demo_checklist",
      module: DemoWeb.FormFlowLive.Checklist,
      name: "Demo checklist",
      description: "A checklist rather than a wizard.",
      properties: []
    }
  end
end
