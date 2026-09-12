defmodule FormFlow.Data.Templates.Form.PrefillTest do
  use ExUnit.Case, async: true

  alias FormFlow.Data.Templates.Form.Prefill

  test "requires a name — it is the key the set is stored under" do
    refute Prefill.changeset(%Prefill{}, %{data: %{"wages" => "1000"}}).valid?

    changeset = Prefill.changeset(%Prefill{}, %{name: "Happy path"})

    assert changeset.valid?
    assert changeset.changes.name == "Happy path"
  end

  test "trims the name, so two prefills cannot differ by a space" do
    changeset = Prefill.changeset(%Prefill{}, %{name: "  Happy path  "})

    assert changeset.changes.name == "Happy path"
  end

  test "casts the answers, what it is for, and who saved it" do
    changeset =
      Prefill.changeset(%Prefill{}, %{
        name: "Happy path",
        description: "Everything filled in.",
        data: %{"wages" => "1000"},
        user_id: "admin"
      })

    assert changeset.valid?
    assert changeset.changes.data == %{"wages" => "1000"}
    assert changeset.changes.description == "Everything filled in."
    assert changeset.changes.user_id == "admin"
  end

  test "timestamps are not castable — the context stamps them as it writes" do
    changeset =
      Prefill.changeset(%Prefill{}, %{name: "Happy path", inserted_at: DateTime.utc_now()})

    assert changeset.valid?
    refute Map.has_key?(changeset.changes, :inserted_at)
  end

  test "round trips through the stored entry" do
    saved_at = DateTime.utc_now()

    prefill = %Prefill{
      name: "Happy path",
      description: "Everything filled in.",
      data: %{"wages" => "1000"},
      user_id: "admin",
      inserted_at: saved_at,
      updated_at: saved_at
    }

    entry = Prefill.to_entry(prefill)

    assert entry == %{
             "data" => %{"wages" => "1000"},
             "description" => "Everything filled in.",
             "user_id" => "admin",
             "inserted_at" => DateTime.to_iso8601(saved_at),
             "updated_at" => DateTime.to_iso8601(saved_at)
           }

    assert Prefill.from_entry("Happy path", entry) == prefill
  end

  test "an entry says only what was set" do
    assert Prefill.to_entry(%Prefill{name: "Happy path"}) == %{"data" => %{}}
  end

  test "reads an entry that has only answers" do
    prefill = Prefill.from_entry("Happy path", %{"data" => %{"wages" => "1000"}})

    assert prefill.name == "Happy path"
    assert prefill.data == %{"wages" => "1000"}
    assert prefill.description == nil
    assert prefill.inserted_at == nil
  end

  test "an entry is a map with its answers under data" do
    assert Prefill.entry?(%{"data" => %{}})
    refute Prefill.entry?(%{"data" => "wages"})
    refute Prefill.entry?(%{"wages" => "1000"})
    refute Prefill.entry?("wages")
  end
end
