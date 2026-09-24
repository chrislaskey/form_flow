defmodule Demo.FormFlowNextPositionsTest do
  @moduledoc """
  Exercises the cache of where a journey's flow is open -
  `FormFlow.Data.Instances.Flows.update_next_positions/2`, the columns it
  writes on the journey row and the rows it writes in
  `form_flow_instance_next_positions` - against a real database
  (`archive/plans/next-position.md` §5.2, §5.3).

  Every path that changes a form instance's status is proven to leave the
  row **and** the table right: creation, start, submit, reopen, completing the
  journey, deletion, and the `refresh: false` opt-out. Two shapes get their
  own tests because they are where a single cached position would lie: a
  form behind a step another step still shuts, and a flow worked in any
  order, where every unfinished form is open at once.
  """

  use Demo.DataCase, async: false

  import Ecto.Query

  alias FormFlow.Data.Instances
  alias FormFlow.Data.Instances.Flow.NextPosition
  alias FormFlow.Data.Repo, as: FormFlowRepo
  alias FormFlow.Data.Templates.Flow
  alias FormFlow.Data.Templates.Flows
  alias FormFlow.Data.Templates.Forms

  describe "a journey of one in-order flow: Start → Name → Address → End" do
    test "creation writes the first form as next, no forms done, and one row" do
      %{journey: journey, forms: [name, _address]} = flow_of_two()

      assert journey.next_path == [name.id]
      assert journey.next_node_id == name.id
      assert journey.completed_forms == 0
      assert journey.forms_total == 2
      assert %DateTime{} = journey.next_computed_at

      assert open_paths(journey) == [[name.id]]
    end

    test "starting the first form leaves it next; submitting it moves next to the second" do
      %{journey: journey, forms: [name, address]} = flow_of_two()

      {:ok, _started} = Instances.Forms.update_status(journey, [name.id], :in_progress)
      journey = reload(journey)
      assert journey.next_path == [name.id]
      assert journey.completed_forms == 0
      assert open_paths(journey) == [[name.id]]

      {:ok, _done} = Instances.Forms.update_status(journey, [name.id], :completed, data: %{})
      journey = reload(journey)
      assert journey.next_path == [address.id]
      assert journey.next_node_id == address.id
      assert journey.completed_forms == 1
      assert journey.forms_total == 2
      assert open_paths(journey) == [[address.id]]
    end

    test "submitting the last form leaves nothing actionable: null columns, no rows, counts final" do
      %{journey: journey, forms: [name, address]} = flow_of_two()

      complete(journey, [name.id])
      complete(journey, [address.id])

      journey = reload(journey)
      assert journey.next_path == nil
      assert journey.next_node_id == nil
      assert journey.completed_forms == 2
      assert journey.forms_total == 2
      assert open_paths(journey) == []
    end

    test "reopening a completed form makes that form next again" do
      %{journey: journey, forms: [name, address]} = flow_of_two()

      complete(journey, [name.id])
      complete(journey, [address.id])

      {:ok, _reopened} = Instances.Forms.update_status(journey, [name.id], :in_progress)

      journey = reload(journey)
      assert journey.next_path == [name.id]
      assert journey.completed_forms == 1
      assert open_paths(journey) == [[name.id]]
    end

    test "a no-op status change refreshes nothing" do
      %{journey: journey, forms: [name, _address]} = flow_of_two()

      {:ok, _started} = Instances.Forms.update_status(journey, [name.id], :in_progress)
      computed_at = reload(journey).next_computed_at

      # Already in progress: the position does not move and nothing is rewritten
      {:ok, _same} = Instances.Forms.update_status(journey, [name.id], :in_progress)
      assert reload(journey).next_computed_at == computed_at
    end

    test "refresh: false leaves the cache where it was, and the caller's own call catches it up" do
      %{journey: journey, forms: [name, address]} = flow_of_two()

      {:ok, _started} = Instances.Forms.update_status(journey, [name.id], :in_progress)

      {:ok, _done} =
        Instances.Forms.update_status(journey, [name.id], :completed, data: %{}, refresh: false)

      # Stale on purpose: still says the first form
      stale = reload(journey)
      assert stale.next_path == [name.id]
      assert stale.completed_forms == 0
      assert open_paths(stale) == [[name.id]]

      {:ok, fresh} = Instances.Flows.update_next_positions(stale)
      assert fresh.next_path == [address.id]
      assert fresh.completed_forms == 1
      assert open_paths(fresh) == [[address.id]]
    end

    test "completing the journey empties the cache, whatever the forms say" do
      %{journey: journey, forms: [name, _address]} = flow_of_two()

      {:ok, completed} = Instances.Flows.complete(journey)

      assert completed.next_path == nil
      assert completed.next_node_id == nil
      # The counts still say how far the forms got
      assert completed.completed_forms == 0
      assert completed.forms_total == 2
      assert open_paths(completed) == []

      # And a later refresh keeps it empty: a completed journey is open nowhere
      {:ok, again} = Instances.Flows.update_next_positions(completed)
      assert again.next_path == nil
      assert open_paths(again) == []
      refute [name.id] in Enum.map(all_rows(), & &1.path)
    end

    test "deleting the journey takes its rows with it" do
      %{journey: journey} = flow_of_two()
      assert length(rows_of(journey)) == 1

      {:ok, _deleted} = Instances.Flows.delete_instance(journey)

      assert rows_of(journey) == []
    end

    test "the row carries the position, its last node, and the journey's tenant" do
      %{journey: journey, forms: [name, _address]} = flow_of_two(tenant_id: "acme")

      assert [row] = rows_of(journey)
      assert row.path == [name.id]
      assert row.node_id == name.id
      assert row.tenant_id == "acme"
    end

    test "creating with refresh: false leaves the columns null and the table empty" do
      {:ok, flow} = Flows.create(%{name: "Application", status: "open"})
      build_node(flow, ["Start"], "Start")

      {:ok, journey} =
        Instances.Flows.create(%{template_flow_id: flow.id, user_id: "dog_owner"}, refresh: false)

      assert journey.next_path == nil
      assert journey.next_computed_at == nil
      assert rows_of(journey) == []
    end
  end

  describe "a journey of one any-order flow" do
    test "every unfinished form is open at once: a row per form, the first of them next" do
      %{journey: journey, forms: [name, address]} = flow_of_two("wizard_any_order")

      assert journey.next_path == [name.id]
      assert open_paths(journey) == [[name.id], [address.id]]

      # Skipping ahead and finishing the second leaves the first as the one row
      complete(journey, [address.id])

      journey = reload(journey)
      assert journey.next_path == [name.id]
      assert journey.completed_forms == 1
      assert open_paths(journey) == [[name.id]]
    end
  end

  describe "a journey of a subflows flow: Start → Documents → Interview → End" do
    test "in order, only the open step's first form is open; the shut step's forms are not" do
      %{journey: journey, documents: documents, interview: interview} = nested_flow()

      [first, second] = documents.forms
      [question, _answer] = interview.forms

      # Two segments deep: the step, then the form
      assert journey.next_path == [documents.node.id, first.id]
      assert journey.next_node_id == first.id
      assert journey.forms_total == 4
      assert open_paths(journey) == [[documents.node.id, first.id]]

      complete(journey, [documents.node.id, first.id])
      complete(journey, [documents.node.id, second.id])

      journey = reload(journey)
      assert journey.next_path == [interview.node.id, question.id]
      assert journey.completed_forms == 2
      assert open_paths(journey) == [[interview.node.id, question.id]]
    end

    test "in any order, the first form of every unfinished step is open at once" do
      %{journey: journey, documents: documents, interview: interview} =
        nested_flow(%{"flow_type" => "any_order"})

      [first, _second] = documents.forms
      [question, _answer] = interview.forms

      assert journey.next_path == [documents.node.id, first.id]

      assert open_paths(journey) == [
               [documents.node.id, first.id],
               [interview.node.id, question.id]
             ]
    end
  end

  describe "update_next_positions/2 on its own" do
    test "takes a loaded tree, reads only narrow form instance rows, and returns the journey" do
      %{journey: journey, flow: flow, forms: [name, _address]} = flow_of_two()
      tree = Flows.resolve_tree(flow.id)

      {:ok, written} = Instances.Flows.update_next_positions(journey, tree: tree)

      assert %Instances.Flow{} = written
      assert written.id == journey.id
      assert written.next_path == [name.id]
    end

    test "a host's flow types decide the order rule" do
      # The demo's own types list carries the library's; a list holding only
      # the any-order wizard makes every "forms" flow any-order
      %{journey: journey, forms: [name, address]} = flow_of_two()

      any_order =
        Enum.filter(FormFlow.Config.Flows.Type.defaults(), &(&1.id == "wizard_any_order"))

      {:ok, written} = Instances.Flows.update_next_positions(journey, flow_types: any_order)

      assert open_paths(written) == [[name.id], [address.id]]
    end
  end

  describe "the sweep: update_next_positions/2 on a Templates.Flow" do
    test "rewrites every open journey of the root against the edited tree, and skips completed ones" do
      %{flow: flow, forms: [name, address]} = flow_of_two()
      first = start_flow(flow, [])
      second = start_flow(flow, [])
      done = start_flow(flow, [])
      {:ok, done} = Instances.Flows.complete(done)

      complete(second, [name.id])

      # The template changes under them: a form is added before Name, so
      # the flow is open there for a journey that has not started Name
      {:ok, flow} = Flows.get(flow.id) |> then(&{:ok, &1})
      first_node = Enum.find(flow.nodes, &("Start" in &1.labels))
      intro = build_form_node(flow, "Intro")
      FormFlowRepo.delete_all(from(r in Flow.Relationship, where: r.source_id == ^first_node.id))
      edge(flow, first_node, intro)
      edge(flow, intro, name)

      # Stale until swept
      assert reload(first).next_path == [name.id]

      # Three open journeys: the fixture's own, `first`, and `second`
      assert {:ok, 3} = Instances.Flows.update_next_positions(flow)

      first = reload(first)
      assert first.next_path == [intro.id]
      assert first.forms_total == 3
      assert open_paths(first) == [[intro.id]]

      # Name is done, so both Intro (nothing before it) and Address (behind
      # Name alone) are open; Intro, first in flow order, is next
      second = reload(second)
      assert second.next_path == [intro.id]
      assert second.completed_forms == 1
      assert open_paths(second) == [[intro.id], [address.id]]

      # The completed journey was not touched: its counts still say two forms
      done = reload(done)
      assert done.forms_total == 2
      assert done.next_path == nil
    end

    test "a subflow finds its root; the count is the journeys rewritten" do
      %{journey: journey, documents: documents} = nested_flow()

      assert {:ok, 1} = Instances.Flows.update_next_positions(documents.flow)
      assert reload(journey).next_computed_at != journey.next_computed_at
    end

    test "works in chunks: more journeys than one chunk holds all get rewritten" do
      %{flow: flow, forms: [name, _address]} = flow_of_two()
      journeys = for _n <- 1..205, do: start_flow(flow, [])

      FormFlowRepo.update_all(from(i in Instances.Flow), set: [next_path: nil, next_node_id: nil])
      FormFlowRepo.delete_all(from(p in NextPosition))

      # 205 plus the fixture's own journey: two chunks
      assert {:ok, 206} = Instances.Flows.update_next_positions(flow)

      for journey <- Enum.take_random(journeys, 5) do
        assert reload(journey).next_path == [name.id]
        assert open_paths(journey) == [[name.id]]
      end

      assert length(all_rows()) == 206
    end
  end

  describe "two runs overlapping" do
    # A slow run of the tree as it was must not land its answer on top of a
    # newer run's. `next_computed_at` is set once per run, before it
    # reads anything, and the write refuses a row a newer run already wrote:
    # last run *started* wins, not last finished. The newer run is simulated
    # by writing the row's `next_computed_at` as it would have.

    test "a run started before the row's `next_computed_at` writes neither the columns nor the rows" do
      %{journey: journey, forms: [name, address]} = flow_of_two()

      # A newer run got there first: the row carries its `next_computed_at` and its answer
      newer = DateTime.add(DateTime.utc_now(), 60, :second)

      FormFlowRepo.update_all(
        from(i in Instances.Flow, where: i.id == ^journey.id),
        set: [next_path: [address.id], next_node_id: address.id, next_computed_at: newer]
      )

      FormFlowRepo.delete_all(from(p in NextPosition, where: p.instance_flow_id == ^journey.id))

      FormFlowRepo.insert_all(NextPosition, [
        %{
          id: Ecto.UUID.generate(),
          instance_flow_id: journey.id,
          path: [address.id],
          node_id: address.id,
          tenant_id: journey.tenant_id,
          inserted_at: newer,
          updated_at: newer
        }
      ])

      # The older run derives [name] and tries to write it
      {:ok, _returned} = Instances.Flows.update_next_positions(reload(journey))

      kept = reload(journey)

      assert kept.next_path == [address.id], "the newer run's answer was overwritten"
      assert kept.next_computed_at == newer
      assert open_paths(kept) == [[address.id]], "the newer run's rows were replaced"
      refute name.id in Enum.map(rows_of(kept), & &1.node_id)
    end

    test "a run started after the row's `next_computed_at` writes as usual" do
      %{journey: journey, forms: [name, _address]} = flow_of_two()

      older = DateTime.add(DateTime.utc_now(), -60, :second)

      FormFlowRepo.update_all(
        from(i in Instances.Flow, where: i.id == ^journey.id),
        set: [next_path: [], next_node_id: nil, next_computed_at: older]
      )

      {:ok, _written} = Instances.Flows.update_next_positions(reload(journey))

      written = reload(journey)

      assert written.next_path == [name.id]
      assert DateTime.compare(written.next_computed_at, older) == :gt
      assert open_paths(written) == [[name.id]]
    end

    test "the sweep skips the journeys a newer run already wrote and rewrites the rest" do
      %{flow: flow, forms: [name, address]} = flow_of_two()
      guarded = start_flow(flow, [])
      ordinary = start_flow(flow, [])

      newer = DateTime.add(DateTime.utc_now(), 60, :second)

      FormFlowRepo.update_all(
        from(i in Instances.Flow, where: i.id == ^guarded.id),
        set: [next_path: [address.id], next_node_id: address.id, next_computed_at: newer]
      )

      {:ok, count} = Instances.Flows.update_next_positions(Flows.get(flow.id))

      # Every open journey was visited - `flow_of_two/0` started one too.
      # The count is journeys read, not journeys written: the guard decides
      # who is written, and a skipped journey is not a failure.
      assert count == 3

      assert reload(guarded).next_path == [address.id]
      assert reload(guarded).next_computed_at == newer
      assert reload(ordinary).next_path == [name.id]
    end
  end

  describe "narrow_next_position/3" do
    test "lists a journey once however many of the nodes it is open at, filters the tenant, and stacks" do
      %{flow: flow, journey: acme, forms: [name, address]} =
        flow_of_two("wizard_any_order", tenant_id: "acme")

      other = start_flow(flow, tenant_id: "other")
      nodes = [name.id, address.id]

      # Open at both nodes, one row
      listed = FormFlowRepo.all(Instances.Flows.narrow_next_position(Instances.Flow, nodes))
      assert Enum.map(listed, & &1.id) |> Enum.sort() == Enum.sort([acme.id, other.id])

      # The tenant inside the filter
      assert [%{id: id}] =
               FormFlowRepo.all(
                 Instances.Flows.narrow_next_position(Instances.Flow, nodes, "acme")
               )

      assert id == acme.id

      # Stacked twice, and on a query that already narrows: no alias to collide
      stacked =
        Instances.Flows.list_query(tenant_id: "acme")
        |> Instances.Flows.narrow_next_position([name.id])
        |> Instances.Flows.narrow_next_position([address.id], "acme")

      assert [%{id: ^id}] = FormFlowRepo.all(stacked)

      # Nothing matches nothing
      assert FormFlowRepo.all(Instances.Flows.narrow_next_position(Instances.Flow, [])) == []
    end
  end

  describe "staleness" do
    test "next_positions_stale?/2: no refresh yet, or a flow of the tree saved since" do
      %{journey: journey, flow: flow} = flow_of_two()
      tree_at = Flows.tree_updated_at(Flows.resolve_tree(flow.id))

      refute Instances.Flows.next_positions_stale?(journey, tree_at)
      assert Instances.Flows.next_positions_stale?(%{journey | next_computed_at: nil}, tree_at)
      refute Instances.Flows.next_positions_stale?(journey, nil)

      # The flow is saved after the refresh
      later = DateTime.add(journey.next_computed_at, 1, :second)
      assert Instances.Flows.next_positions_stale?(journey, later)
    end

    test "tree_updated_at/1 is the newest save anywhere in the tree, a subflow's included" do
      %{root: root, documents: documents} = nested_flow()
      tree = Flows.resolve_tree(root.id)

      assert Flows.tree_updated_at(tree) == Flows.tree_updated_at(tree)

      later = DateTime.add(Flows.tree_updated_at(tree), 60, :second)

      FormFlowRepo.update_all(from(f in Flow, where: f.id == ^documents.flow.id),
        set: [updated_at: later]
      )

      assert Flows.tree_updated_at(Flows.resolve_tree(root.id)) == later
      assert Flows.tree_updated_at(nil) == nil
    end
  end

  # ── fixtures ────────────────────────────────────────────────────────────

  # Start → Name → Address → End, one "forms" flow of the given type, and a
  # journey of it. `opts[:tenant_id]` sets the journey's tenant.
  describe "Instances.Flows.complete/2 records the template" do
    test "writes the tree and the form positions as they stand, once" do
      %{flow: flow, journey: journey, forms: [name, address]} = flow_of_two()
      _ = complete(journey, [name.id])

      {:ok, completed} = Instances.Flows.complete(journey)
      snapshot = completed.completed_template_snapshot

      assert snapshot["tree"]["flow"]["id"] == flow.id
      assert snapshot["tree"]["flow"]["name"] == "Application"
      assert snapshot["tree"]["subflows"] == %{}
      assert length(snapshot["tree"]["nodes"]) == 4
      assert length(snapshot["tree"]["relationships"]) == 3

      form_node = Enum.find(snapshot["tree"]["nodes"], &(&1["id"] == name.id))
      assert form_node["form_id"] == name.form_id
      assert form_node["labels"] == ["Form"]

      [name_instance] = Instances.Flows.form_instances(journey)

      assert snapshot["positions"] == [
               %{
                 "path" => [name.id],
                 "label" => "Name",
                 "status" => "completed",
                 "instance_id" => name_instance.id,
                 "version_id" => name_instance.template_form_version_id
               },
               %{
                 "path" => [address.id],
                 "label" => "Address",
                 "status" => "available",
                 "instance_id" => nil,
                 "version_id" => nil
               }
             ]

      # Completing a completed journey is a no-op: the snapshot stays
      {:ok, again} = Instances.Flows.complete(completed)
      assert again.completed_template_snapshot == snapshot
      assert reload(journey).completed_template_snapshot == snapshot
    end

    test "a later template edit moves the derivation, not the snapshot" do
      %{flow: flow, journey: journey, forms: [_name, address]} = flow_of_two()
      {:ok, completed} = Instances.Flows.complete(journey)
      snapshot = completed.completed_template_snapshot
      assert length(snapshot["positions"]) == 2

      extra = build_form_node(flow, "Extra")
      edge(flow, address, extra)

      assert map_size(Instances.Flows.progress(reload(journey))) == 5
      assert reload(journey).completed_template_snapshot == snapshot
    end

    test "null on a journey still in progress" do
      %{journey: journey} = flow_of_two()
      assert reload(journey).completed_template_snapshot == nil
    end
  end

  defp flow_of_two(type_or_opts \\ nil)

  defp flow_of_two(opts) when is_list(opts), do: flow_of_two(nil, opts)
  defp flow_of_two(type), do: flow_of_two(type, [])

  defp flow_of_two(type, opts) do
    {:ok, flow} =
      Flows.create(%{name: "Application", properties: properties(type), status: "open"})

    first_node = build_node(flow, ["Start"], "Start")
    name = build_form_node(flow, "Name")
    address = build_form_node(flow, "Address")
    last_node = build_node(flow, ["End"], "End")

    edge(flow, first_node, name)
    edge(flow, name, address)
    edge(flow, address, last_node)

    %{flow: flow, journey: start_flow(flow, opts), forms: [name, address]}
  end

  # Start → Documents → Interview → End, each step a private child flow of
  # two forms; `properties` type the root
  defp nested_flow(properties \\ %{}) do
    {:ok, root} =
      Flows.create(%{
        name: "Onboarding",
        label: "subflows",
        status: "open",
        properties: properties
      })

    documents = owned_flow_of_two(root, "Documents")
    interview = owned_flow_of_two(root, "Interview")

    first_node = build_node(root, ["Start"], "Start")
    documents_node = build_node(root, ["Subflow"], "Documents", %{subflow_id: documents.flow.id})
    interview_node = build_node(root, ["Subflow"], "Interview", %{subflow_id: interview.flow.id})
    last_node = build_node(root, ["End"], "End")

    edge(root, first_node, documents_node)
    edge(root, documents_node, interview_node)
    edge(root, interview_node, last_node)

    %{
      root: root,
      journey: start_flow(root, []),
      documents: Map.put(documents, :node, documents_node),
      interview: Map.put(interview, :node, interview_node)
    }
  end

  # A private child flow of `root`: Start → First → Second → End
  defp owned_flow_of_two(root, name) do
    {:ok, flow} = Flows.create(%{name: name, label: "forms", owner_flow_id: root.id})

    first_node = build_node(flow, ["Start"], "Start")
    first = build_form_node(flow, "First")
    second = build_form_node(flow, "Second")
    last_node = build_node(flow, ["End"], "End")

    edge(flow, first_node, first)
    edge(flow, first, second)
    edge(flow, second, last_node)

    %{flow: flow, forms: [first, second]}
  end

  defp properties(nil), do: %{}
  defp properties(type), do: %{"flow_type" => type}

  defp start_flow(flow, opts) do
    {:ok, journey} =
      Instances.Flows.create(%{
        template_flow_id: flow.id,
        user_id: "dog_owner",
        tenant_id: Keyword.get(opts, :tenant_id)
      })

    journey
  end

  # Starts and submits the form at `path`
  defp complete(journey, path) do
    {:ok, _opened} = Instances.Forms.update_status(journey, path, :in_progress)
    {:ok, completed} = Instances.Forms.update_status(journey, path, :completed, data: %{})

    completed
  end

  defp reload(journey), do: Instances.Flows.get(journey.id)

  # The journey's rows in flow order - the order the refresh wrote them,
  # which `inserted_at` shares, so the id breaks the tie the way the rows
  # were listed
  defp rows_of(journey) do
    FormFlowRepo.all(
      from(p in NextPosition,
        where: p.instance_flow_id == ^journey.id,
        order_by: [asc: p.inserted_at]
      )
    )
  end

  defp all_rows, do: FormFlowRepo.all(from(p in NextPosition))

  # The journey's open positions as the table holds them, in flow order
  defp open_paths(journey) do
    journey
    |> rows_of()
    |> Enum.map(& &1.path)
    |> Enum.sort_by(&flow_order(&1, journey))
  end

  # Where a path sits in the tree's flow order (`FlowProgress.forms/2`)
  defp flow_order(path, journey) do
    tree = Flows.resolve_tree(journey.template_flow_id)

    tree
    |> FormFlow.Data.Instances.FlowProgress.forms([])
    |> Enum.find_index(&(&1.path == path))
  end

  defp build_node(flow, labels, label, attrs \\ %{}) do
    attrs =
      Map.merge(
        %{flow_id: flow.id, labels: labels, properties: %{"data" => %{"label" => label}}},
        attrs
      )

    {:ok, node} = FormFlowRepo.insert(Flow.Node.changeset(%Flow.Node{}, attrs))

    node
  end

  defp edge(flow, source, target) do
    {:ok, _relationship} =
      FormFlowRepo.insert(
        Flow.Relationship.changeset(%Flow.Relationship{}, %{
          flow_id: flow.id,
          source_id: source.id,
          target_id: target.id,
          label: "CONNECTS_TO"
        })
      )
  end

  # A published form with one text question, "name"
  defp build_form_node(flow, label) do
    {:ok, form} = Forms.create(%{name: "#{label} #{System.unique_integer([:positive])}"})
    [draft] = form.versions

    definition = %{"elements" => [%{"type" => "text", "name" => "name", "title" => "Name"}]}
    {:ok, draft} = Forms.update_draft(draft, %{definition: definition})
    {:ok, _published} = Forms.update_status(draft, :published)

    build_node(flow, ["Form"], label, %{form_id: form.id})
  end
end
