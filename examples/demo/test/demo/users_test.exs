defmodule Demo.UsersTest do
  use ExUnit.Case, async: true

  alias Demo.Users

  test "every perspective a user carries is one the demo's flow types declare" do
    declared = Enum.map(DemoWeb.FormFlowLive.Types.perspectives(), & &1.id)
    assert declared == ["applicant", "reviewer"]

    for user <- Users.all(), id <- user.perspectives do
      assert id in declared, "#{user.id} names #{inspect(id)}, which no flow type declares"
    end
  end

  test "the pet owners are applicants, the reviewer a reviewer, the admin both, the reader none" do
    assert perspectives("dog_owner") == ["applicant"]
    assert perspectives("cat_owner") == ["applicant"]
    assert perspectives("reviewer") == ["reviewer"]
    assert perspectives("admin") == ["applicant", "reviewer"]
    assert perspectives("docs_reader") == []
  end

  test "the pet owners list their own journeys, the reviewer and admin everyone's" do
    assert Users.instances(fetch("dog_owner")) == nil
    assert Users.instances(fetch("cat_owner")) == nil
    assert Users.instances(fetch("docs_reader")) == nil

    for id <- ["reviewer", "admin"] do
      assert %Ecto.Query{} = Users.instances(fetch(id)),
             "#{id} should list everyone's journeys"
    end
  end

  test "the applicants get every flow, the reviewer the two licenses and no Start" do
    assert Users.flows(fetch("dog_owner")) == nil
    assert Users.flows(fetch("cat_owner")) == nil
    assert Users.flows(fetch("docs_reader")) == nil

    for id <- ["reviewer", "admin"] do
      allowed = Users.flows(fetch(id))

      assert Enum.map(allowed, & &1.flow_slug) == ["dog-license", "cat-license"],
             "#{id} should be about the two pet licenses"

      for entry <- allowed do
        refute entry.start, "#{id} should start no journeys of their own"
        assert entry.continue, "#{id} should work inside the journeys they list"
      end
    end
  end

  test "every user says whose journeys their pages list" do
    for user <- Users.all() do
      assert user.journeys in [:own, :everyone],
             "#{user.id} has journeys: #{inspect(user.journeys)}"
    end
  end

  defp perspectives(id), do: fetch(id).perspectives

  defp fetch(id) do
    {:ok, user} = Users.fetch(id)
    user
  end
end
