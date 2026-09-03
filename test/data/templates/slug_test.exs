defmodule FormFlow.Data.Templates.SlugTest do
  use ExUnit.Case, async: true

  alias FormFlow.Data.Templates.Flow
  alias FormFlow.Data.Templates.Slug

  describe "segment/2" do
    test "one or two words concatenate and truncate to ten characters" do
      assert Slug.segment("Intake", "form") == "intake"
      assert Slug.segment("User Information", "form") == "userinform"
      assert Slug.segment("W-2 Details", "form") == "w2details"
    end

    test "three or more words become initials, keeping numbers whole" do
      assert Slug.segment("Dog License Application 2026", "flow") == "dla2026"
      assert Slug.segment("Form 2 Review", "form") == "f2r"
    end

    test "initials are truncated too when they run long" do
      name = Enum.map_join(1..12, " ", fn _ -> "Word" end)
      assert Slug.segment(name, "flow") == "wwwwwwwwww"
    end

    test "lowercases and strips accents and punctuation" do
      assert Slug.segment("Café Menu", "form") == "cafemenu"
      assert Slug.segment("Q&A: Follow-up!", "form") == "qafollowup"
    end

    test "a name with nothing usable falls back" do
      assert Slug.segment(nil, "flow") == "flow"
      assert Slug.segment("", "flow") == "flow"
      assert Slug.segment("!!! ???", "form") == "form"
    end
  end

  test "join/2 prefixes a child's segment with its containing flow's slug" do
    assert Slug.join("dla2026", "userinform") == "dla2026_userinform"
    assert Slug.join(nil, "userinform") == "userinform"
  end

  describe "rewrite/3" do
    test "swaps the old root prefix for the new one" do
      assert Slug.rewrite("dla2026_userinform", "dla2026", "dla2027") == "dla2027_userinform"
      assert Slug.rewrite("dla2026_docs_intake", "dla2026", "dla2027") == "dla2027_docs_intake"
    end

    test "leaves a slug that is not under the old prefix alone" do
      assert Slug.rewrite("custom", "dla2026", "dla2027") == "custom"
      assert Slug.rewrite("dla20261_x", "dla2026", "dla2027") == "dla20261_x"
    end

    test "is nil-safe on every side" do
      assert Slug.rewrite(nil, "a", "b") == nil
      assert Slug.rewrite("a_x", nil, "b") == "a_x"
      assert Slug.rewrite("a_x", "a", nil) == "a_x"
    end
  end

  describe "validate_slug/2" do
    test "normalizes to lowercase and trims; blank becomes nil" do
      assert Flow.changeset(%Flow{}, %{slug: "  DLA2026 "}).changes.slug == "dla2026"
      refute Map.has_key?(Flow.changeset(%Flow{}, %{slug: "   "}).changes, :slug)
    end

    test "accepts letters, numbers, _ and -; rejects anything else" do
      assert Flow.changeset(%Flow{}, %{slug: "dla2026_user-info"}).valid?

      for bad <- ["with space", "dash-first-is-fine-but-not-this!", "_leading", "über"] do
        changeset = Flow.changeset(%Flow{}, %{slug: bad})
        refute changeset.valid?, "expected #{inspect(bad)} to be refused"
        assert {_message, _opts} = changeset.errors[:slug]
      end
    end

    test "caps the length" do
      assert Flow.changeset(%Flow{}, %{slug: String.duplicate("a", Slug.max_length())}).valid?

      refute Flow.changeset(%Flow{}, %{slug: String.duplicate("a", Slug.max_length() + 1)}).valid?
    end
  end
end
