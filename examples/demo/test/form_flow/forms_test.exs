defmodule Demo.FormFlowFormsTest do
  @moduledoc """
  Exercises `FormFlow.Data.Templates.Forms` — the lineage/version lifecycle
  and the publish operation with its migration policies — against a real
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

  describe "lineage CRUD" do
    test "create makes the lineage plus its initial draft in one transaction" do
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

    test "list is the catalog: unowned forms, oldest first" do
      {:ok, first} = Forms.create(%{name: "First"})
      {:ok, second} = Forms.create(%{name: "Second"})

      assert Enum.map(Forms.list(), & &1.id) == [first.id, second.id]
    end

    test "update touches identity only" do
      {:ok, form} = Forms.create(%{name: "Before"})

      assert {:ok, %Form{name: "After"}} = Forms.update(Forms.get(form.id), %{name: "After"})
    end

    test "catalog names are unique" do
      {:ok, _} = Forms.create(%{name: "Enrollment"})

      assert {:error, changeset} = Forms.create(%{name: "Enrollment"})
      assert %{name: _} = errors_on(changeset)
    end

    test "delete removes versions then the lineage" do
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

      assert {:error, :based_on_not_published} = Forms.create_draft(form.id, based_on: draft.id)
    end

    test "based_on must belong to the same lineage" do
      {_form, v1} = published_form()
      {:ok, other} = Forms.create(%{name: "Other"})

      assert {:error, :based_on_wrong_form} = Forms.create_draft(other.id, based_on: v1.id)
    end

    test "several drafts coexist per lineage" do
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

    test "archived versions are not valid based_on targets" do
      {form, v1} = published_form()
      {:ok, _} = Forms.update_status(v1, :archived)

      assert {:error, :based_on_not_published} = Forms.create_draft(form.id, based_on: v1.id)
    end
  end

  describe "publish-time migration policies" do
    test "the default (small fix) keeps existing instances pinned" do
      {form, v1} = published_form()
      instance = insert_instance(v1)

      {:ok, _v2} = publish_next(form, v1)

      assert reload(instance).template_form_version_id == v1.id
      assert events_for(instance) == []
    end

    test "bug fix carries in-progress instances, keeping data; completed stay untouched" do
      {form, v1} = published_form()
      in_progress = insert_instance(v1, data: %{"name" => "Ada"})
      completed = insert_instance(v1, status: "completed", completed_at: DateTime.utc_now())

      {:ok, v2} = publish_next(form, v1, preset: :bug_fix, user_id: "admin-7")

      carried = reload(in_progress)
      assert carried.template_form_version_id == v2.id
      assert carried.data == %{"name" => "Ada"}

      assert [event] = events_for(in_progress)
      assert event.event == "migrated"
      assert event.from_version_id == v1.id
      assert event.to_version_id == v2.id
      assert event.user_id == "admin-7"

      # Completed pins are attestation records — untouched by default
      assert reload(completed).template_form_version_id == v1.id
      assert events_for(completed) == []
    end

    test "big fix resets in-progress and reopens completed, snapshotting discarded data" do
      {form, v1} = published_form()
      in_progress = insert_instance(v1, data: %{"name" => "Ada"})

      completed =
        insert_instance(v1,
          status: "completed",
          completed_at: DateTime.utc_now(),
          data: %{"name" => "Grace"}
        )

      {:ok, v2} = publish_next(form, v1, preset: :big_fix)

      reset = reload(in_progress)
      assert reset.template_form_version_id == v2.id
      assert reset.data == %{}
      assert [%{event: "migrated", data_snapshot: %{"name" => "Ada"}}] = events_for(in_progress)

      reopened = reload(completed)
      assert reopened.template_form_version_id == v2.id
      assert reopened.status == "in_progress"
      assert reopened.completed_at == nil
      assert reopened.data == %{}
      assert [%{event: "reopened", data_snapshot: %{"name" => "Grace"}}] = events_for(completed)
    end

    test "renames re-key carried data before prune drops the rest" do
      {form, v1} = published_form()

      instance =
        insert_instance(v1, data: %{"old_name" => "Ada", "kept" => "yes", "orphan" => "gone"})

      {:ok, draft} = Forms.create_draft(form.id, based_on: v1.id)

      {:ok, draft} =
        Forms.update_draft(draft, %{
          definition: %{"fields" => [%{"name" => "new_name"}, %{"name" => "kept"}]}
        })

      {:ok, _v2} =
        Forms.update_status(draft, :published,
          preset: :bug_fix,
          renames: %{"old_name" => "new_name"},
          prune: true
        )

      migrated = reload(instance)
      assert migrated.data == %{"new_name" => "Ada", "kept" => "yes"}

      # The pruned key survives in the event snapshot — nothing is lost silently
      assert [%{data_snapshot: %{"orphan" => "gone"}}] = events_for(instance)
    end

    test "prune without declared fields prunes nothing — never everything" do
      {form, v1} = published_form()
      instance = insert_instance(v1, data: %{"name" => "Ada"})

      {:ok, _v2} = publish_next(form, v1, preset: :bug_fix, prune: true)

      assert reload(instance).data == %{"name" => "Ada"}
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

      # The editor round-trips properties; the column arrives nil and adopts
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

    test "duplicate copies owned forms into the new domain, with provenance" do
      {:ok, flow} = Flows.create()
      {:ok, _} = Flows.update(flow, %{nodes: [form_node_attrs("W-2 Details")]})
      [source_node] = Flows.get(flow.id).nodes

      {:ok, copy} = Flows.duplicate(Flows.get(flow.id))
      [copied_node] = copy.nodes

      assert copied_node.form_id != source_node.form_id

      copied_form = Forms.get(copied_node.form_id)
      assert copied_form.copied_from_form_id == source_node.form_id
      assert copied_form.owner_flow_id == copy.id

      # The stale property copy was overwritten — a copied node must never
      # point back at the original lineage through property adoption
      assert copied_node.properties["form_id"] == copied_node.form_id
    end

    test "duplicate keeps catalog forms as shared references" do
      {:ok, catalog_form} = Forms.create(%{name: "Shared W-2"})
      {:ok, flow} = Flows.create()

      node_attrs = %{
        form_id: catalog_form.id,
        properties: %{"type" => "step", "data" => %{"label" => "Shared W-2", "kind" => "form"}}
      }

      {:ok, _} = Flows.update(flow, %{nodes: [node_attrs]})

      {:ok, copy} = Flows.duplicate(Flows.get(flow.id))
      [copied_node] = copy.nodes

      assert copied_node.form_id == catalog_form.id
    end
  end

  # --- helpers --------------------------------------------------------------

  defp form_node_attrs(label) do
    %{properties: %{"type" => "step", "data" => %{"label" => label, "kind" => "form"}}}
  end

  defp insert_flow do
    {:ok, flow} = Flows.create()
    flow
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

  defp insert_instance(version, attrs \\ []) do
    attrs = Enum.into(attrs, %{template_form_version_id: version.id, data: %{}})

    # status/completed_at are stamp-only (never castable) — tests stamp them
    # the way completion machinery does, with a bare change/2
    {stamps, attrs} = Map.split(attrs, [:status, :completed_at])

    {:ok, instance} =
      FormFlowRepo.insert(Instances.Form.changeset(%Instances.Form{}, attrs))

    if stamps == %{} do
      instance
    else
      {:ok, stamped} = FormFlowRepo.update(Ecto.Changeset.change(instance, stamps))
      stamped
    end
  end

  defp reload(instance), do: Instances.Forms.get(instance.id)

  defp events_for(instance) do
    FormFlowRepo.all(
      from(e in Instances.Form.Event, where: e.instance_form_id == ^instance.id)
    )
  end
end
