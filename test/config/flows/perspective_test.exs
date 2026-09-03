defmodule FormFlow.Config.Flows.PerspectiveTest do
  use ExUnit.Case, async: true

  alias FormFlow.Config.Flows.Perspective
  alias FormFlow.Context
  alias FormFlow.Data.Templates.Flow

  @applicant %Perspective{id: "applicant", name: "Applicant"}
  @reviewer %Perspective{id: "reviewer", name: "Reviewer", metadata: %{desk: :regional}}
  @enabled [@applicant, @reviewer]

  defp flow(ids), do: %Flow{label: "forms", properties: %{"perspectives" => ids}}

  describe "the stored ids" do
    test "ids/1 reads them; a flow storing none is for everyone" do
      assert Perspective.ids(flow(["reviewer"])) == ["reviewer"]
      assert Perspective.ids(%Flow{properties: %{}}) == []
      assert Perspective.ids(nil) == []
    end

    test "for_flow/2 resolves them to the enabled structs, in the enabled order, dropping stale ids" do
      assert Perspective.for_flow(flow(["reviewer", "applicant", "gone"]), @enabled) ==
               [@applicant, @reviewer]

      assert Perspective.for_flow(flow([]), @enabled) == []
    end

    test "stale_ids/2 names what the config no longer offers" do
      assert Perspective.stale_ids(flow(["reviewer", "gone"]), @enabled) == ["gone"]
      assert Perspective.stale_ids(flow(["reviewer"]), @enabled) == []
    end

    test "put_ids/2 stores a list, and removes the key for none" do
      assert Perspective.put_ids(%{"k" => "v"}, ["applicant"]) == %{
               "k" => "v",
               "perspectives" => ["applicant"]
             }

      assert Perspective.put_ids(%{"k" => "v", "perspectives" => ["x"]}, []) == %{"k" => "v"}
    end
  end

  test "normalize/1 takes the attr as a string or a list" do
    assert Perspective.normalize(nil) == []
    assert Perspective.normalize("reviewer") == ["reviewer"]
    assert Perspective.normalize(["reviewer", :applicant]) == ["reviewer", "applicant"]
  end

  describe "visible?/1" do
    test "a flow for one of the viewer's perspectives is visible" do
      context = %Context{subflow: flow(["reviewer"]), perspectives: ["reviewer"]}
      assert Perspective.visible?(context)

      shared = %Context{subflow: flow(["applicant", "reviewer"]), perspectives: ["reviewer"]}
      assert Perspective.visible?(shared)
    end

    test "a flow for another perspective is not" do
      refute Perspective.visible?(%Context{
               subflow: flow(["reviewer"]),
               perspectives: ["applicant"]
             })
    end

    test "a flow naming no perspective is for everyone" do
      assert Perspective.visible?(%Context{subflow: flow([]), perspectives: ["applicant"]})
      assert Perspective.visible?(%Context{subflow: nil, perspectives: ["applicant"]})
    end

    test "a viewer with no perspective sees everything" do
      assert Perspective.visible?(%Context{subflow: flow(["reviewer"]), perspectives: []})
      assert Perspective.visible?(%Context{subflow: flow(["reviewer"]), perspectives: nil})
    end
  end
end
