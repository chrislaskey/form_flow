defmodule FormFlow.Web.Components.Forms.Types.ReviewTest do
  use ExUnit.Case, async: true

  alias FormFlow.Data.Instances
  alias FormFlow.Data.Instances.Form.Event
  alias FormFlow.Data.Instances.FormProgress
  alias FormFlow.Web.Components.Forms.Types.Review

  # The review was completed at this instant; source events are placed
  # relative to it
  @reviewed_at ~U[2026-09-01 12:00:00.000000Z]
  @v1 "version-1"
  @v2 "version-2"

  defp event(kind, seconds_after, opts \\ []) do
    %Event{
      event: kind,
      inserted_at: DateTime.add(@reviewed_at, seconds_after, :second),
      to_version_id: opts[:to_version_id]
    }
  end

  defp completion, do: event("status_changed", 0)

  defp instance(id \\ "intake-1", version \\ @v1) do
    %Instances.Form{id: id, template_form_version_id: version, data: %{"name" => "Grace"}}
  end

  defp source(instance) do
    %FormProgress{path: ["intake"], label: "Intake", status: :completed, instance: instance}
  end

  defp snapshot(overrides \\ %{}) do
    Map.merge(
      %{
        "path" => "intake",
        "instance_id" => "intake-1",
        "version_id" => @v1,
        "data" => %{"name" => "Ada"}
      },
      overrides
    )
  end

  describe "staleness/4" do
    test "never reviewed: no completion, or a completion with no record" do
      assert Review.staleness(nil, nil, source(instance()), []) == :never_reviewed
      assert Review.staleness(nil, snapshot(), source(instance()), []) == :never_reviewed
      assert Review.staleness(completion(), nil, source(instance()), []) == :never_reviewed
    end

    test "nothing was reviewed: current, whatever the source did since" do
      nothing = snapshot(%{"instance_id" => nil})
      later = [event("created", 30), event("status_changed", 60)]

      assert Review.staleness(completion(), nothing, source(instance()), later) == :current
      assert Review.staleness(completion(), nothing, source(nil), []) == :current
    end

    test "redacted wins over the identity checks" do
      redacted = snapshot(%{"data" => %{}, "redacted_at" => "2026-09-02T00:00:00Z"})

      assert Review.staleness(completion(), redacted, nil, []) == :redacted
      assert Review.staleness(completion(), redacted, source(nil), []) == :redacted

      assert Review.staleness(completion(), redacted, source(instance("intake-2")), []) ==
               :redacted
    end

    test "deleted: the source has no instance now" do
      gone = {:stale, :deleted, structure_changed?: false}

      assert Review.staleness(completion(), snapshot(), source(nil), []) == gone
      assert Review.staleness(completion(), snapshot(), nil, []) == gone
    end

    test "replaced: another instance at the position, its structure compared to the record" do
      assert Review.staleness(completion(), snapshot(), source(instance("intake-2")), [
               event("created", 30)
             ]) == {:stale, :replaced, structure_changed?: false}

      assert Review.staleness(completion(), snapshot(), source(instance("intake-2", @v2)), []) ==
               {:stale, :replaced, structure_changed?: true}
    end

    test "current: nothing on the source's trail is newer than the review" do
      # The same instant is not newer
      trail = [event("created", -120), event("status_changed", -60), event("status_changed", 0)]

      assert Review.staleness(completion(), snapshot(), source(instance()), trail) == :current
      assert Review.staleness(completion(), snapshot(), source(instance()), []) == :current
    end

    test "resubmitted: the source was reopened and submitted again" do
      trail = [
        event("created", -120),
        event("status_changed", -60),
        event("reopened", 30),
        event("status_changed", 60)
      ]

      assert Review.staleness(completion(), snapshot(), source(instance()), trail) ==
               {:stale, :resubmitted, structure_changed?: false}
    end

    test "reopened by a user, or migrated by a publish policy that reopens" do
      by_user = [event("status_changed", -60), event("reopened", 30)]

      assert Review.staleness(completion(), snapshot(), source(instance()), by_user) ==
               {:stale, :reopened, structure_changed?: false}

      by_policy = [event("status_changed", -60), event("reopened", 30, to_version_id: @v2)]

      assert Review.staleness(
               completion(),
               snapshot(),
               source(instance("intake-1", @v2)),
               by_policy
             ) ==
               {:stale, :migrated, structure_changed?: true}
    end

    test "migrated: a publish policy moved the pin without reopening" do
      trail = [event("status_changed", -60), event("migrated", 30, to_version_id: @v2)]

      assert Review.staleness(completion(), snapshot(), source(instance("intake-1", @v2)), trail) ==
               {:stale, :migrated, structure_changed?: true}
    end

    test "the latest event is the headline; a structure change rides along" do
      trail = [event("migrated", 30, to_version_id: @v2), event("status_changed", 60)]

      assert Review.staleness(completion(), snapshot(), source(instance("intake-1", @v2)), trail) ==
               {:stale, :resubmitted, structure_changed?: true}
    end

    test "a version mismatch alone marks the structure changed" do
      trail = [event("status_changed", 60)]

      assert Review.staleness(completion(), snapshot(), source(instance("intake-1", @v2)), trail) ==
               {:stale, :resubmitted, structure_changed?: true}
    end
  end

  describe "diff/4" do
    defp definition(elements) do
      DynamicForm.Parser.FromData.parse!(%{"elements" => elements})
    end

    defp intake_v1 do
      definition([
        %{"type" => "text", "name" => "name", "title" => "Name"},
        %{"type" => "text", "name" => "email", "title" => "Email"},
        %{"type" => "checkbox", "name" => "tags", "title" => "Tags", "choices" => ["a", "b"]}
      ])
    end

    test "changed, added, and removed answers; unchanged ones are left out" do
      old = %{"name" => "Ada", "email" => "ada@example.com", "tags" => ["a"]}
      new = %{"name" => "Grace", "tags" => ["a"], "phone" => "555"}

      assert Review.diff(old, new, intake_v1(), intake_v1()) == [
               {"Name", "Name", "Ada", "Grace"},
               {"Email", "Email", "ada@example.com", ""},
               {"phone", "phone", "", "555"}
             ]
    end

    test "lists, maps, booleans, and numbers render through one rule" do
      old = %{"tags" => ["a", "b"], "address" => %{"city" => "Boston"}, "ok" => true, "n" => 1}
      new = %{"tags" => ["b"], "address" => %{"city" => "Salem"}, "ok" => false, "n" => 2}

      assert Review.diff(old, new, intake_v1(), intake_v1()) == [
               {"Tags", "Tags", "a, b", "b"},
               {"address", "address", ~s({"city":"Boston"}), ~s({"city":"Salem"})},
               {"n", "n", "1", "2"},
               {"ok", "ok", "Yes", "No"}
             ]
    end

    test "titles come from each side's definition when the structure changed" do
      intake_v2 =
        definition([
          %{"type" => "text", "name" => "name", "title" => "Full name"},
          %{"type" => "text", "name" => "phone", "title" => "Phone"}
        ])

      old = %{"name" => "Ada", "email" => "ada@example.com"}
      new = %{"name" => "Grace", "phone" => "555"}

      assert Review.diff(old, new, intake_v1(), intake_v2) == [
               {"Name", "Full name", "Ada", "Grace"},
               {"phone", "Phone", "", "555"},
               {"Email", "email", "ada@example.com", ""}
             ]
    end

    test "titles inside panels are found; missing definitions fall back to keys" do
      paneled =
        definition([
          %{
            "type" => "panel",
            "name" => "contact",
            "elements" => [%{"type" => "text", "name" => "email", "title" => "Email address"}]
          }
        ])

      assert Review.diff(%{"email" => "a"}, %{"email" => "b"}, paneled, paneled) ==
               [{"Email address", "Email address", "a", "b"}]

      assert Review.diff(%{"email" => "a"}, %{"email" => "b"}, nil, nil) ==
               [{"email", "email", "a", "b"}]
    end

    test "nothing differs, nothing is listed" do
      assert Review.diff(%{"name" => "Ada"}, %{"name" => "Ada"}, intake_v1(), intake_v1()) == []
      assert Review.diff(nil, %{}, nil, nil) == []
    end
  end
end
