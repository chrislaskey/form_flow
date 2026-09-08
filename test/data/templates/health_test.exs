defmodule FormFlow.Data.Templates.Flows.HealthTest do
  @moduledoc """
  `FormFlow.Data.Templates.Flows.Health.check/2` over hand-built trees —
  pure structs, no database, the way
  `FormFlow.Data.Templates.Flows.ConnectedTreeTest` builds its fixtures. Each
  test wires one flow one way and asserts on the codes that come out, since
  the codes are the stable part; messages are checked where their wording
  is the point.
  """

  use ExUnit.Case, async: true

  alias FormFlow.Config.Flows.Perspective
  alias FormFlow.Config.Property
  alias FormFlow.Data.Templates.Flow
  alias FormFlow.Data.Templates.Flows.Health
  alias FormFlow.Data.Templates.Flows.Health.Problem
  alias FormFlow.Data.Templates.Form
  alias FormFlow.Data.Templates.Form.Version

  # --- fixtures --------------------------------------------------------------

  defp build_node(labels, opts) do
    %Flow.Node{
      id: Ecto.UUID.generate(),
      labels: labels,
      form_id: Keyword.get(opts, :form_id),
      form: Keyword.get(opts, :form, %Ecto.Association.NotLoaded{}),
      subflow_id: Keyword.get(opts, :subflow_id),
      properties: %{"data" => %{"label" => Keyword.get(opts, :label)}}
    }
  end

  defp start_node, do: build_node(["Start"], label: "Start")
  defp end_node, do: build_node(["End"], label: "End")

  # A form node whose form is published — the healthy default
  defp form_node(label, opts \\ []) do
    form = Keyword.get_lazy(opts, :form, fn -> published_form(label) end)
    build_node(["Form"], form_id: form && form.id, form: form, label: label)
  end

  defp subflow_node(label, subflow_id) do
    build_node(["Subflow"], subflow_id: subflow_id, label: label)
  end

  defp published_form(name, properties \\ %{}) do
    %Form{
      id: Ecto.UUID.generate(),
      name: name,
      properties: properties,
      versions: [%Version{status: "published", version: 1, definition: %{"a" => 1}}]
    }
  end

  defp draft_only_form(name) do
    %Form{
      id: Ecto.UUID.generate(),
      name: name,
      properties: %{},
      versions: [%Version{status: "draft"}]
    }
  end

  defp edge(source, target) do
    %Flow.Relationship{
      id: Ecto.UUID.generate(),
      source_id: source.id,
      target_id: target.id,
      label: "CONNECTS_TO"
    }
  end

  defp tree(nodes, edges, opts \\ []) do
    flow = %Flow{
      id: Keyword.get(opts, :id, Ecto.UUID.generate()),
      name: Keyword.get(opts, :name, "Flow"),
      label: Keyword.get(opts, :label, "forms"),
      properties: Keyword.get(opts, :properties, %{})
    }

    %{flow: flow, nodes: nodes, relationships: edges, subflows: Keyword.get(opts, :subflows, %{})}
  end

  # Start → each form in turn → End
  defp chain(forms, opts \\ []) do
    start = start_node()
    stop = end_node()
    nodes = [start | forms] ++ [stop]
    edges = nodes |> Enum.chunk_every(2, 1, :discard) |> Enum.map(fn [a, b] -> edge(a, b) end)

    tree(nodes, edges, opts)
  end

  defp codes(%Health{problems: problems}), do: Enum.map(problems, & &1.code)

  # --- a healthy flow ----------------------------------------------------------

  test "a connected flow of published forms has nothing to report" do
    health = Health.check(chain([form_node("Name"), form_node("Address")]))

    assert %Health{level: :ok, problems: [], counts: %{error: 0, warning: 0, info: 0}} = health
    assert Health.ok?(health)
  end

  test "nil in, nil out" do
    assert Health.check(nil) == nil
  end

  # --- structure ---------------------------------------------------------------

  test "missing Start and End nodes are errors" do
    name = form_node("Name")

    assert codes(Health.check(tree([name], []))) == [:no_start, :no_end]
  end

  test "Start not connecting to End is an error, once, however long the dangling chain" do
    start = start_node()
    name = form_node("Name")
    address = form_node("Address")
    stop = end_node()

    health =
      Health.check(tree([start, name, address, stop], [edge(start, name), edge(name, address)]))

    assert codes(health) == [:end_unreachable, :unconnected]

    assert [
             %Problem{message: "This flow does not connect Start to End", node_id: nil, path: []}
             | _
           ] =
             health.problems

    # End itself is what is unconnected — not the chain leading towards it
    assert [%Problem{code: :unconnected, node_id: end_id}] = Health.at(health, :warning)
    assert end_id == stop.id
  end

  test "a node no Start reaches is a warning, and what is behind it goes unchecked" do
    loose = form_node("Loose", form: draft_only_form("Loose"))
    %{nodes: nodes, relationships: edges} = chain([form_node("Name")])

    health = Health.check(tree(nodes ++ [loose], edges))

    assert [%Problem{level: :warning, code: :unconnected, node_id: node_id, path: [path_id]}] =
             health.problems

    assert node_id == loose.id and path_id == loose.id
    assert health.level == :warning
  end

  test "a reachable node nothing follows is a dead end" do
    %{nodes: nodes, relationships: edges} = chain([form_node("Name")])
    [start | _rest] = nodes
    aside = form_node("Aside")

    health = Health.check(tree(nodes ++ [aside], edges ++ [edge(start, aside)]))

    assert [%Problem{code: :dead_end, message: "“Aside” leads nowhere — nothing follows it"}] =
             health.problems
  end

  test "Start wired straight to End is a warning" do
    assert codes(Health.check(chain([]))) == [:no_steps]
  end

  # --- forms -----------------------------------------------------------------

  test "a connected form with no published version is an error" do
    health = Health.check(chain([form_node("Name", form: draft_only_form("Name"))]))

    assert [
             %Problem{
               level: :error,
               code: :form_not_published,
               message: "“Name” has no published version — users cannot start it"
             }
           ] = health.problems
  end

  test "a form step pointing at nothing is an error" do
    assert codes(Health.check(chain([form_node("Name", form: nil)]))) == [:form_missing]
  end

  test "a form whose versions are not loaded says nothing about publishing" do
    node = build_node(["Form"], form_id: Ecto.UUID.generate(), label: "Name")

    assert Health.ok?(Health.check(chain([node])))
  end

  test "a draft that differs from the latest published version is info" do
    form = published_form("Name")
    same = %Version{status: "draft", definition: %{"a" => 1}}
    changed = %Version{status: "draft", definition: %{"a" => 2}}

    assert Health.ok?(
             Health.check(
               chain([form_node("Name", form: %{form | versions: form.versions ++ [same]})])
             )
           )

    health =
      Health.check(
        chain([form_node("Name", form: %{form | versions: form.versions ++ [changed]})])
      )

    assert [%Problem{level: :info, code: :unpublished_changes}] = health.problems
    assert health.level == :info
  end

  test "an archived-only lineage counts as unpublished" do
    form = %Form{
      id: Ecto.UUID.generate(),
      name: "Old",
      properties: %{},
      versions: [%Version{status: "archived", version: 1}]
    }

    assert codes(Health.check(chain([form_node("Old", form: form)]))) == [:form_not_published]
  end

  # --- types -------------------------------------------------------------------

  test "a form type the host does not offer is a warning" do
    form = published_form("Name", %{"form_type" => "gone"})

    assert [
             %Problem{
               code: :unknown_type,
               message: "“Name” uses the form type “gone”, which is not offered"
             }
           ] =
             Health.check(chain([form_node("Name", form: form)])).problems
  end

  test "a required form property left unset is an error — the Review type's source" do
    form = published_form("Check", %{"form_type" => "review"})

    assert [%Problem{code: :property_missing, message: "“Check” needs “Form to review” set"}] =
             Health.check(chain([form_node("Check", form: form)])).problems
  end

  test "a related form pointing at a position the tree has is fine; one it lacks is an error" do
    about = form_node("About")

    review_of = fn path ->
      form_node("Check",
        form:
          published_form("Check", %{
            "form_type" => "review",
            "form_type_property_values" => %{"source" => path}
          })
      )
    end

    assert Health.ok?(Health.check(chain([about, review_of.(about.id)])))

    assert [%Problem{code: :related_form_missing}] =
             Health.check(chain([about, review_of.(Ecto.UUID.generate())])).problems
  end

  test "a related form resolves across subflows, by path" do
    about = form_node("About")
    inner = chain([about], name: "Application")
    step = subflow_node("Application", inner.flow.id)

    check =
      form_node("Check",
        form:
          published_form("Check", %{
            "form_type" => "review",
            "form_type_property_values" => %{"source" => "#{step.id}/#{about.id}"}
          })
      )

    outer = chain([step, check], label: "subflows", subflows: %{step.id => inner})

    # A "subflows" flow holding a form step is not a shape a save allows,
    # but the check does not police flavor — that is the save's job
    assert Health.ok?(Health.check(outer))
  end

  test "a flow type the host does not offer, and its stale perspectives, are warnings" do
    health = Health.check(chain([form_node("Name")], properties: %{"form_flow_type" => "gone"}))
    assert codes(health) == [:unknown_type]

    types = [
      %FormFlow.Config.Flows.Type{
        id: "wizard_in_order",
        module: FormFlow.Web.Components.Flows.Types.WizardInOrder,
        name: "Wizard",
        perspectives: [%Perspective{id: "applicant", name: "Applicant"}]
      }
    ]

    health =
      Health.check(
        chain([form_node("Name")], properties: %{"perspectives" => ["applicant", "auditor"]}),
        flow_types: types
      )

    assert [
             %Problem{
               code: :stale_perspectives,
               message: "This flow is for “auditor”, which its type no longer declares"
             }
           ] =
             health.problems
  end

  test "a required flow property left unset is an error" do
    types = [
      %FormFlow.Config.Flows.Type{
        id: "wizard_in_order",
        module: FormFlow.Web.Components.Flows.Types.WizardInOrder,
        name: "Wizard",
        properties: [%Property{id: "deadline", name: "Deadline", type: :text, required: true}]
      }
    ]

    assert codes(Health.check(chain([form_node("Name")]), flow_types: types)) == [
             :property_missing
           ]

    filled = %{"form_flow_type_property_values" => %{"deadline" => "2026-12-31"}}

    assert Health.ok?(
             Health.check(chain([form_node("Name")], properties: filled), flow_types: types)
           )
  end

  test "a subflows flow has no flow type to check" do
    inner = chain([form_node("Name")], name: "Application")
    step = subflow_node("Application", inner.flow.id)

    outer =
      chain([step],
        label: "subflows",
        subflows: %{step.id => inner},
        properties: %{"form_flow_type" => "gone"}
      )

    assert Health.ok?(Health.check(outer))
  end

  # --- subflows ----------------------------------------------------------------

  test "problems inside a subflow are found, named by the way down, and carry the subflow's id and the path" do
    inner = chain([form_node("Check", form: draft_only_form("Check"))], name: "Review")
    step = subflow_node("Review", inner.flow.id)
    outer = chain([step], label: "subflows", subflows: %{step.id => inner})

    health = Health.check(outer)

    assert [%Problem{code: :form_not_published, message: message, flow_id: flow_id, path: path}] =
             health.problems

    assert message == "“Review / Check” has no published version — users cannot start it"
    assert flow_id == inner.flow.id
    assert path == [step.id, Enum.at(inner.nodes, 1).id]
  end

  test "a flow-level problem inside a subflow names the subflow, and carries the step's path" do
    start = start_node()
    stop = end_node()
    inner = tree([start, stop], [], name: "Review")
    step = subflow_node("Review", inner.flow.id)
    outer = chain([step], label: "subflows", subflows: %{step.id => inner})

    health = Health.check(outer)

    assert [
             %Problem{
               code: :end_unreachable,
               message: "Review does not connect Start to End",
               path: path,
               node_id: nil
             }
             | _
           ] =
             health.problems

    assert path == [step.id]
  end

  test "a subflow step with nothing behind it is an error, and an unconnected one is not descended into" do
    dangling = subflow_node("Dangling", Ecto.UUID.generate())
    broken_inner = tree([], [], name: "Broken")
    loose = subflow_node("Loose", broken_inner.flow.id)
    %{nodes: nodes, relationships: edges} = chain([dangling], label: "subflows")

    health =
      Health.check(
        tree(nodes ++ [loose], edges, label: "subflows", subflows: %{loose.id => broken_inner})
      )

    assert codes(health) == [:subflow_missing, :unconnected]
  end

  # --- the summary -------------------------------------------------------------

  test "problems sort worst first and are counted by level" do
    loose = form_node("Loose")
    changed = %Version{status: "draft", definition: %{"changed" => true}}
    form = published_form("Name")
    name = form_node("Name", form: %{form | versions: form.versions ++ [changed]})
    unpublished = form_node("New", form: draft_only_form("New"))
    %{nodes: nodes, relationships: edges} = chain([name, unpublished])

    health = Health.check(tree(nodes ++ [loose], edges))

    assert Enum.map(health.problems, & &1.level) == [:error, :warning, :info]
    assert health.counts == %{error: 1, warning: 1, info: 1, ignored: 0}
    assert health.level == :error
  end

  # --- ignored problems --------------------------------------------------------

  test "an ignored problem is listed last, marked, and left out of the level and counts" do
    loose = form_node("Loose")
    unpublished = form_node("New", form: draft_only_form("New"))
    %{nodes: nodes, relationships: edges} = chain([unpublished])

    ignored = %{
      "code" => "form_not_published",
      "path" => [unpublished.id],
      "user_id" => "demo-admin",
      "ignored_at" => "2026-09-08T10:00:00Z"
    }

    health =
      Health.check(tree(nodes ++ [loose], edges, properties: %{"ignored_problems" => [ignored]}))

    assert [
             %Problem{code: :unconnected, ignored: nil},
             %Problem{
               code: :form_not_published,
               ignored: %{user_id: "demo-admin", ignored_at: at}
             }
           ] = health.problems

    assert at == ~U[2026-09-08 10:00:00Z]
    assert health.level == :warning
    assert health.counts == %{error: 0, warning: 1, info: 0, ignored: 1}
    assert [%Problem{code: :unconnected}] = Health.open(health)
    assert [%Problem{code: :form_not_published}] = Health.ignored(health)
    assert Health.at(health, :error) == []
    refute Health.ok?(health)
  end

  test "a flow whose every problem is ignored is ok" do
    unpublished = form_node("New", form: draft_only_form("New"))
    ignored = %{"code" => "form_not_published", "path" => [unpublished.id], "user_id" => nil}

    health = Health.check(chain([unpublished], properties: %{"ignored_problems" => [ignored]}))

    assert Health.ok?(health)
    assert health.level == :ok
    assert [%Problem{ignored: %{user_id: nil, ignored_at: nil}}] = health.problems
  end

  test "a record for a problem the check no longer finds marks nothing" do
    stale = %{"code" => "unconnected", "path" => [Ecto.UUID.generate()]}

    health =
      Health.check(chain([form_node("Name")], properties: %{"ignored_problems" => [stale]}))

    assert health.problems == []
    assert health.counts.ignored == 0
  end
end
