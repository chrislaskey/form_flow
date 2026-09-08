defmodule Demo.FormFlowFlowsTest do
  @moduledoc """
  Exercises `FormFlow.Data.Templates.Flows` and the flow schemas against a real database —
  the library's own tests stop at changesets, so this is where the V01 flow DDL
  (foreign keys, cascades, the unique relationship index) is proven to hold.
  """

  use Demo.DataCase, async: false

  alias FormFlow.Data.Repo, as: FormFlowRepo
  alias FormFlow.Data.Templates.Flow
  alias FormFlow.Data.Templates.Flows
  alias FormFlow.Data.Templates.Forms

  test "create, get, update, and delete a flow" do
    assert {:ok, %Flow{id: id}} = Flows.create()

    assert %Flow{id: ^id, nodes: [], relationships: []} = Flows.get(id)

    assert {:ok, %Flow{id: ^id}} = Flows.update(Flows.get(id), %{})

    assert {:ok, _} = Flows.delete(Flows.get(id))
    assert Flows.get(id) == nil
  end

  test "list returns flows with counts, without loading their contents" do
    {:ok, first} = Flows.create()
    {:ok, second} = Flows.create()

    start = insert_node(first)
    form = insert_node(first)
    insert_relationship(first, start, form)

    assert [%Flow{id: a}, %Flow{id: b}] = Flows.list()
    assert {a, b} == {first.id, second.id}

    assert [
             %Flow{nodes_count: 2, relationships_count: 1},
             %Flow{nodes_count: 0, relationships_count: 0}
           ] = Flows.list()

    assert [%Flow{nodes: %Ecto.Association.NotLoaded{}} | _] = Flows.list()

    # Owned subflow children live inside their root — never listed beside it
    {:ok, _child} = Flows.create(%{owner_flow_id: first.id})
    assert length(Flows.list()) == 2
  end

  test "get loads nodes and relationships, round-tripping labels and properties" do
    {:ok, flow} = Flows.create()

    start = insert_node(flow, ["Step", "Start"], %{"label" => "Start"})
    form = insert_node(flow, ["Step"], %{"label" => "Form", "fields" => 4})
    insert_relationship(flow, start, form, %{"if" => "always"})

    assert %Flow{nodes: nodes, relationships: [relationship]} = Flows.get(flow.id)

    assert length(nodes) == 2
    assert Enum.find(nodes, &(&1.id == start.id)).labels == ["Step", "Start"]

    assert Enum.find(nodes, &(&1.id == form.id)).properties == %{
             "label" => "Form",
             "fields" => 4,
             "flow_id" => flow.id
           }

    assert relationship.label == "TRANSITIONS_TO"
    assert relationship.properties == %{"if" => "always", "flow_id" => flow.id}
    assert {relationship.source_id, relationship.target_id} == {start.id, form.id}
  end

  test "flow_id is written to both the column and properties" do
    {:ok, flow} = Flows.create()
    node = insert_node(flow)
    other = insert_node(flow)
    relationship = insert_relationship(flow, node, other)

    assert node.flow_id == flow.id
    assert node.properties["flow_id"] == flow.id

    assert relationship.flow_id == flow.id
    assert relationship.properties["flow_id"] == flow.id
  end

  test "a source and target can only be linked once per label" do
    {:ok, flow} = Flows.create()
    start = insert_node(flow)
    form = insert_node(flow)

    insert_relationship(flow, start, form)

    assert {:error, changeset} =
             FormFlowRepo.insert(relationship_changeset(flow, start, form))

    assert %{source_id: ["has already been taken"]} = errors_on(changeset)

    # The same pair under a different label is fine
    assert {:ok, _} =
             FormFlowRepo.insert(
               relationship_changeset(flow, start, form, label: "FALLS_BACK_TO")
             )
  end

  test "relationships require nodes that exist" do
    {:ok, flow} = Flows.create()
    start = insert_node(flow)

    changeset =
      Flow.Relationship.changeset(%Flow.Relationship{}, %{
        flow_id: flow.id,
        source_id: start.id,
        target_id: Ecto.UUID.generate(),
        label: "TRANSITIONS_TO"
      })

    # SQLite reports foreign key violations without naming the constraint, so
    # Ecto cannot route them to the changeset's foreign_key_constraint and
    # raises instead. On Postgres this same insert returns {:error, changeset}
    # with "does not exist" on :target_id.
    assert_raise Ecto.ConstraintError, ~r/foreign_key_constraint/, fn ->
      FormFlowRepo.insert(changeset)
    end
  end

  test "deleting a node detaches it: its relationships go too" do
    {:ok, flow} = Flows.create()
    start = insert_node(flow)
    form = insert_node(flow)
    insert_relationship(flow, start, form)

    assert {:ok, _} = FormFlowRepo.delete(form)

    assert %Flow{relationships: []} = Flows.get(flow.id)
  end

  test "deleting a flow cascades to every node and relationship in it" do
    {:ok, flow} = Flows.create()
    start = insert_node(flow)
    form = insert_node(flow)
    insert_relationship(flow, start, form)

    assert {:ok, _} = Flows.delete(Flows.get(flow.id))

    assert {:ok, %{rows: [[0]]}} = Repo.query("SELECT count(*) FROM form_flow_nodes")

    assert {:ok, %{rows: [[0]]}} =
             Repo.query("SELECT count(*) FROM form_flow_relationships")
  end

  describe "declared flavor and save-time children" do
    test "create persists name and label; label is immutable" do
      {:ok, flow} = Flows.create(%{name: "Enrollment", label: "subflows"})

      assert flow.name == "Enrollment"
      assert flow.label == "subflows"

      assert {:error, changeset} = Flows.update(flow, %{label: "forms"})
      assert %{label: ["cannot be changed after creation"]} = errors_on(changeset)

      assert {:ok, renamed} = Flows.update(flow, %{name: "Renamed"})
      assert renamed.name == "Renamed"
    end

    test "a forms flow rejects subflow steps" do
      {:ok, flow} = Flows.create(%{label: "forms"})

      assert {:error, changeset} =
               Flows.update(flow, %{
                 nodes: [%{properties: %{"type" => "subflow", "data" => %{}}}],
                 relationships: []
               })

      assert %{nodes: ["a forms flow cannot contain subflow steps"]} = errors_on(changeset)
    end

    test "a subflows flow rejects form steps but accepts Start and End" do
      {:ok, flow} = Flows.create(%{label: "subflows"})

      assert {:error, changeset} =
               Flows.update(flow, %{
                 nodes: [%{properties: %{"type" => "step", "data" => %{"kind" => "form"}}}],
                 relationships: []
               })

      assert %{nodes: ["a subflows flow cannot contain form steps"]} = errors_on(changeset)

      assert {:ok, _} =
               Flows.update(Flows.get(flow.id), %{
                 nodes: Flows.starter_nodes(),
                 relationships: []
               })
    end

    test "saving creates children for subflow nodes, from their declared label" do
      {:ok, root} =
        Flows.create(%{label: "subflows", nodes: Flows.starter_nodes(), relationships: []})

      {:ok, _} =
        Flows.update(Flows.get(root.id), %{
          nodes: [
            %{
              properties: %{
                "type" => "subflow",
                "data" => %{"label" => "Collect address", "subflow_label" => "forms"}
              }
            },
            %{
              properties: %{
                "type" => "subflow",
                "data" => %{"label" => "Interview", "subflow_label" => "subflows"}
              }
            }
          ],
          relationships: []
        })

      root = Flows.get(root.id)
      children = root.nodes |> Enum.map(& &1.subflow_id) |> Enum.map(&Flows.get/1)

      address = Enum.find(children, &(&1.name == "Collect address"))
      interview = Enum.find(children, &(&1.name == "Interview"))

      assert address.label == "forms"
      assert interview.label == "subflows"

      # Owned by the root, seeded with the universal Start/End starter
      for child <- children do
        assert child.owner_flow_id == root.id

        assert child.nodes |> Enum.map(&get_in(&1.properties, ["data", "label"])) |> Enum.sort() ==
                 ["End", "Start"]

        assert child.relationships == []
      end

      # Saving again does not create duplicates: the references round-trip
      {:ok, _} =
        Flows.update(root, %{
          nodes: Enum.map(root.nodes, &%{id: &1.id, properties: &1.properties}),
          relationships: []
        })

      assert Flows.get(root.id).nodes
             |> Enum.map(& &1.subflow_id)
             |> Enum.sort() == Enum.sort([address.id, interview.id])
    end
  end

  describe "tenancy" do
    test "owned children created at save take the root's tenant, column and properties" do
      {:ok, root} = Flows.create(%{label: "subflows", tenant_id: "acme"})

      {:ok, _} =
        Flows.update(root, %{
          nodes: [
            %{
              id: Ecto.UUID.generate(),
              properties: %{
                "type" => "subflow",
                "data" => %{"label" => "Documents", "subflow_label" => "forms"}
              }
            }
          ],
          relationships: []
        })

      assert [node] = Flows.get(root.id).nodes
      child = Flows.get(node.subflow_id)
      assert child.tenant_id == "acme"
      assert child.properties["tenant_id"] == "acme"

      {:ok, _} =
        Flows.update(child, %{
          nodes: [
            %{
              id: Ecto.UUID.generate(),
              properties: %{"data" => %{"kind" => "form", "label" => "Intake"}}
            }
          ],
          relationships: []
        })

      assert [form_node] = Flows.get(child.id).nodes
      form = FormFlow.Data.Templates.Forms.get(form_node.form_id)
      assert form.tenant_id == "acme"
      assert form.properties["tenant_id"] == "acme"
    end

    test "duplicate carries the tenant into the copy and everything it owns" do
      {:ok, root} = Flows.create(%{tenant_id: "acme"})
      {:ok, child} = Flows.create(%{owner_flow_id: root.id, tenant_id: "acme"})
      insert_subflow_node(root, child)

      {:ok, copy} = Flows.duplicate(root)

      assert copy.tenant_id == "acme"
      assert copy.properties["tenant_id"] == "acme"

      assert [copied_node] = copy.nodes
      assert Flows.get(copied_node.subflow_id).tenant_id == "acme"
    end

    test "the listings narrow by tenant" do
      {:ok, mine} = Flows.create(%{name: "Mine", tenant_id: "acme"})
      {:ok, _theirs} = Flows.create(%{name: "Theirs", tenant_id: "globex"})
      {:ok, _untenanted} = Flows.create(%{name: "Nobody's"})

      assert [%Flow{id: id}] = Flows.list(tenant_id: "acme")
      assert id == mine.id
      assert length(Flows.list()) == 3
    end
  end

  describe "tenancy on the graph tables" do
    test "nodes and relationships carry the flow's tenant_id, in the column and in properties" do
      {:ok, flow} = Flows.create(%{name: "Intake", tenant_id: "acme"})
      start_id = Ecto.UUID.generate()
      form_id = Ecto.UUID.generate()

      {:ok, _} =
        Flows.update(flow, %{
          nodes: [
            %{id: start_id, properties: %{"data" => %{"label" => "Start", "kind" => "start"}}},
            %{id: form_id, properties: %{"data" => %{"label" => "Details", "kind" => "form"}}}
          ],
          relationships: [%{source_id: start_id, target_id: form_id, label: "CONNECTS_TO"}]
        })

      %{nodes: nodes, relationships: [relationship]} = Flows.get(flow.id)

      for node <- nodes do
        assert node.tenant_id == "acme"
        assert node.properties["tenant_id"] == "acme"
      end

      assert relationship.tenant_id == "acme"
      assert relationship.properties["tenant_id"] == "acme"

      # A duplicate's rows carry it too
      {:ok, copy} = Flows.duplicate(flow)
      %{nodes: nodes, relationships: [relationship]} = Flows.get(copy.id)
      assert Enum.all?(nodes, &(&1.tenant_id == "acme"))
      assert relationship.tenant_id == "acme"

      # A host with no tenants: nil, and no properties key
      {:ok, plain} = Flows.create(%{name: "Plain"})

      {:ok, _} =
        Flows.update(plain, %{
          nodes: [%{properties: %{"data" => %{"label" => "Start", "kind" => "start"}}}]
        })

      [node] = Flows.get(plain.id).nodes
      assert node.tenant_id == nil
      refute Map.has_key?(node.properties, "tenant_id")
    end
  end

  describe "slugs" do
    alias FormFlow.Data.Templates.Forms

    test "create generates one from the name; a given one is kept, normalized" do
      {:ok, flow} = Flows.create(%{name: "Dog License Application 2026"})
      assert flow.slug == "dla2026"
      assert flow.properties["slug"] == "dla2026"

      {:ok, named} = Flows.create(%{name: "Whatever", slug: " Custom-Slug "})
      assert named.slug == "custom-slug"

      {:ok, nameless} = Flows.create()
      assert nameless.slug == "flow"
    end

    test "a taken slug gets the first free -N suffix, per tenant" do
      {:ok, first} = Flows.create(%{name: "Intake"})
      {:ok, second} = Flows.create(%{name: "Intake"})
      {:ok, third} = Flows.create(%{name: "Intake"})
      {:ok, elsewhere} = Flows.create(%{name: "Intake", tenant_id: "acme"})

      assert first.slug == "intake"
      assert second.slug == "intake-2"
      assert third.slug == "intake-3"
      assert elsewhere.slug == "intake"
    end

    test "the database refuses a duplicate, hosts with no tenants included" do
      {:ok, _} = Flows.create(%{name: "A", slug: "taken"})

      assert {:error, changeset} = Flows.create(%{name: "B", slug: "taken"})
      assert {"has already been taken", _} = changeset.errors[:slug]

      # The same slug in another tenant is fine — and a second untenanted one is not
      assert {:ok, _} = Flows.create(%{name: "C", slug: "taken", tenant_id: "acme"})
      assert {:error, _} = Flows.create(%{name: "D", slug: "taken"})
    end

    test "a rename leaves the slug alone; an admin can change or clear it" do
      {:ok, flow} = Flows.create(%{name: "Dog License Application 2026"})

      {:ok, renamed} = Flows.update(flow, %{name: "Dog License Application 2027"})
      assert renamed.slug == "dla2026"

      {:ok, changed} = Flows.update(renamed, %{slug: "dla2027"})
      assert changed.slug == "dla2027"
      assert changed.properties["slug"] == "dla2027"

      {:ok, cleared} = Flows.update(changed, %{slug: nil})
      assert cleared.slug == nil
      refute Map.has_key?(cleared.properties, "slug")
    end

    test "steps get a slug under the root's; the owned children behind them have none" do
      {:ok, root} = Flows.create(%{name: "Dog License Application 2026", label: "subflows"})
      {:ok, _} = Flows.update(root, %{nodes: [subflow_step("Documents")], relationships: []})

      [node] = Flows.get(root.id).nodes
      assert node.slug == "dla2026_documents"
      assert node.properties["slug"] == "dla2026_documents"

      documents = Flows.get(node.subflow_id)
      assert documents.slug == nil
      refute Map.has_key?(documents.properties, "slug")

      # Inside the subflow the prefix is still the root's — the subflow has no
      # slug of its own — and two same-named steps in one save see each other
      {:ok, _} =
        Flows.update(documents, %{
          nodes: [form_step("User Information"), form_step("User Information")],
          relationships: []
        })

      nodes = Flows.get(documents.id).nodes

      assert Enum.sort(Enum.map(nodes, & &1.slug)) == [
               "dla2026_user-inform",
               "dla2026_user-inform-2"
             ]

      assert Enum.all?(nodes, &(Forms.get(&1.form_id).slug == nil))
    end

    test "Start and End get no slug; a slug given in node attrs is kept, and a taken one refused" do
      {:ok, flow} = Flows.create(%{name: "Intake"})

      {:ok, _} =
        Flows.update(flow, %{
          nodes:
            Flows.starter_nodes() ++ [Map.put(form_step("Owner contact"), :slug, "owner-contact")]
        })

      nodes = Flows.get(flow.id).nodes
      assert nodes |> Enum.reject(& &1.form_id) |> Enum.map(& &1.slug) == [nil, nil]
      assert [%{slug: "owner-contact"}] = Enum.filter(nodes, & &1.form_id)

      {:ok, other} = Flows.create(%{name: "Other"})

      assert {:error, changeset} =
               Flows.update(other, %{
                 nodes: [Map.put(form_step("Owner contact"), :slug, "owner-contact")]
               })

      assert {"has already been taken", _} = changeset.errors[:slug]

      # Another tenant may use it: steps are unique per tenant
      {:ok, acme} = Flows.create(%{name: "Acme", tenant_id: "acme"})

      assert {:ok, _} =
               Flows.update(acme, %{
                 nodes: [Map.put(form_step("Owner contact"), :slug, "owner-contact")]
               })
    end

    test "a canvas save keeps a step's slug by id and ignores the properties copy" do
      {:ok, flow} = Flows.create(%{name: "Intake"})
      {:ok, _} = Flows.update(flow, %{nodes: [form_step("Owner contact")]})
      [node] = Flows.get(flow.id).nodes
      assert node.slug == "intake_owner-conta"

      {:ok, _} = Flows.update_node(node, %{slug: "owner-contact"})

      # A tab opened before the change sends the old copy back — the column wins
      stale =
        put_in(form_step("Owner contact", node), [:properties, "slug"], "intake_owner-conta")

      {:ok, _} = Flows.update(Flows.get(flow.id), %{nodes: [stale]})

      [saved] = Flows.get(flow.id).nodes
      assert saved.slug == "owner-contact"
      assert saved.properties["slug"] == "owner-contact"

      # A step removed and added again is a new node, and takes the default
      {:ok, _} = Flows.update(Flows.get(flow.id), %{nodes: [form_step("Owner contact")]})
      [fresh] = Flows.get(flow.id).nodes
      assert fresh.id != node.id
      assert fresh.slug == "intake_owner-conta"
    end

    test "duplicate rewrites copied steps' defaults under the copy's slug; hand-set ones get a suffix" do
      {:ok, root} = Flows.create(%{name: "Dog License Application 2026", label: "subflows"})
      {:ok, _} = Flows.update(root, %{nodes: [subflow_step("Documents")]})
      [node] = Flows.get(root.id).nodes
      documents = Flows.get(node.subflow_id)

      {:ok, _} =
        Flows.update(documents, %{
          nodes: [
            form_step("User Information"),
            Map.put(form_step("Owner contact"), :slug, "owner-contact")
          ]
        })

      {:ok, copy} = Flows.duplicate(Flows.get(root.id), slug: "dla2027")
      assert copy.slug == "dla2027"
      [copied_node] = copy.nodes
      assert copied_node.slug == "dla2027_documents"

      copied_documents = Flows.get(copied_node.subflow_id)
      assert copied_documents.slug == nil

      assert Enum.sort(Enum.map(copied_documents.nodes, & &1.slug)) ==
               ["dla2027_user-inform", "owner-contact-2"]

      assert Enum.all?(copied_documents.nodes, &(Forms.get(&1.form_id).slug == nil))

      # Without a slug the copy takes the next free suffix of the source's,
      # and the steps' defaults follow it
      {:ok, second} = Flows.duplicate(Flows.get(root.id))
      assert second.slug == "dla2026-2"
      [second_node] = second.nodes
      assert second_node.slug == "dla2026-2_documents"

      # Copied into another tree, the steps' defaults take that tree's root
      # prefix — what a step made there would get — and the copy has no slug;
      # the hand-set one is on its fourth holder by now
      {:ok, cat} = Flows.create(%{name: "Cat License", label: "subflows"})
      {:ok, into} = Flows.duplicate(Flows.get(documents.id), owner_flow_id: cat.id)
      assert into.slug == nil
      assert into.owner_flow_id == cat.id

      assert Enum.sort(Enum.map(into.nodes, & &1.slug)) ==
               ["cat-license_user-inform", "owner-contact-4"]
    end

    test "get_by_slug/2 looks up by slug, scoped to a tenant when asked" do
      {:ok, plain} = Flows.create(%{name: "Intake"})
      {:ok, acme} = Flows.create(%{name: "Intake", tenant_id: "acme"})

      assert %Flow{id: id, nodes: []} = Flows.get_by_slug("intake", tenant_id: "acme")
      assert id == acme.id
      assert Flows.get_by_slug("nope") == nil
      assert Flows.get_by_slug("intake", tenant_id: "globex") == nil

      {:ok, _} = Flows.delete(acme)
      assert Flows.get_by_slug("intake").id == plain.id
    end

    test "get_node_by_slug/2 looks a step up, scoped to a tenant when asked" do
      {:ok, plain} = Flows.create(%{name: "Intake"})
      {:ok, _} = Flows.update(plain, %{nodes: [Map.put(form_step("Details"), :slug, "details")]})
      {:ok, acme} = Flows.create(%{name: "Intake", tenant_id: "acme"})
      {:ok, _} = Flows.update(acme, %{nodes: [Map.put(form_step("Details"), :slug, "details")]})

      assert %Flow.Node{flow_id: flow_id, form_id: form_id} =
               Flows.get_node_by_slug("details", tenant_id: "acme")

      assert flow_id == acme.id
      assert Forms.get(form_id).owner_flow_id == acme.id
      assert Flows.get_node_by_slug("details", tenant_id: "globex") == nil
      assert Flows.get_node_by_slug("nope") == nil

      {:ok, _} = Flows.delete(Flows.get(acme.id))
      assert Flows.get_node_by_slug("details").flow_id == plain.id
    end
  end

  describe "subflows and ownership" do
    test "an owned subflow: created, referenced, drilled into" do
      {:ok, root} = Flows.create()
      {:ok, child} = Flows.create(%{owner_flow_id: root.id})

      node = insert_subflow_node(root, child)

      assert Flows.owned?(child)
      refute Flows.owned?(root)

      # The reference dual-writes into properties, like flow_id
      assert node.subflow_id == child.id
      assert node.properties["subflow_id"] == child.id

      assert %Flow{id: id} = Flows.get(node.subflow_id)
      assert id == child.id
    end

    test "a subflow reference survives the editor round-trip via properties" do
      {:ok, root} = Flows.create(%{label: "subflows"})
      {:ok, child} = Flows.create(%{owner_flow_id: root.id})

      # The editor sends properties untouched, no :subflow_id attribute
      {:ok, _} =
        Flows.update(root, %{
          nodes: [%{id: Ecto.UUID.generate(), properties: %{"subflow_id" => child.id}}],
          relationships: []
        })

      assert [node] = Flows.get(root.id).nodes
      assert node.subflow_id == child.id
      assert Flows.get(child.id) != nil
    end

    test "duplicate copies the identity: name, label, and properties" do
      {:ok, root} =
        Flows.create(%{
          name: "Onboarding",
          label: "subflows",
          properties: %{"form_flow_type" => "wizard_any_order"}
        })

      {:ok, copy} = Flows.duplicate(root)

      assert copy.name == "Onboarding"
      assert copy.label == "subflows"
      assert copy.properties["form_flow_type"] == "wizard_any_order"
      assert copy.slug == "onboarding-2"
      assert copy.properties["slug"] == "onboarding-2"
    end

    test "duplicate deep-copies the subflows" do
      {:ok, root} = Flows.create()
      {:ok, owned} = Flows.create(%{owner_flow_id: root.id})

      form = insert_node(owned, ["Step"], %{"label" => "Inside"})
      insert_subflow_node(root, owned)

      assert {:ok, copy} = Flows.duplicate(Flows.get(root.id))

      assert copy.id != root.id

      # The subflow reference points at a fresh copy, never at the source's
      assert [owned_copy_id] = copy.nodes |> Enum.map(& &1.subflow_id) |> Enum.reject(&is_nil/1)
      assert owned_copy_id != owned.id

      owned_copy = Flows.get(owned_copy_id)
      assert owned_copy.owner_flow_id == copy.id
      assert [inside] = owned_copy.nodes
      assert inside.id != form.id
      assert inside.properties["label"] == "Inside"
    end

    test "deleting a root deletes its owned tree" do
      {:ok, root} = Flows.create()
      {:ok, owned} = Flows.create(%{owner_flow_id: root.id})
      {:ok, other} = Flows.create()

      insert_subflow_node(root, owned)

      assert {:ok, _} = Flows.delete(Flows.get(root.id))

      assert Flows.get(root.id) == nil
      assert Flows.get(owned.id) == nil
      assert Flows.get(other.id) != nil
    end

    test "deleting a subflow on its own is refused — its step is the way" do
      {:ok, root} = Flows.create(%{label: "subflows"})
      {:ok, owned} = Flows.create(%{owner_flow_id: root.id})
      node = insert_subflow_node(root, owned)

      assert {:error, changeset} = Flows.delete(owned)
      assert %{id: [message]} = errors_on(changeset)
      assert message =~ "it is a subflow of another flow"
      assert Flows.get(owned.id) != nil

      {:ok, _} = Flows.delete_node(node)
      assert Flows.get(owned.id) == nil
    end

    test "delete_node removes the step and collects the subtree under it" do
      {:ok, root} = Flows.create(%{label: "subflows"})
      {:ok, owned} = Flows.create(%{owner_flow_id: root.id})
      {:ok, grandchild} = Flows.create(%{owner_flow_id: root.id})

      owned_node = insert_subflow_node(root, owned)
      insert_subflow_node(owned, grandchild)

      {:ok, _} = Flows.delete_node(owned_node)

      # The step is gone, and the owned subtree went with it
      assert Flows.get_node(owned_node.id) == nil
      assert Flows.get(owned.id) == nil
      assert Flows.get(grandchild.id) == nil
    end

    test "a save refuses a subflow step pointing at a flow the tree does not own" do
      {:ok, root} = Flows.create(%{label: "subflows"})
      {:ok, other_root} = Flows.create(%{label: "subflows"})
      {:ok, theirs} = Flows.create(%{owner_flow_id: other_root.id})

      # Another tree's subflow, and a root flow: neither is this tree's to embed
      for foreign <- [theirs, other_root] do
        assert {:error, changeset} =
                 Flows.update(Flows.get(root.id), %{
                   nodes: [%{properties: %{"type" => "subflow", "subflow_id" => foreign.id}}],
                   relationships: []
                 })

        assert %{nodes: [message]} = errors_on(changeset)
        assert message =~ "must point at a flow this flow owns"
      end

      # Nothing was half-written, and the other tree is untouched
      assert Flows.get(root.id).nodes == []
      assert Flows.get(theirs.id).owner_flow_id == other_root.id

      # Copying is the way to use it here
      {:ok, mine} = Flows.duplicate(theirs, owner_flow_id: root.id)

      assert {:ok, _} =
               Flows.update(Flows.get(root.id), %{
                 nodes: [%{properties: %{"type" => "subflow", "subflow_id" => mine.id}}],
                 relationships: []
               })
    end

    test "saving contents garbage-collects unreachable owned subflows" do
      {:ok, root} = Flows.create(%{label: "subflows"})
      {:ok, kept} = Flows.create(%{owner_flow_id: root.id})
      {:ok, dropped} = Flows.create(%{owner_flow_id: root.id})
      {:ok, grandchild} = Flows.create(%{owner_flow_id: root.id})

      keeper = insert_subflow_node(root, kept)
      insert_subflow_node(root, dropped)
      insert_subflow_node(dropped, grandchild)

      # Save the root keeping only the node that references `kept`
      {:ok, _} =
        Flows.update(Flows.get(root.id), %{
          nodes: [%{id: keeper.id, subflow_id: kept.id, properties: keeper.properties}],
          relationships: []
        })

      assert Flows.get(kept.id) != nil
      assert Flows.get(dropped.id) == nil
      assert Flows.get(grandchild.id) == nil
    end
  end

  defp insert_node(flow, labels \\ ["Step"], properties \\ %{}) do
    {:ok, node} =
      %Flow.Node{}
      |> Flow.Node.changeset(%{flow_id: flow.id, labels: labels, properties: properties})
      |> FormFlowRepo.insert()

    node
  end

  defp insert_relationship(flow, source, target, properties \\ %{}) do
    {:ok, relationship} =
      FormFlowRepo.insert(relationship_changeset(flow, source, target, properties: properties))

    relationship
  end

  defp insert_subflow_node(flow, subflow) do
    {:ok, node} =
      %Flow.Node{}
      |> Flow.Node.changeset(%{
        flow_id: flow.id,
        subflow_id: subflow.id,
        properties: %{"type" => "subflow"}
      })
      |> FormFlowRepo.insert()

    node
  end

  defp relationship_changeset(flow, source, target, opts \\ []) do
    Flow.Relationship.changeset(%Flow.Relationship{}, %{
      flow_id: flow.id,
      source_id: source.id,
      target_id: target.id,
      label: Keyword.get(opts, :label, "TRANSITIONS_TO"),
      properties: Keyword.get(opts, :properties, %{})
    })
  end

  describe "step names" do
    # A step's name is its node's data.label — what the instance pages show.
    # Saving the canvas writes it through to the entity behind the step only
    # when this flow owns that entity; a catalog form or a reusable subflow
    # keeps its own name for every consumer.
    test "a canvas save renames the owned form behind a step, never a catalog form" do
      {:ok, dog} = Flows.create(%{name: "Dog License"})
      {:ok, _} = Flows.update(dog, %{nodes: [form_step("Owner contact")]})
      [owned_node] = Flows.get(dog.id).nodes
      assert Forms.get(owned_node.form_id).name == "Owner contact"

      {:ok, _} =
        Flows.update(Flows.get(dog.id), %{nodes: [form_step("Your details", owned_node)]})

      assert Forms.get(owned_node.form_id).name == "Your details"
      assert step_label(Flows.get(dog.id)) == "Your details"

      # A step pointing at a catalog form, labelled with the form's name, then
      # relabelled by a canvas save (which carries the node's id — a node saved
      # without one records no intent, so the first save here renames nothing)
      {:ok, catalog} = Forms.create(%{name: "Owner contact"})
      {:ok, cat} = Flows.create(%{name: "Cat License"})

      {:ok, _} =
        Flows.update(cat, %{nodes: [form_step("Owner contact", %{"form_id" => catalog.id})]})

      [cat_node] = Flows.get(cat.id).nodes
      assert cat_node.form_id == catalog.id

      {:ok, _} = Flows.update(Flows.get(cat.id), %{nodes: [form_step("Your details", cat_node)]})

      assert step_label(Flows.get(cat.id)) == "Your details"
      assert Forms.get(catalog.id).name == "Owner contact"
      assert Forms.get(catalog.id).owner_flow_id == nil
    end

    test "a canvas save renames the subflow behind a step" do
      {:ok, root} = Flows.create(%{name: "Dog License", label: "subflows"})
      {:ok, _} = Flows.update(root, %{nodes: [subflow_step("Subflow 1")]})
      [node] = Flows.get(root.id).nodes
      assert Flows.get(node.subflow_id).name == "Subflow 1"

      {:ok, _} = Flows.update(Flows.get(root.id), %{nodes: [subflow_step("Application", node)]})
      assert Flows.get(node.subflow_id).name == "Application"
      assert step_label(Flows.get(root.id)) == "Application"
    end

    test "update_node writes the step's label and slug, and nothing else" do
      {:ok, flow} = Flows.create(%{name: "Dog License"})
      {:ok, _} = Flows.update(flow, %{nodes: [form_step("Owner contact")]})
      [node] = Flows.get(flow.id).nodes
      assert node.slug == "dog-license_owner-conta"

      assert {:ok, renamed} = Flows.update_node(node, %{label: "Your details"})
      assert get_in(renamed.properties, ["data", "label"]) == "Your details"
      assert get_in(renamed.properties, ["data", "kind"]) == "form"
      assert renamed.form_id == node.form_id
      assert renamed.slug == "dog-license_owner-conta"
      assert step_label(Flows.get(flow.id)) == "Your details"

      # The form is the step's owner's concern, not this function's
      assert Forms.get(node.form_id).name == "Owner contact"

      # A blank label renames nothing — names are never blanked
      assert {:ok, same} = Flows.update_node(renamed, %{label: ""})
      assert get_in(same.properties, ["data", "label"]) == "Your details"

      # The slug: set, normalized, mirrored into properties; blank clears it
      assert {:ok, slugged} = Flows.update_node(same, %{slug: " Your-Details "})
      assert slugged.slug == "your-details"
      assert slugged.properties["slug"] == "your-details"
      assert get_in(slugged.properties, ["data", "label"]) == "Your details"

      assert {:ok, cleared} = Flows.update_node(slugged, %{label: "Your details", slug: ""})
      assert cleared.slug == nil
      refute Map.has_key?(cleared.properties, "slug")

      # A slug another step holds is refused by name
      {:ok, other} = Flows.create(%{name: "Cat License"})

      {:ok, _} =
        Flows.update(other, %{nodes: [Map.put(form_step("Owner contact"), :slug, "taken")]})

      assert {:error, changeset} = Flows.update_node(cleared, %{slug: "taken"})
      assert {"has already been taken", _} = changeset.errors[:slug]
    end
  end

  describe "reusing a catalog form" do
    # Dog License and Cat License each embed an Application subflow with an
    # Owner contact step. Saving gives each step a blank owned form; reusing
    # makes both steps the catalog's one Owner contact.
    test "form_usages names each step's flow and root, oldest root first" do
      {:ok, owner} = Forms.create(%{name: "Owner contact"})
      dog = license_flow("Dog License")
      cat = license_flow("Cat License")

      assert Flows.form_usages(owner.id) == []

      {:ok, _} = Flows.reuse_form(dog.step, owner)
      {:ok, _} = Flows.reuse_form(cat.step, owner)

      assert [dog_use, cat_use] = Flows.form_usages(owner.id)
      assert {dog_use.root.id, dog_use.flow.id} == {dog.root.id, dog.flow.id}
      assert dog_use.node.id == dog.step.id
      assert {cat_use.root.id, cat_use.flow.id} == {cat.root.id, cat.flow.id}
      assert {dog_use.root.name, dog_use.flow.name} == {"Dog License", "Application"}

      # An owned form is used once, in its own tree; a step in a root flow
      # has that root as both flow and root
      {:ok, flat} = Flows.create(%{name: "Flat"})
      {:ok, _} = Flows.update(flat, %{nodes: [form_step("Only")]})
      [flat_step] = Flows.get(flat.id).nodes

      assert [%{root: %{id: root_id}, flow: %{id: flow_id}}] =
               Flows.form_usages(flat_step.form_id)

      assert {root_id, flow_id} == {flat.id, flat.id}
    end

    test "reuse_form repoints the step, deletes its own form, and leaves the step's slug alone" do
      {:ok, owner} = Forms.create(%{name: "Owner contact"})
      dog = license_flow("Dog License")
      own = Forms.get(dog.step.form_id)
      assert own.owner_flow_id == dog.root.id
      assert own.slug == nil
      assert dog.step.slug == "dog-license_owner-conta"

      assert {:ok, %{form_id: form_id} = node} = Flows.reuse_form(dog.step, owner)
      assert form_id == owner.id
      # The properties copy the canvas round-trips moved with the column
      assert node.properties["form_id"] == owner.id
      # The step is still the step: its handle survives the change of form
      assert node.slug == "dog-license_owner-conta"

      assert Forms.get(own.id) == nil
      assert Forms.get(owner.id).owner_flow_id == nil

      # The flow's next save sweeps nothing: a catalog form has no owner
      {:ok, _} =
        Flows.update(Flows.get(dog.flow.id), %{nodes: [form_step("Owner contact", node)]})

      assert Forms.get(owner.id) != nil
      assert [%{form_id: ^form_id}] = Flows.get(dog.flow.id).nodes
    end

    test "reuse_form refuses what cannot be shared, and a published step form" do
      dog = license_flow("Dog License")

      {:ok, other_root} = Flows.create(%{name: "Other"})
      {:ok, owned} = Forms.create(%{name: "Owned", owner_flow_id: other_root.id})
      assert {:error, :owned_form} = Flows.reuse_form(dog.step, owned)

      {:ok, elsewhere} = Forms.create(%{name: "Elsewhere", tenant_id: "other"})
      assert {:error, :other_tenant} = Flows.reuse_form(dog.step, elsewhere)

      # A review form's source is a step path in one flow
      {:ok, review} = Forms.create(%{name: "Check owner", properties: %{"form_type" => "review"}})
      assert {:error, :related_form} = Flows.reuse_form(dog.step, review)

      # A published step form may have instances; it is never thrown away
      {:ok, owner} = Forms.create(%{name: "Owner contact"})
      [draft] = Forms.list_versions(dog.step.form_id)
      {:ok, _v1} = Forms.update_status(draft, :published)
      assert {:error, :step_form_published} = Flows.reuse_form(dog.step, owner)
      assert Flows.get_node(dog.step.id).form_id == dog.step.form_id
      assert Forms.get(dog.step.form_id) != nil

      # Content alone is no bar — the page's confirmation names what goes
      cat = license_flow("Cat License")
      [cat_draft] = Forms.list_versions(cat.step.form_id)
      {:ok, _} = Forms.update_draft(cat_draft, %{definition: %{"elements" => []}})
      assert {:ok, _} = Flows.reuse_form(cat.step, owner)
      assert Forms.get(cat.step.form_id) == nil
    end

    test "a canvas save types the owned form behind a step, never a catalog form" do
      {:ok, owner} = Forms.create(%{name: "Owner contact"})
      dog = license_flow("Dog License")

      {:ok, _} =
        Flows.update(Flows.get(dog.flow.id), %{nodes: [typed_step(dog.step, "review")]})

      assert Forms.get(dog.step.form_id).properties["form_type"] == "review"

      {:ok, step} = Flows.reuse_form(dog.step, owner)
      {:ok, _} = Flows.update(Flows.get(dog.flow.id), %{nodes: [typed_step(step, "review")]})

      refute Map.has_key?(Forms.get(owner.id).properties, "form_type")
    end
  end

  # A root flow of subflows embedding one Application flow of forms with one
  # Owner contact step — saved, so the step has its blank owned form
  defp license_flow(name) do
    {:ok, root} = Flows.create(%{name: name, label: "subflows"})
    {:ok, _} = Flows.update(root, %{nodes: [subflow_step("Application")]})
    [subflow_node] = Flows.get(root.id).nodes

    flow = Flows.get(subflow_node.subflow_id)
    {:ok, _} = Flows.update(flow, %{nodes: [form_step("Owner contact")]})
    [step] = Flows.get(flow.id).nodes

    %{root: Flows.get(root.id), subflow_node: subflow_node, flow: Flows.get(flow.id), step: step}
  end

  # The step as the canvas saves it with a form type picked in its dropdown
  defp typed_step(node, type) do
    %{
      id: node.id,
      properties: %{
        "type" => "step",
        "form_id" => node.form_id,
        "data" => %{"label" => "Owner contact", "kind" => "form", "form_type" => type}
      }
    }
  end

  defp form_step(label, node_or_extra \\ %{})

  defp form_step(label, %{id: id} = node) do
    %{
      id: id,
      properties: %{
        "type" => "step",
        "form_id" => node.form_id,
        "data" => %{"label" => label, "kind" => "form"}
      }
    }
  end

  defp form_step(label, extra) when is_map(extra) do
    %{
      properties:
        Map.merge(%{"type" => "step", "data" => %{"label" => label, "kind" => "form"}}, extra)
    }
  end

  defp subflow_step(label, node \\ nil) do
    properties = %{
      "type" => "subflow",
      "data" => %{"label" => label, "subflow_label" => "forms"}
    }

    case node do
      nil -> %{properties: properties}
      node -> %{id: node.id, properties: Map.put(properties, "subflow_id", node.subflow_id)}
    end
  end

  defp step_label(%Flow{nodes: [node]}), do: get_in(node.properties, ["data", "label"])
end
