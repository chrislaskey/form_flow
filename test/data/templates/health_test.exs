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
  alias FormFlow.Data.Templates.Flows.Health.Entry
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

  defp codes(%Health{entries: entries}), do: Enum.map(entries, & &1.code)

  # --- a healthy flow ----------------------------------------------------------

  test "a connected flow of published forms has nothing to report" do
    health = Health.check(chain([form_node("Name"), form_node("Address")]))

    assert %Health{level: :ok, entries: [], counts: %{error: 0, warning: 0, info: 0}} = health
    assert Health.ok?(health)
    assert health.checks_run > 0
    assert Health.passing(health) == health.checks_run
  end

  test "checks are counted as they run, entries included" do
    start = start_node()
    stop = end_node()

    # A "subflows" flow has no type to check, so the count is structure alone:
    # Start and End looked for, the walk from one to the other, the steps on
    # it, each of the two nodes for being connected, Start for leading on
    health = Health.check(tree([start, stop], [edge(start, stop)], label: "subflows"))

    assert codes(health) == [:no_steps]
    assert health.checks_run == 7
    assert Health.passing(health) == 6
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
             %Entry{message: "This flow does not connect Start to End", node_id: nil, path: []}
             | _
           ] =
             health.entries

    # End itself is what is unconnected — not the chain leading towards it
    assert [%Entry{code: :unconnected, node_id: end_id}] = Health.at(health, :warning)
    assert end_id == stop.id
  end

  test "a node no Start reaches is a warning, and what is behind it goes unchecked" do
    loose = form_node("Loose", form: draft_only_form("Loose"))
    %{nodes: nodes, relationships: edges} = chain([form_node("Name")])

    health = Health.check(tree(nodes ++ [loose], edges))

    assert [%Entry{level: :warning, code: :unconnected, node_id: node_id, path: [path_id]}] =
             health.entries

    assert node_id == loose.id and path_id == loose.id
    assert health.level == :warning
  end

  test "a reachable node nothing follows is a dead end" do
    %{nodes: nodes, relationships: edges} = chain([form_node("Name")])
    [start | _rest] = nodes
    aside = form_node("Aside")

    health = Health.check(tree(nodes ++ [aside], edges ++ [edge(start, aside)]))

    assert [%Entry{code: :dead_end, message: "“Aside” leads nowhere — nothing follows it"}] =
             health.entries
  end

  test "Start wired straight to End is a warning" do
    assert codes(Health.check(chain([]))) == [:no_steps]
  end

  # --- forms -----------------------------------------------------------------

  test "a connected form with no published version is an error" do
    health = Health.check(chain([form_node("Name", form: draft_only_form("Name"))]))

    assert [
             %Entry{
               level: :error,
               code: :form_not_published,
               message: "“Name” has no published version — users cannot start it"
             }
           ] = health.entries
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

    assert [%Entry{level: :info, code: :unpublished_changes}] = health.entries
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
             %Entry{
               code: :unknown_type,
               message: "“Name” uses the form type “gone”, which is not offered"
             }
           ] =
             Health.check(chain([form_node("Name", form: form)])).entries
  end

  test "a required form property left unset is an error — the Review type's source" do
    form = published_form("Check", %{"form_type" => "review"})

    assert [%Entry{code: :property_missing, message: "“Check” needs “Form to review” set"}] =
             Health.check(chain([form_node("Check", form: form)])).entries
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

    assert [%Entry{code: :related_form_missing, message: message}] =
             Health.check(chain([about, review_of.(Ecto.UUID.generate())])).entries

    assert message == "“Check” points “Form to review” at a form that is no longer in this flow"
  end

  test "a related form the tree has but no Start reaches is as missing as one deleted" do
    # The runtime looks the related form up among the connected positions,
    # so the reviewer would find nothing; the message says which fix applies
    loose = form_node("About")

    check =
      form_node("Check",
        form:
          published_form("Check", %{
            "form_type" => "review",
            "form_type_property_values" => %{"source" => loose.id}
          })
      )

    %{nodes: nodes, relationships: edges} = chain([check])
    health = Health.check(tree(nodes ++ [loose], edges))

    assert [
             %Entry{code: :related_form_missing, message: message},
             %Entry{code: :unconnected}
           ] = health.entries

    assert message == "“Check” points “Form to review” at a form no Start reaches"
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
             %Entry{
               code: :stale_perspectives,
               message: "This flow is for “auditor”, which its type no longer declares"
             }
           ] =
             health.entries
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

  test "entries inside a subflow are found, named by the way down, and carry the subflow's id and the path" do
    inner = chain([form_node("Check", form: draft_only_form("Check"))], name: "Review")
    step = subflow_node("Review", inner.flow.id)
    outer = chain([step], label: "subflows", subflows: %{step.id => inner})

    health = Health.check(outer)

    assert [%Entry{code: :form_not_published, message: message, flow_id: flow_id, path: path}] =
             health.entries

    assert message == "“Review / Check” has no published version — users cannot start it"
    assert flow_id == inner.flow.id
    assert path == [step.id, Enum.at(inner.nodes, 1).id]
  end

  test "a flow-level entry inside a subflow names the subflow, and carries the step's path" do
    start = start_node()
    stop = end_node()
    inner = tree([start, stop], [], name: "Review")
    step = subflow_node("Review", inner.flow.id)
    outer = chain([step], label: "subflows", subflows: %{step.id => inner})

    health = Health.check(outer)

    assert [
             %Entry{
               code: :end_unreachable,
               message: "Review does not connect Start to End",
               path: path,
               node_id: nil
             }
             | _
           ] =
             health.entries

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

  # --- what an entry carries ---------------------------------------------------

  test "every entry says where it is, why it matters, and what to do" do
    inner = tree([start_node(), end_node()], [], name: "Review")
    step = subflow_node("Review", inner.flow.id)
    loose = form_node("Loose")
    %{nodes: nodes, relationships: edges} = chain([step], label: "subflows")

    health =
      Health.check(
        tree(nodes ++ [loose], edges, label: "subflows", subflows: %{step.id => inner})
      )

    # A step by the way down; a subflow by its own; the root by nothing, since
    # whatever lists the report names it
    assert %Entry{code: :end_unreachable, subject: "Review"} = Health.at(health, :error) |> hd()
    assert %Entry{code: :unconnected, subject: "Loose"} = Health.at(health, :warning) |> hd()
    assert %Entry{code: :no_start, subject: nil} = Health.check(tree([], [])).entries |> hd()

    for entry <- health.entries do
      assert entry.explanation == Entry.explanation(entry.code)
      assert entry.fix == Entry.fix(entry.code)
    end

    # Words of its own for every code — not the general sentence an unlisted
    # code falls back to, which keeps a save from refusing over a missing
    # paragraph
    for code <- Entry.codes() do
      assert String.length(Entry.explanation(code)) > 40
      assert Entry.explanation(code) != Entry.explanation(:not_a_code)
      assert String.ends_with?(Entry.fix(code), ".")
      assert Entry.fix(code) != Entry.fix(:not_a_code)
    end

    assert length(Entry.codes()) == 14
  end

  test "the checks emit every listed code, and no code the list lacks" do
    # One tree per code the other tests build alone; the set of codes that
    # come out of all of them is the set `Entry.codes/0` names, so a check
    # added without its code — which would take the fallback words — fails
    # here, and so does a listed code no check produces
    loose = form_node("Loose")
    unpublished = form_node("New", form: draft_only_form("New"))
    changed = %Version{status: "draft", definition: %{"changed" => true}}
    drafted = published_form("Drafted")
    drafted = form_node("Drafted", form: %{drafted | versions: drafted.versions ++ [changed]})
    no_form = build_node(["Form"], label: "Empty", form: nil)
    stale_type = form_node("Typed", form: published_form("Typed", %{"form_type" => "gone"}))
    review = form_node("Check", form: published_form("Check", %{"form_type" => "review"}))

    pointing =
      form_node("Pointing",
        form:
          published_form("Pointing", %{
            "form_type" => "review",
            "form_type_property_values" => %{"source" => Ecto.UUID.generate()}
          })
      )

    dangling = subflow_node("Dangling", Ecto.UUID.generate())
    dead = form_node("Dead")

    start = start_node()
    stop = end_node()

    %{nodes: nodes, relationships: edges} =
      chain([unpublished, drafted, no_form, stale_type, review, pointing])

    review_flow = %FormFlow.Config.Flows.Type{
      id: "review_flow",
      name: "Review",
      properties: [%Property{id: "source", name: "Form to review", required: true}],
      perspectives: []
    }

    trees = [
      tree([form_node("Alone")], []),
      tree([start, stop], []),
      tree([start, stop], [edge(start, stop)], label: "subflows"),
      tree([start, stop, dead], [edge(start, stop), edge(start, dead)]),
      tree(nodes ++ [loose], edges),
      chain([dangling], label: "subflows"),
      chain([], properties: %{"form_flow_type" => "gone"}),
      chain([], properties: %{"form_flow_type" => "review_flow", "perspectives" => ["nobody"]})
    ]

    emitted =
      trees
      |> Enum.flat_map(fn tree -> tree |> Health.check(flow_types: [review_flow]) |> codes() end)
      |> MapSet.new()

    assert MapSet.equal?(emitted, MapSet.new(Entry.codes()))
  end

  # --- ordering and counts -----------------------------------------------------

  test "entries sort worst first and are counted by level" do
    loose = form_node("Loose")
    changed = %Version{status: "draft", definition: %{"changed" => true}}
    form = published_form("Name")
    name = form_node("Name", form: %{form | versions: form.versions ++ [changed]})
    unpublished = form_node("New", form: draft_only_form("New"))
    %{nodes: nodes, relationships: edges} = chain([name, unpublished])

    health = Health.check(tree(nodes ++ [loose], edges))

    assert Enum.map(health.entries, & &1.level) == [:error, :warning, :info]
    assert health.counts == %{error: 1, warning: 1, info: 1, ignored: 0}
    assert health.level == :error
    assert Health.passing(health) == health.checks_run - 3
  end

  # --- the summary -------------------------------------------------------------

  test "the summary describes the whole tree: steps, subflows, distinct forms, perspectives, types" do
    shared = published_form("Owner contact")

    inner =
      chain([form_node("About"), form_node("Owner", form: shared)],
        name: "Application",
        properties: %{"perspectives" => ["applicant"], "form_flow_type" => "wizard_in_order"}
      )

    review =
      chain([form_node("Owner again", form: shared)],
        name: "Review",
        properties: %{"perspectives" => ["reviewer"]}
      )

    application = subflow_node("Application", inner.flow.id)
    review_step = subflow_node("Review", review.flow.id)
    loose = form_node("Loose")
    %{nodes: nodes, relationships: edges} = chain([application, review_step], label: "subflows")

    health =
      Health.check(
        tree(nodes ++ [loose], edges,
          label: "subflows",
          subflows: %{application.id => inner, review_step.id => review}
        )
      )

    assert health.summary == %{
             label: "subflows",
             steps: 6,
             subflows: 2,
             forms: 3,
             perspectives: ["applicant", "reviewer"],
             form_flow_types: ["wizard_in_order", nil]
           }
  end

  # --- ignored entries --------------------------------------------------------

  test "an ignored entry stays in its place, marked, and left out of the level and counts" do
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
      Health.check(
        tree(nodes ++ [loose], edges,
          properties: %{"_health_metadata" => %{"ignored_entries" => [ignored]}}
        )
      )

    # Level order as before: the ignored error keeps its place at the top
    assert [
             %Entry{
               code: :form_not_published,
               ignored: %{user_id: "demo-admin", ignored_at: at}
             },
             %Entry{code: :unconnected, ignored: nil}
           ] = health.entries

    assert at == ~U[2026-09-08 10:00:00Z]
    assert health.level == :warning
    assert health.counts == %{error: 0, warning: 1, info: 0, ignored: 1}
    assert [%Entry{code: :unconnected}] = Health.open(health)
    assert [%Entry{code: :form_not_published}] = Health.ignored(health)
    assert Health.at(health, :error) == []
    refute Health.ok?(health)
  end

  test "a flow whose every entry is ignored is ok" do
    unpublished = form_node("New", form: draft_only_form("New"))
    ignored = %{"code" => "form_not_published", "path" => [unpublished.id], "user_id" => nil}

    health =
      Health.check(
        chain([unpublished],
          properties: %{"_health_metadata" => %{"ignored_entries" => [ignored]}}
        )
      )

    assert Health.ok?(health)
    assert health.level == :ok
    assert [%Entry{ignored: %{user_id: nil, ignored_at: nil}}] = health.entries
  end

  test "a record for an entry the check no longer finds marks nothing" do
    stale = %{"code" => "unconnected", "path" => [Ecto.UUID.generate()]}

    health =
      Health.check(
        chain([form_node("Name")],
          properties: %{"_health_metadata" => %{"ignored_entries" => [stale]}}
        )
      )

    assert health.entries == []
    assert health.counts.ignored == 0
  end
end
