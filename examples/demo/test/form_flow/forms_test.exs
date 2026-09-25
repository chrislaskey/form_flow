defmodule Demo.FormFlowFormsTest do
  @moduledoc """
  Exercises `FormFlow.Data.Templates.Forms` — the form template row and version lifecycle
  and the publish operation with what it does to existing instances — against a real
  database. The library's own tests stop at changesets; the optimistic lock,
  the version-numbering unique index, the FK net, and the instance
  migrations are proven here.
  """

  use Demo.DataCase, async: false

  alias FormFlow.Data.Templates.Flows
  alias FormFlow.Data.Instances
  alias FormFlow.Data.Repo, as: FormFlowRepo
  alias FormFlow.Data.Templates.Form
  alias FormFlow.Data.Templates.Forms

  describe "form template CRUD" do
    test "create makes the form template row plus its initial draft in one transaction" do
      assert {:ok, %Form{} = form} =
               Forms.create(%{name: "W-2 Details", definition: %{"seed" => true}})

      assert [draft] = form.versions
      assert draft.status == "draft"
      assert draft.version == nil
      assert draft.definition == %{"seed" => true}
    end

    test "create without a name fails, and no orphan draft is left behind" do
      assert {:error, %Ecto.Changeset{}} = Forms.create(%{definition: %{}})
    end

    test "list is the catalog: unowned forms, oldest first, narrowed to a tenant on request" do
      {:ok, first} = Forms.create(%{name: "First"})
      {:ok, other_tenant} = Forms.create(%{name: "Elsewhere", tenant_id: "other"})
      {:ok, second} = Forms.create(%{name: "Second"})

      # No tenant given lists every tenant's catalog — a host with no tenants
      # has nothing to narrow by
      assert Enum.map(Forms.list(), & &1.id) == [first.id, other_tenant.id, second.id]
      assert Enum.map(Forms.list(tenant_id: "other"), & &1.id) == [other_tenant.id]
    end

    test "update touches identity only" do
      {:ok, form} = Forms.create(%{name: "Before"})

      assert {:ok, %Form{name: "After"}} = Forms.update(Forms.get(form.id), %{name: "After"})
    end

    test "catalog names are unique — the catalog is one namespace, across tenants" do
      {:ok, _} = Forms.create(%{name: "Enrollment"})

      assert {:error, changeset} = Forms.create(%{name: "Enrollment"})
      assert %{name: ["has already been taken"]} = errors_on(changeset)

      assert {:error, changeset} = Forms.create(%{name: "Enrollment", tenant_id: "other"})
      assert %{name: ["has already been taken"]} = errors_on(changeset)
    end

    test "delete removes versions then the form template row" do
      {:ok, form} = Forms.create(%{name: "Mistake"})

      assert {:ok, _} = Forms.delete(Forms.get(form.id))
      assert Forms.get(form.id) == nil
      assert Forms.list_versions(form.id) == []
    end

    test "delete refuses while instance data exists — fill data is never orphaned" do
      {form, v1} = published_form()
      instance = insert_instance(v1)

      assert {:error, :has_instances} = Forms.delete(Forms.get(form.id))

      # The explicit deletion path unblocks it: events, then the instance
      assert {:ok, _} = Instances.Forms.delete_instance(instance)
      assert {:ok, _} = Forms.delete(Forms.get(form.id))
    end
  end

  describe "drafts" do
    test "create_draft forks a published version, recording provenance" do
      {form, v1} = published_form(%{"fields" => [%{"name" => "ssn"}]})

      assert {:ok, draft} = Forms.create_draft(form.id, based_on: v1.id)
      assert draft.definition == v1.definition
      assert draft.based_on_version_id == v1.id
      refute Forms.stale_draft?(draft)
    end

    test "drafts cannot fork drafts, only published versions" do
      {:ok, form} = Forms.create(%{name: "Form"})
      [draft] = form.versions

      assert {:error, :based_on_draft} = Forms.create_draft(form.id, based_on: draft.id)
    end

    test "based_on must belong to the same form template" do
      {_form, v1} = published_form()
      {:ok, other} = Forms.create(%{name: "Other"})

      assert {:error, :based_on_wrong_form} = Forms.create_draft(other.id, based_on: v1.id)
    end

    test "several drafts coexist per form template" do
      {form, v1} = published_form()

      {:ok, _a} = Forms.create_draft(form.id, based_on: v1.id)
      {:ok, _b} = Forms.create_draft(form.id)

      drafts = Enum.filter(Forms.list_versions(form.id), &(&1.status == "draft"))
      assert length(drafts) == 2
    end

    test "update_draft edits under the optimistic lock" do
      {:ok, form} = Forms.create(%{name: "Form"})
      [draft] = form.versions

      assert {:ok, updated} = Forms.update_draft(draft, %{definition: %{"v" => 2}})
      assert updated.definition == %{"v" => 2}

      # The caller still holding the pre-update struct is told, not overwritten
      assert {:error, :stale} = Forms.update_draft(draft, %{definition: %{"v" => 3}})
    end

    test "published definitions are immutable" do
      {_form, v1} = published_form()

      assert {:error, changeset} = Forms.update_draft(v1, %{definition: %{"changed" => true}})
      assert %{definition: _} = errors_on(changeset)
    end

    test "delete_draft removes drafts and nothing else" do
      {form, v1} = published_form()
      {:ok, draft} = Forms.create_draft(form.id)

      assert {:ok, _} = Forms.delete_draft(draft)
      assert {:error, :not_draft} = Forms.delete_draft(v1)
    end

    test "stale_draft? fires once a newer version publishes" do
      {form, v1} = published_form()
      {:ok, draft} = Forms.create_draft(form.id, based_on: v1.id)

      {:ok, newer} = Forms.create_draft(form.id, based_on: v1.id)
      {:ok, _v2} = Forms.update_status(newer, :published)

      assert Forms.stale_draft?(Forms.get_version(draft.id))
    end
  end

  describe "publishing" do
    test "publish assigns linear numbers in publish order" do
      {:ok, form} = Forms.create(%{name: "Form"})
      [draft] = form.versions

      assert {:ok, v1} = Forms.update_status(draft, :published)
      assert v1.version == 1
      assert v1.status == "published"
      assert v1.published_at != nil

      {:ok, second} = Forms.create_draft(form.id, based_on: v1.id)
      assert {:ok, %{version: 2}} = Forms.update_status(second, :published)
    end

    test "publishing a non-draft is refused" do
      {_form, v1} = published_form()

      assert {:error, :not_draft} = Forms.update_status(v1, :published)
    end

    test "get_latest_version skips drafts and archived — archiving the latest is a rollback" do
      {form, v1} = published_form()
      {:ok, draft} = Forms.create_draft(form.id, based_on: v1.id)
      {:ok, v2} = Forms.update_status(draft, :published)

      assert Forms.get_latest_version(form.id).id == v2.id

      {:ok, _archived} = Forms.update_status(v2, :archived)
      assert Forms.get_latest_version(form.id).id == v1.id
    end

    test "numbering counts archived versions — a retired number is never reissued" do
      {form, v1} = published_form()
      {:ok, _} = Forms.update_status(v1, :archived)

      {:ok, draft} = Forms.create_draft(form.id)
      assert {:ok, %{version: 2}} = Forms.update_status(draft, :published)
    end

    test "archived versions are valid based_on targets, and the draft is stale once anything else is published" do
      {form, v1} = published_form()
      {:ok, v2_draft} = Forms.create_draft(form.id, based_on: v1.id)
      {:ok, v2} = Forms.update_status(v2_draft, :published)
      {:ok, v1} = Forms.update_status(v1, :archived)

      assert {:ok, draft} = Forms.create_draft(form.id, based_on: v1.id)
      assert draft.definition == v1.definition
      assert draft.based_on_version_id == v1.id
      assert Forms.stale_draft?(draft)

      # Retiring the only published version leaves nothing to be behind
      {:ok, _} = Forms.update_status(v2, :archived)
      refute Forms.stale_draft?(draft)
    end
  end

  describe "publishing: what happens to existing form instances" do
    test "drafts move to the new version with their answers; submitted forms stay" do
      {form, v1} = published_form()
      draft = insert_instance(v1, data: %{"name" => "Ada"})
      submitted = insert_instance(v1, status: "completed", completed_at: DateTime.utc_now())

      {:ok, v2} = publish_next(form, v1, user_id: "admin-7")

      carried = reload(draft)
      assert carried.template_form_version_id == v2.id
      assert carried.data == %{"name" => "Ada"}

      assert [event] = events_for(draft)
      assert event.event == "migrated"
      assert event.from_version_id == v1.id
      assert event.to_version_id == v2.id
      assert event.user_id == "admin-7"

      # A submitted form is an attestation record - left as it is by default
      assert reload(submitted).template_form_version_id == v1.id
      assert reload(submitted).status == "completed"
      assert events_for(submitted) == []
    end

    test "reopen_submitted: true reopens submitted forms in journeys still in progress, answers kept" do
      {form, v1} = published_form()
      journey = journey()

      submitted =
        insert_instance(v1,
          instance_flow_id: journey.id,
          path: ["a"],
          status: "completed",
          completed_at: DateTime.utc_now(),
          data: %{"name" => "Grace"}
        )

      draft =
        insert_instance(v1, instance_flow_id: journey.id, path: ["b"], data: %{"name" => "Ada"})

      {:ok, v2} = publish_next(form, v1, reopen_submitted: true, user_id: "admin-7")

      reopened = reload(submitted)
      assert reopened.template_form_version_id == v2.id
      assert reopened.status == "in_progress"
      assert reopened.completed_at == nil
      assert %DateTime{} = reopened.reopened_at
      # Answers are never cleared - the user checks and submits again
      assert reopened.data == %{"name" => "Grace"}

      assert [event] = events_for(submitted)
      assert event.event == "reopened"
      assert event.from_version_id == v1.id
      assert event.to_version_id == v2.id
      assert event.snapshot == %{}
      assert event.user_id == "admin-7"

      # Drafts carry as they always do
      assert reload(draft).template_form_version_id == v2.id
      assert [%{event: "migrated"}] = events_for(draft)
    end

    test "a completed journey is never touched, whatever the publish asks" do
      {form, v1} = published_form()
      journey = journey("open", "completed")

      draft =
        insert_instance(v1, instance_flow_id: journey.id, path: ["a"], data: %{"name" => "Ada"})

      submitted =
        insert_instance(v1,
          instance_flow_id: journey.id,
          path: ["b"],
          status: "completed",
          completed_at: DateTime.utc_now()
        )

      {:ok, _v2} = publish_next(form, v1, reopen_submitted: true)

      assert reload(draft).template_form_version_id == v1.id
      assert reload(submitted).template_form_version_id == v1.id
      assert reload(submitted).status == "completed"
      assert events_for(draft) == []
      assert events_for(submitted) == []
    end

    test "a read-only or archived flow is never touched either" do
      {form, v1} = published_form()

      instances =
        for flow_status <- ["read_only", "archived"] do
          journey = journey(flow_status)

          [
            insert_instance(v1,
              instance_flow_id: journey.id,
              path: ["a"],
              data: %{"name" => "Ada"}
            ),
            insert_instance(v1,
              instance_flow_id: journey.id,
              path: ["b"],
              status: "completed",
              completed_at: DateTime.utc_now()
            )
          ]
        end

      {:ok, _v2} = publish_next(form, v1, reopen_submitted: true)

      for instance <- List.flatten(instances) do
        assert reload(instance).template_form_version_id == v1.id
        assert reload(instance).status == instance.status
        assert events_for(instance) == []
      end
    end

    test "the saved draft follows the answers: carried and re-keyed with them" do
      {form, v1} = published_form()

      instance =
        insert_instance(v1,
          data: %{"name" => "Ada"},
          draft: %{"data" => %{"name" => "Ad", "note" => "wip"}, "user_id" => "ada"}
        )

      {:ok, v2} = publish_next(form, v1, renames: %{"name" => "full_name"})

      carried = reload(instance)
      assert carried.template_form_version_id == v2.id
      assert carried.data == %{"full_name" => "Ada"}

      # Re-keyed like the answers, with who saved it untouched
      assert carried.draft == %{
               "data" => %{"full_name" => "Ad", "note" => "wip"},
               "user_id" => "ada"
             }

      # The event snapshots what was dropped from the answers - nothing
      # here, the definition declares no fields - and never the draft
      assert [%{event: "migrated", snapshot: %{}}] = events_for(instance)
    end

    test "renames re-key carried data, then keys the new definition does not declare are dropped into the snapshot" do
      {form, v1} = published_form()

      instance =
        insert_instance(v1, data: %{"old_name" => "Ada", "kept" => "yes", "orphan" => "gone"})

      {:ok, draft} = Forms.create_draft(form.id, based_on: v1.id)

      {:ok, draft} =
        Forms.update_draft(draft, %{
          definition: %{"fields" => [%{"name" => "new_name"}, %{"name" => "kept"}]}
        })

      {:ok, _v2} = Forms.update_status(draft, :published, renames: %{"old_name" => "new_name"})

      migrated = reload(instance)
      assert migrated.data == %{"new_name" => "Ada", "kept" => "yes"}

      # The dropped key survives in the event snapshot - nothing is lost silently
      assert [%{snapshot: %{"orphan" => "gone"}}] = events_for(instance)
    end

    test "a definition without declared fields drops nothing - never everything" do
      {form, v1} = published_form()
      instance = insert_instance(v1, data: %{"name" => "Ada"})

      {:ok, _v2} = publish_next(form, v1)

      assert reload(instance).data == %{"name" => "Ada"}
      assert [%{snapshot: %{}}] = events_for(instance)
    end

    test "a shared catalog form's publish reaches every flow using it, journey by journey" do
      {form, v1} = published_form()
      dog = journey()
      cat = journey()
      finished = journey("open", "completed")

      [in_dog, in_cat, in_finished] =
        for journey <- [dog, cat, finished] do
          insert_instance(v1,
            instance_flow_id: journey.id,
            status: "completed",
            completed_at: DateTime.utc_now()
          )
        end

      {:ok, v2} = publish_next(form, v1, reopen_submitted: true)

      assert reload(in_dog).template_form_version_id == v2.id
      assert reload(in_dog).status == "in_progress"
      assert reload(in_cat).template_form_version_id == v2.id
      assert reload(in_cat).status == "in_progress"
      assert reload(in_finished).template_form_version_id == v1.id
      assert reload(in_finished).status == "completed"
    end

    test "the retired options are refused, not ignored" do
      {form, v1} = published_form()

      for opts <- [
            [preset: :big_fix],
            [in_progress: :carry],
            [completed: :reopen_carry],
            [prune: true]
          ] do
        assert_raise ArgumentError, ~r/unknown publish option/, fn ->
          publish_next(form, v1, opts)
        end
      end

      assert_raise ArgumentError, ~r/boolean/, fn ->
        publish_next(form, v1, reopen_submitted: :yes)
      end
    end
  end

  describe "instance counts" do
    test "count the forms a publish reaches, by draft and submitted, by flow, and by version" do
      {form, v1} = published_form()
      {:ok, open_flow} = Flows.create(%{name: "Open flow", status: "open"})

      {:ok, open_journey} =
        Instances.Flows.create(%{template_flow_id: open_flow.id}, refresh: false)

      finished = journey("open", "completed")
      frozen = journey("read_only")

      # Counted: a standalone submitted form, and a draft and a submitted
      # form in a journey still in progress
      insert_instance(v1, status: "completed", completed_at: DateTime.utc_now())
      insert_instance(v1, instance_flow_id: open_journey.id, path: ["a"])

      insert_instance(v1,
        instance_flow_id: open_journey.id,
        path: ["b"],
        status: "completed",
        completed_at: DateTime.utc_now()
      )

      # Not counted: a completed journey, a read-only flow, a superseded row
      insert_instance(v1,
        instance_flow_id: finished.id,
        status: "completed",
        completed_at: DateTime.utc_now()
      )

      insert_instance(v1,
        instance_flow_id: frozen.id,
        status: "completed",
        completed_at: DateTime.utc_now()
      )

      insert_instance(v1,
        instance_flow_id: open_journey.id,
        path: ["c"],
        status: "completed",
        completed_at: DateTime.utc_now(),
        superseded_at: DateTime.utc_now()
      )

      assert Forms.instance_counts(form.id) == %{drafts: 1, submitted: 2}

      assert Forms.instance_counts_by_flow(form.id) == [
               %{flow_id: open_flow.id, flow_name: "Open flow", drafts: 1, submitted: 1},
               %{flow_id: nil, flow_name: nil, drafts: 0, submitted: 1}
             ]

      assert Forms.instance_counts_by_version(form.id) == %{v1.id => %{drafts: 1, submitted: 2}}
    end
  end

  describe "copy/2" do
    test "a published source copies as a published v1 with provenance" do
      {form, _v1} = published_form(%{"fields" => [%{"name" => "ssn"}]})
      # A newer draft exists but does not copy — history stays with the source
      {:ok, _draft} = Forms.create_draft(form.id)

      owner = insert_flow()
      assert {:ok, copy} = Forms.copy(Forms.get(form.id), owner_flow_id: owner.id)

      assert copy.copied_from_form_id == form.id
      assert copy.owner_flow_id == owner.id
      assert [v1] = copy.versions
      assert v1.status == "published"
      assert v1.version == 1
      assert v1.definition == %{"fields" => [%{"name" => "ssn"}]}
    end

    test "the copy carries the source's properties, and no slug of its own" do
      {:ok, form} =
        Forms.create(%{
          name: "Check owner",
          properties: %{
            "form_type" => "review",
            "form_type_property_values" => %{"source" => "node-a/node-b"}
          }
        })

      owner = insert_flow()
      assert {:ok, copy} = Forms.copy(form, owner_flow_id: owner.id)

      assert copy.properties["form_type"] == "review"
      assert copy.properties["form_type_property_values"] == %{"source" => "node-a/node-b"}

      # Or the properties given, when the caller has re-pointed them
      assert {:ok, repointed} =
               Forms.copy(form,
                 owner_flow_id: owner.id,
                 properties: %{
                   "form_type" => "review",
                   "form_type_property_values" => %{"source" => "node-c"}
                 }
               )

      assert repointed.properties["form_type_property_values"] == %{"source" => "node-c"}
      # An owned copy has no slug — its step's is the handle — and the
      # dual-written copy of the source's did not come along
      assert copy.slug == nil
      refute Map.has_key?(copy.properties, "slug")
    end

    test "a never-published source copies its newest draft as a draft" do
      {:ok, form} = Forms.create(%{name: "Unfinished", definition: %{"wip" => true}})

      owner = insert_flow()
      assert {:ok, copy} = Forms.copy(form, owner_flow_id: owner.id)

      assert [draft] = copy.versions
      assert draft.status == "draft"
      assert draft.version == nil
      assert draft.definition == %{"wip" => true}
    end
  end

  describe "prefills" do
    test "create saves a named set of answers, recorded with who and when" do
      {:ok, form} = Forms.create(%{name: "Dog Information"})

      assert {:ok, form} =
               Forms.create_prefill(form, %{
                 name: "Happy path",
                 description: "Everything filled in.",
                 data: %{"pet_name" => "Rex", "breed" => "Beagle"},
                 user_id: "admin"
               })

      assert [prefill] = Forms.list_prefills(form)
      assert prefill.name == "Happy path"
      assert prefill.description == "Everything filled in."
      assert prefill.data == %{"pet_name" => "Rex", "breed" => "Beagle"}
      assert prefill.user_id == "admin"
      assert %DateTime{} = prefill.inserted_at
      assert prefill.updated_at == prefill.inserted_at

      # Through the database, not just the struct the write returned
      assert Forms.get_prefill(Forms.get(form.id), "Happy path") == prefill
    end

    test "a form's prefills are listed by name, and fetched by it" do
      {:ok, form} = Forms.create(%{name: "Dog Information"})
      {:ok, form} = Forms.create_prefill(form, %{name: "No vet record", data: %{}})

      {:ok, form} =
        Forms.create_prefill(form, %{name: "Happy path", data: %{"pet_name" => "Rex"}})

      assert ["Happy path", "No vet record"] = Enum.map(Forms.list_prefills(form), & &1.name)
      assert Forms.get_prefill(form, "Happy path").data == %{"pet_name" => "Rex"}
      assert Forms.get_prefill(form, "Never saved") == nil
    end

    test "a name is a form's own handle — twice is refused, another form is free" do
      {:ok, form} = Forms.create(%{name: "Dog Information"})
      {:ok, other} = Forms.create(%{name: "Cat Information"})
      {:ok, form} = Forms.create_prefill(form, %{name: "Happy path", data: %{}})

      assert {:error, changeset} = Forms.create_prefill(form, %{name: "Happy path", data: %{}})
      assert %{name: ["has already been taken"]} = errors_on(changeset)

      assert {:ok, _other} = Forms.create_prefill(other, %{name: "Happy path", data: %{}})
    end

    test "create refuses a prefill with no name" do
      {:ok, form} = Forms.create(%{name: "Dog Information"})

      assert {:error, changeset} = Forms.create_prefill(form, %{data: %{"pet_name" => "Rex"}})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "update edits the answers and moves updated_at, keeping when it was saved" do
      {:ok, form} = Forms.create(%{name: "Dog Information"})

      {:ok, form} =
        Forms.create_prefill(form, %{name: "Happy path", data: %{"pet_name" => "Rex"}})

      saved_at = Forms.get_prefill(form, "Happy path").inserted_at

      assert {:ok, form} =
               Forms.update_prefill(form, "Happy path", %{data: %{"pet_name" => "Rexington"}})

      prefill = Forms.get_prefill(form, "Happy path")
      assert prefill.data == %{"pet_name" => "Rexington"}
      assert prefill.inserted_at == saved_at
      assert DateTime.compare(prefill.updated_at, saved_at) in [:gt, :eq]
    end

    test "update under another name renames it, and refuses a name already taken" do
      {:ok, form} = Forms.create(%{name: "Dog Information"})

      {:ok, form} =
        Forms.create_prefill(form, %{name: "Happy path", data: %{"pet_name" => "Rex"}})

      {:ok, form} = Forms.create_prefill(form, %{name: "No vet record", data: %{}})

      assert {:ok, form} = Forms.update_prefill(form, "Happy path", %{name: "Every field"})

      assert Forms.get_prefill(form, "Happy path") == nil
      assert Forms.get_prefill(form, "Every field").data == %{"pet_name" => "Rex"}

      assert {:error, changeset} =
               Forms.update_prefill(form, "Every field", %{name: "No vet record"})

      assert %{name: ["has already been taken"]} = errors_on(changeset)
    end

    test "update and delete answer for a prefill that is not there" do
      {:ok, form} = Forms.create(%{name: "Dog Information"})

      assert {:error, :not_found} = Forms.update_prefill(form, "Never saved", %{data: %{}})
      assert {:error, :not_found} = Forms.delete_prefill(form, "Never saved")
    end

    test "delete removes one and leaves the rest" do
      {:ok, form} = Forms.create(%{name: "Dog Information"})
      {:ok, form} = Forms.create_prefill(form, %{name: "Happy path", data: %{}})
      {:ok, form} = Forms.create_prefill(form, %{name: "No vet record", data: %{}})

      assert {:ok, form} = Forms.delete_prefill(form, "Happy path")

      assert ["No vet record"] = Enum.map(Forms.list_prefills(Forms.get(form.id)), & &1.name)
    end

    test "prefills survive a publish — they are the form's, not a version's" do
      {:ok, form} = Forms.create(%{name: "Dog Information", definition: %{"fields" => []}})

      {:ok, form} =
        Forms.create_prefill(form, %{name: "Happy path", data: %{"pet_name" => "Rex"}})

      [draft] = Forms.list_versions(form.id)
      {:ok, _published} = Forms.update_status(draft, :published)

      assert ["Happy path"] = Enum.map(Forms.list_prefills(Forms.get(form.id)), & &1.name)
    end

    test "an ordinary update cannot drop the set" do
      {:ok, form} = Forms.create(%{name: "Dog Information"})

      {:ok, form} =
        Forms.create_prefill(form, %{name: "Happy path", data: %{"pet_name" => "Rex"}})

      {:ok, renamed} = Forms.update(Forms.get(form.id), %{name: "Dog Details", prefills: %{}})

      assert ["Happy path"] = Enum.map(Forms.list_prefills(renamed), & &1.name)
    end

    test "a copy opens with the source's prefills" do
      {:ok, form} = Forms.create(%{name: "Dog Information"})

      {:ok, form} =
        Forms.create_prefill(form, %{
          name: "Happy path",
          data: %{"pet_name" => "Rex"},
          user_id: "admin"
        })

      owner = insert_flow()
      assert {:ok, copy} = Forms.copy(form, owner_flow_id: owner.id)

      assert [prefill] = Forms.list_prefills(copy)
      assert prefill.name == "Happy path"
      assert prefill.data == %{"pet_name" => "Rex"}
      assert prefill.user_id == "admin"
    end
  end

  describe "flow integration" do
    test "saving a forms flow auto-creates an owned form per unbacked form node" do
      {:ok, flow} = Flows.create(%{name: "Taxes 2026"})

      {:ok, _flow} = Flows.update(flow, %{nodes: [form_node_attrs("W-2 Details")]})

      [node] = Flows.get(flow.id).nodes
      form = Forms.get(node.form_id)

      assert form.name == "W-2 Details"
      assert form.owner_flow_id == flow.id
      assert node.properties["form_id"] == form.id
      assert [%{status: "draft"}] = Forms.list_versions(form.id)
    end

    test "a form node keeps its form across editor round-trip saves" do
      {:ok, flow} = Flows.create()
      {:ok, _} = Flows.update(flow, %{nodes: [form_node_attrs("W-2")]})
      [node] = Flows.get(flow.id).nodes

      # The editor round-trips properties; the column arrives nil and takes
      # its value from the copy
      {:ok, _} =
        Flows.update(Flows.get(flow.id), %{
          nodes: [%{id: node.id, properties: node.properties}]
        })

      [saved] = Flows.get(flow.id).nodes
      assert saved.form_id == node.form_id
    end

    test "removing a form node sweeps its owned form on save" do
      {:ok, flow} = Flows.create()
      {:ok, _} = Flows.update(flow, %{nodes: [form_node_attrs("Doomed")]})
      [node] = Flows.get(flow.id).nodes

      {:ok, _} = Flows.update(Flows.get(flow.id), %{nodes: []})

      assert Forms.get(node.form_id) == nil
    end

    test "the sweep refuses when the removed form has fill data" do
      {:ok, flow} = Flows.create()
      {:ok, _} = Flows.update(flow, %{nodes: [form_node_attrs("Filled")]})
      [node] = Flows.get(flow.id).nodes

      [draft] = Forms.list_versions(node.form_id)
      {:ok, v1} = Forms.update_status(draft, :published)
      insert_instance(v1)

      assert {:error, changeset} = Flows.update(Flows.get(flow.id), %{nodes: []})
      assert %{nodes: [message]} = errors_on(changeset)
      assert message =~ "still has submitted data"

      # And nothing was half-deleted — the save rolled back whole
      assert Forms.get(node.form_id) != nil
      assert [_node] = Flows.get(flow.id).nodes
    end

    test "deleting a flow deletes its owned forms — they never leak into the catalog" do
      {:ok, flow} = Flows.create()
      {:ok, _} = Flows.update(flow, %{nodes: [form_node_attrs("Private")]})
      [node] = Flows.get(flow.id).nodes

      {:ok, _} = Flows.delete(Flows.get(flow.id))

      assert Forms.get(node.form_id) == nil
      refute Enum.any?(Forms.list(), &(&1.name == "Private"))
    end

    test "deleting a flow is refused while an owned form has fill data" do
      {:ok, flow} = Flows.create()
      {:ok, _} = Flows.update(flow, %{nodes: [form_node_attrs("Filled")]})
      [node] = Flows.get(flow.id).nodes

      [draft] = Forms.list_versions(node.form_id)
      {:ok, v1} = Forms.update_status(draft, :published)
      insert_instance(v1)

      assert {:error, changeset} = Flows.delete(Flows.get(flow.id))
      assert %{id: [message]} = errors_on(changeset)
      assert message =~ "still has submitted data"
    end

    test "copy copies owned forms into the new domain, with provenance" do
      {:ok, flow} = Flows.create()
      {:ok, _} = Flows.update(flow, %{nodes: [form_node_attrs("W-2 Details")]})
      [source_node] = Flows.get(flow.id).nodes

      {:ok, copy} = Flows.copy(Flows.get(flow.id), host_types())
      [copied_node] = copy.nodes

      assert copied_node.form_id != source_node.form_id

      copied_form = Forms.get(copied_node.form_id)
      assert copied_form.copied_from_form_id == source_node.form_id
      assert copied_form.owner_flow_id == copy.id

      # The stale property copy was overwritten — a copied node must never
      # point back at the original form template through the properties copy
      assert copied_node.properties["form_id"] == copied_node.form_id
    end

    test "copy keeps catalog forms as shared references" do
      {:ok, catalog_form} = Forms.create(%{name: "Shared W-2"})
      {:ok, flow} = Flows.create()

      node_attrs = %{
        form_id: catalog_form.id,
        properties: %{"type" => "step", "data" => %{"label" => "Shared W-2", "kind" => "form"}}
      }

      {:ok, _} = Flows.update(flow, %{nodes: [node_attrs]})

      {:ok, copy} = Flows.copy(Flows.get(flow.id), host_types())
      [copied_node] = copy.nodes

      assert copied_node.form_id == catalog_form.id
    end

    test "delete refuses a catalog form that steps point at" do
      {:ok, owner} = Forms.create(%{name: "Owner contact"})
      flow = flow_reusing(owner, "Dog License")

      assert {:error, :in_use} = Forms.delete(owner)
      assert Forms.get(owner.id) != nil

      # Removing the step is what frees it
      {:ok, _} = Flows.update(Flows.get(flow.id), %{nodes: []})
      assert {:ok, _} = Forms.delete(Forms.get(owner.id))
    end

    test "publishing a shared form reaches every flow using it; reusing it moves nothing" do
      {owner, v1} = published_form(%{"fields" => [%{"name" => "email"}]})

      dog = flow_reusing(owner, "Dog License")
      dog_instance = start_at_step(dog)
      assert dog_instance.template_form_version_id == v1.id

      # A second flow starts reusing the form while the dog owner is mid-form
      cat = flow_reusing(owner, "Cat License")
      assert reload(dog_instance).template_form_version_id == v1.id
      cat_instance = start_at_step(cat)

      # The dialog's attribution, by root flow, flows by name
      assert Forms.instance_counts_by_flow(owner.id) == [
               %{flow_id: cat.id, flow_name: "Cat License", drafts: 1, submitted: 0},
               %{flow_id: dog.id, flow_name: "Dog License", drafts: 1, submitted: 0}
             ]

      # One publish, both flows: the reason to share, and the thing to see
      # coming
      {:ok, v2} = publish_next(owner, v1)

      assert reload(dog_instance).template_form_version_id == v2.id
      assert reload(cat_instance).template_form_version_id == v2.id
    end

    test "a reopening publish moves where a journey is open, and the sweep catches the cache up" do
      {owner, v1} = published_form()
      {dog, step} = flow_through_two(owner, "Dog License")
      instance = start_at_step(dog, step)
      journey = Instances.Flows.get(instance.instance_flow_id)
      assert journey.next_path == [step.id]

      {:ok, _} = Instances.Forms.update_status(journey, [step.id], :completed, data: %{})
      journey = Instances.Flows.get(journey.id)
      # Submitted, so the flow has moved past it - and the journey is still
      # in progress, a form behind it, which is what leaves the publish
      # anything to reach
      assert journey.status == "in_progress"
      refute journey.next_path == [step.id]
      computed_before = journey.next_computed_at

      {:ok, _v2} = publish_next(owner, v1, reopen_submitted: true)

      # The publish reopened the form and moved where the flow is open,
      # and the cache does not know yet - what the sweep exists for
      assert reload(instance).status == "in_progress"
      refute Instances.Flows.get(journey.id).next_path == [step.id]

      assert {:ok, 1} = Forms.refresh_next_positions(owner.id)

      swept = Instances.Flows.get(journey.id)
      assert swept.next_path == [step.id]
      assert DateTime.compare(swept.next_computed_at, computed_before) == :gt
    end

    test "the sweep reaches every root a catalog form is in, and skips standalone instances" do
      {owner, v1} = published_form()
      {dog, dog_step} = flow_through_two(owner, "Dog License")
      {cat, cat_step} = flow_through_two(owner, "Cat License")

      journeys =
        for {flow, step} <- [{dog, dog_step}, {cat, cat_step}] do
          instance = start_at_step(flow, step)
          journey = Instances.Flows.get(instance.instance_flow_id)
          {:ok, _} = Instances.Forms.update_status(journey, [step.id], :completed, data: %{})
          Instances.Flows.get(journey.id)
        end

      # Filled outside any flow: nothing to sweep, nothing to crash on
      insert_instance(v1, status: "completed", completed_at: DateTime.utc_now())

      assert Forms.sweep_size(owner.id) == 2

      {:ok, _v2} = publish_next(owner, v1, reopen_submitted: true)
      assert {:ok, 2} = Forms.refresh_next_positions(owner.id)

      for {journey, step} <- Enum.zip(journeys, [dog_step, cat_step]) do
        assert Instances.Flows.get(journey.id).next_path == [step.id]
      end
    end

    test "sweep_size counts journeys still in progress of the roots reached, and no others" do
      {owner, _v1} = published_form()
      {dog, step} = flow_through(owner, "Dog License")

      # Two journeys in the root, one of them completed; a third journey of
      # an unrelated flow
      _open = start_at_step(dog, step)
      finished = start_at_step(dog, step)
      {:ok, _} = Instances.Flows.complete(Instances.Flows.get(finished.instance_flow_id))
      {other, other_step} = flow_through(elem(published_form(), 0), "Other")
      _elsewhere = start_at_step(other, other_step)

      assert Forms.sweep_size(owner.id) == 1
      assert [%{flow_name: "Dog License"}] = Forms.instance_counts_by_flow(owner.id)
    end
  end

  # A root "forms" flow whose one step points at the catalog form
  defp flow_reusing(form, name) do
    {:ok, flow} = Flows.create(%{name: name, status: "open"})

    node_attrs = %{
      form_id: form.id,
      properties: %{"type" => "step", "data" => %{"label" => form.name, "kind" => "form"}}
    }

    {:ok, _} = Flows.update(flow, %{nodes: [node_attrs]})
    Flows.get(flow.id)
  end

  # A journey through the flow with its one step's form started
  defp start_at_step(%{nodes: [step]} = flow), do: start_at_step(flow, step)

  defp start_at_step(flow, step) do
    {:ok, journey} = Instances.Flows.create(%{template_flow_id: flow.id, user_id: "owner"})
    {:ok, instance} = Instances.Forms.update_status(journey, [step.id], :in_progress)
    instance
  end

  # Start -> the catalog form -> End: a root flow a journey can actually be
  # open in, which `flow_reusing/2`'s lone step is not (nothing reaches it
  # from Start). Returns the flow and the form's step.
  defp flow_through(form, name) do
    {:ok, flow} = Flows.create(%{name: name, status: "open"})

    [start_node, step, end_node] =
      for {labels, label, attrs} <- [
            {["Start"], "Start", %{}},
            {["Form"], form.name, %{form_id: form.id}},
            {["End"], "End", %{}}
          ] do
        attrs =
          Map.merge(
            %{flow_id: flow.id, labels: labels, properties: %{"data" => %{"label" => label}}},
            attrs
          )

        {:ok, node} =
          FormFlowRepo.insert(
            FormFlow.Data.Templates.Flow.Node.changeset(
              %FormFlow.Data.Templates.Flow.Node{},
              attrs
            )
          )

        node
      end

    for {source, target} <- [{start_node, step}, {step, end_node}] do
      {:ok, _} =
        FormFlowRepo.insert(
          FormFlow.Data.Templates.Flow.Relationship.changeset(
            %FormFlow.Data.Templates.Flow.Relationship{},
            %{flow_id: flow.id, source_id: source.id, target_id: target.id, label: "CONNECTS_TO"}
          )
        )
    end

    {Flows.get(flow.id), step}
  end

  # `flow_through/2` with a second form position after the first, so that
  # submitting the first leaves the journey **in progress**. A publish never
  # touches a form inside a completed journey (the journey rule in
  # `FormFlow.Data.Templates.Forms`), so a one-form flow finishes the moment
  # its form is submitted and has nothing left for a reopening publish to
  # move. Returns the flow and the first form's step.
  defp flow_through_two(form, name) do
    {:ok, trailing} = Forms.create(%{name: "Trailing #{System.unique_integer([:positive])}"})
    [draft] = trailing.versions
    {:ok, _published} = Forms.update_status(draft, :published)

    {flow, step} = flow_through(form, name)
    [end_node] = for n <- flow.nodes, n.labels == ["End"], do: n

    {:ok, second} =
      FormFlowRepo.insert(
        FormFlow.Data.Templates.Flow.Node.changeset(
          %FormFlow.Data.Templates.Flow.Node{},
          %{
            flow_id: flow.id,
            labels: ["Form"],
            form_id: trailing.id,
            properties: %{"data" => %{"label" => trailing.name}}
          }
        )
      )

    [%{id: step_to_end_id}] =
      for r <- flow.relationships, r.source_id == step.id, r.target_id == end_node.id, do: r

    {:ok, _} =
      FormFlowRepo.delete(
        FormFlowRepo.get(FormFlow.Data.Templates.Flow.Relationship, step_to_end_id)
      )

    for {source, target} <- [{step, second}, {second, end_node}] do
      {:ok, _} =
        FormFlowRepo.insert(
          FormFlow.Data.Templates.Flow.Relationship.changeset(
            %FormFlow.Data.Templates.Flow.Relationship{},
            %{flow_id: flow.id, source_id: source.id, target_id: target.id, label: "CONNECTS_TO"}
          )
        )
    end

    {Flows.get(flow.id), step}
  end

  # --- helpers --------------------------------------------------------------

  defp form_node_attrs(label) do
    %{properties: %{"type" => "step", "data" => %{"label" => label, "kind" => "form"}}}
  end

  defp insert_flow do
    {:ok, flow} = Flows.create()
    flow
  end

  # A journey of a flow with the given status, completed when asked. No
  # graph: the publish reads the journey's status and its flow's, nothing
  # else, and `refresh: false` keeps the next-position cache out of it
  defp journey(flow_status \\ "open", journey_status \\ "in_progress") do
    {:ok, flow} = Flows.create(%{status: flow_status})
    {:ok, journey} = Instances.Flows.create(%{template_flow_id: flow.id}, refresh: false)

    case journey_status do
      "completed" ->
        {:ok, journey} = Instances.Flows.complete(journey, refresh: false)
        journey

      "in_progress" ->
        journey
    end
  end

  defp published_form(definition \\ %{}) do
    {:ok, form} = Forms.create(%{name: "Form #{System.unique_integer([:positive])}"})
    [draft] = form.versions
    {:ok, draft} = Forms.update_draft(draft, %{definition: definition})
    {:ok, v1} = Forms.update_status(draft, :published)

    {form, v1}
  end

  defp publish_next(form, based_on, opts \\ []) do
    {:ok, draft} = Forms.create_draft(form.id, based_on: based_on.id)

    Forms.update_status(draft, :published, opts)
  end

  # Inserts the row as given. `Instances.Form.changeset/2` never casts
  # `status` or `completed_at` — completion is `Instances.Forms.update_status/4`'s
  # to write — so a test that needs a completed row sets the struct directly.
  defp insert_instance(version, attrs \\ []) do
    attrs =
      Enum.into(attrs, %{
        template_form_version_id: version.id,
        data: %{},
        status: "in_progress"
      })

    {:ok, instance} = FormFlowRepo.insert(struct(Instances.Form, attrs))

    instance
  end

  defp reload(instance), do: Instances.Forms.get(instance.id)

  defp events_for(instance) do
    FormFlowRepo.all(from(e in Instances.Form.Event, where: e.instance_form_id == ^instance.id))
  end

  describe "slugs" do
    test "a catalog form gets one from the name; an owned form or owned copy has none" do
      {:ok, form} = Forms.create(%{name: "User Information"})
      assert form.slug == "user-inform"
      assert form.properties["slug"] == "user-inform"

      {:ok, root} = FormFlow.Data.Templates.Flows.create()

      # Owned: the step's slug is the handle
      {:ok, owned} = Forms.create(%{name: "Owner Contact", owner_flow_id: root.id})
      assert owned.slug == nil
      refute Map.has_key?(owned.properties, "slug")

      {:ok, copy} = Forms.copy(form, owner_flow_id: root.id)
      assert copy.slug == nil

      {:ok, named} = Forms.copy(form, owner_flow_id: root.id, slug: "userinfo2027")
      assert named.slug == "userinfo2027"

      # A catalog copy suffixes the source's — or, when the source was owned
      # and had none, defaults from the name
      {:ok, promoted} = Forms.copy(owned)
      assert promoted.owner_flow_id == nil
      assert promoted.slug == "owner-conta"
    end

    test "get_by_slug/2 looks up by slug, scoped to a tenant when asked" do
      {:ok, plain} = Forms.create(%{name: "Intake"})
      {:ok, acme} = Forms.create(%{name: "Intake (Acme)", slug: "intake", tenant_id: "acme"})

      assert Forms.get_by_slug("intake", tenant_id: "acme").id == acme.id
      assert Forms.get_by_slug("intake", tenant_id: "globex") == nil
      assert Forms.get_by_slug("nope") == nil

      {:ok, _} = Forms.delete(acme)
      assert Forms.get_by_slug("intake").id == plain.id
    end
  end
end
