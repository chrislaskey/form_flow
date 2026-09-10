defmodule DemoWeb.FormFlowLive.Renewal do
  @moduledoc """
  The demo's renewal form type, behind the `"demo_renewal"` option: a form
  that starts filled in with what the same user answered last year.

  "Last year" is a copy. Dog License 2027 is a copy of Dog License 2026
  (`FormFlow.Data.Templates.Flows.copy/2`), and every form the copy owns
  records which lineage it was rolled over from — `copied_from_form_id` on
  `FormFlow.Data.Templates.Form`. That is the join, and this module walks it:
  from this year's form to last year's lineage; from the lineage to its
  owner, last year's root flow; from the flow to this user's journeys in it
  (`FormFlow.Data.Instances.Flows.list/1`, newest first); and in each journey
  to the form submitted at that lineage, whose answers are offered under the
  user's own — the shape every prefill takes (`DemoWeb.FormFlowLive.Prefill`).
  A user who skipped a year is found the year before: the walk follows
  `copied_from_form_id` back until a submitted form turns up or the
  provenance runs out. The walk needs no guard against cycles: the column
  is written by `FormFlow.Data.Templates.Forms.copy/2` alone, never cast,
  so a chain of copies only ever points at older lineages.

  It asks for the form the user *submitted* — a completed form instance at
  the position — and not for a completed journey: the demo never stamps a
  journey completed (`FormFlow.Data.Instances.Flows.complete/2` is the host's
  to call), and last year's review being unfinished is no reason to make the
  owner retype their address. A host that does stamp journeys narrows the
  same listing with `status: "completed"`. A step that reuses a catalog form
  has nothing to join — the same lineage serves both years — so the type
  prefills nothing there, and neither does it for a viewer with no
  `user_id`, whose last year nobody can name.
  """

  use FormFlow.Config.Forms.Type

  alias FormFlow.Config.Forms.Type
  alias FormFlow.Context
  alias FormFlow.Data.Instances
  alias FormFlow.Data.Instances.FlowProgress
  alias FormFlow.Data.Templates

  @impl true
  def initial_data(context, callback_data) do
    stored = Type.Default.initial_data(context, callback_data)

    Map.merge(last_years_answers(context), stored)
  end

  defp last_years_answers(%Context{user_id: nil}), do: %{}

  defp last_years_answers(%Context{form: %Templates.Form{} = form} = context),
    do: answers_at(form.copied_from_form_id, context) || %{}

  defp last_years_answers(%Context{}), do: %{}

  # The answers this user submitted at `form_id` in any journey of the flow
  # owning it, newest journey first — or the same one lineage back
  defp answers_at(nil, _context), do: nil

  defp answers_at(form_id, %Context{user_id: user_id, tenant_id: tenant_id} = context) do
    case Templates.Forms.get(form_id) do
      %Templates.Form{owner_flow_id: flow_id} = form when is_binary(flow_id) ->
        journeys = Instances.Flows.list(user_id: user_id, tenant_id: tenant_id, flow: flow_id)
        # Every journey here is of the one flow: its tree, resolved once
        tree = journeys != [] && Templates.Flows.resolve_tree(flow_id)

        Enum.find_value(journeys, &submitted_at(&1, tree, form.id)) ||
          answers_at(form.copied_from_form_id, context)

      _catalog_or_gone ->
        nil
    end
  end

  # The stored answers of the completed form at `form_id`'s position in a
  # journey, read the way the pages read progress: the resolved tree and
  # every form instance of the journey, so a superseded instance is passed
  # over and a step the flow no longer has is not a form of it
  defp submitted_at(%Instances.Flow{} = journey, tree, form_id) do
    tree
    |> FlowProgress.forms(Instances.Flows.form_instances(journey))
    |> Enum.find_value(fn
      %{node: %{form_id: ^form_id}, status: :completed, instance: %{data: data}} -> data
      _other -> nil
    end)
  end
end
