defmodule DemoWeb.FormFlowLive.Types do
  @moduledoc """
  The demo's flow and form types — the lists both the admin and the users
  pages pass as `flow_types` and `form_types`. One module serves both pages
  because a type is chosen on the admin side (the flow and form edit pages'
  dropdowns) and acted on in the users side (which forms a user may edit;
  what a form starts filled in with) — the same list has to answer in both
  places, so both pages call the same function. What the types *do* is
  `DemoWeb.FormFlowLive.Checklist` and `DemoWeb.FormFlowLive.Prefill`.

  Each list starts from the library's defaults, so the demo offers its own
  types beside the built-in ones rather than instead of them.
  """

  # The checklist joins the built-in wizards. Every type, the wizards
  # included, is for the demo's two kinds of user: a type's `perspectives`
  # are the host's to set, and setting them on the library's structs is how
  # the wizards learn the host's roles.
  def flow_types do
    Enum.map(
      FormFlow.Config.Flows.Type.defaults() ++ [checklist()],
      &%{&1 | perspectives: perspectives()}
    )
  end

  # The prefill type joins the library's Default and Review.
  def form_types do
    FormFlow.Config.Forms.Type.defaults() ++ [prefill()]
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
