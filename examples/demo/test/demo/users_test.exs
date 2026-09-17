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

  defp perspectives(id) do
    {:ok, user} = Users.fetch(id)
    user.perspectives
  end
end
