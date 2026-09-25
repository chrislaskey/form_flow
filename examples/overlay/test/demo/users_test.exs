defmodule Demo.UsersTest do
  use Demo.DataCase, async: false

  alias Demo.Users
  alias FormFlow.Data.Templates.Flows

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

  test "a page's flows are the root flows in its group; applicants may start them, the reviewer may not" do
    {:ok, dog} = Flows.create(%{name: "Dog License", flow_group: Users.pet_licensing()})
    {:ok, cat} = Flows.create(%{name: "Cat License", flow_group: Users.pet_licensing()})
    {:ok, address} = Flows.create(%{name: "Change of Address"})

    for id <- ["dog_owner", "cat_owner", "docs_reader"] do
      allowed = Users.flows(fetch(id), Users.pet_licensing())

      assert Enum.map(allowed, & &1.flow.id) == [dog.id, cat.id]
      assert Enum.all?(allowed, & &1.start), "#{id} should start the flows they list"
      assert Enum.map(Users.flows(fetch(id), :none), & &1.flow.id) == [address.id]
    end

    for id <- ["reviewer", "admin"] do
      allowed = Users.flows(fetch(id), Users.pet_licensing())

      assert Enum.map(allowed, & &1.flow.id) == [dog.id, cat.id],
             "#{id} should be about the pet licenses"

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
