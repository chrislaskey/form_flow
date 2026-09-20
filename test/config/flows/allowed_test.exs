defmodule FormFlow.Config.Flows.AllowedTest do
  @moduledoc """
  What a host may write in the `flows` attr, and what `new/1` refuses.

  The two refusals are the point of the struct: a flow named twice or not
  at all, and a page that would start a journey it then will not open.
  """

  use ExUnit.Case, async: true

  alias FormFlow.Config.Flows.Allowed
  alias FormFlow.Data.Templates.Flow

  describe "new/1" do
    test "a slug alone is a fully enabled flow" do
      allowed = Allowed.new(flow_slug: "dog-license")

      assert allowed.flow_slug == "dog-license"
      assert allowed.start
      assert allowed.continue
    end

    test "start: false leaves the journeys workable" do
      allowed = Allowed.new(flow_slug: "dog-license", start: false)

      refute allowed.start
      assert allowed.continue
    end

    test "both false is a flow that is listed and read-only" do
      allowed = Allowed.new(flow_slug: "dog-license", start: false, continue: false)

      refute allowed.start
      refute allowed.continue
    end

    test "refuses a flow that could be started and then not worked in" do
      assert_raise ArgumentError, ~r/startable and not continuable/, fn ->
        Allowed.new(flow_slug: "dog-license", start: true, continue: false)
      end
    end

    test "refuses a struct naming no flow" do
      assert_raise ArgumentError, ~r/none was given/, fn -> Allowed.new(start: false) end
    end

    test "refuses a struct naming a flow twice" do
      assert_raise ArgumentError, ~r/exactly one/, fn ->
        Allowed.new(flow_id: Ecto.UUID.generate(), flow_slug: "dog-license")
      end
    end

    test "takes a map as well as a keyword list" do
      assert Allowed.new(%{flow_slug: "dog-license"}).flow_slug == "dog-license"
    end
  end

  describe "allows?/2" do
    test "start and continue read their fields" do
      allowed = Allowed.new(flow_slug: "dog-license", start: false)

      refute Allowed.allows?(allowed, :start)
      assert Allowed.allows?(allowed, :continue)
    end

    test "see is answered by naming the flow at all" do
      allowed = Allowed.new(flow_slug: "dog-license", start: false, continue: false)

      assert Allowed.allows?(allowed, :see)
    end
  end

  describe "names?/2" do
    test "matches by whichever handle is set" do
      id = Ecto.UUID.generate()
      flow = %Flow{id: id, slug: "dog-license"}

      assert Allowed.names?(Allowed.new(flow_id: id), flow)
      assert Allowed.names?(Allowed.new(flow_slug: "dog-license"), flow)
      assert Allowed.names?(Allowed.new(flow: flow), flow)
    end

    test "another flow is named by nobody" do
      flow = %Flow{id: Ecto.UUID.generate(), slug: "cat-license"}

      refute Allowed.names?(Allowed.new(flow_slug: "dog-license"), flow)
      refute Allowed.names?(Allowed.new(flow_id: Ecto.UUID.generate()), flow)
    end

    test "a flow with no slug is not matched by a slug entry" do
      flow = %Flow{id: Ecto.UUID.generate(), slug: nil}

      refute Allowed.names?(Allowed.new(flow_slug: "dog-license"), flow)
    end
  end

  describe "handle/1" do
    test "answers which handle is set" do
      assert Allowed.handle(Allowed.new(flow_slug: "dog-license")) ==
               {:flow_slug, "dog-license"}
    end

    test "raises on a hand-written struct naming nothing" do
      assert_raise ArgumentError, ~r/none was given/, fn -> Allowed.handle(%Allowed{}) end
    end
  end
end
