defmodule FormFlow.Web.Downloads.DocumentTest do
  use ExUnit.Case, async: true

  alias FormFlow.Web.Downloads.Document
  alias FormFlow.Web.Downloads.Document.Section

  describe "any_content?/1" do
    test "is false for a document with no sections at all" do
      refute Document.any_content?(%Document{})
    end

    test "is false when every section is empty — an opened panel nobody filled" do
      document = %Document{sections: [%Section{title: "Address"}, %Section{title: nil}]}

      refute Document.any_content?(document)
    end

    test "is true as soon as one section holds an entry" do
      document = %Document{
        sections: [%Section{title: nil}, %Section{title: "A", entries: [{:text, "hi"}]}]
      }

      assert Document.any_content?(document)
    end
  end

  describe "slugify/2" do
    test "lowercases and joins on the characters a filename should not carry" do
      assert Document.slugify("Dog Licence / Owner details") == "dog-licence-owner-details"
    end

    test "collapses runs and trims the dashes off both ends" do
      assert Document.slugify("  ...Owner   details!  ") == "owner-details"
    end

    test "cuts to 80 characters, trimming a dash the cut lands on" do
      slug = Document.slugify(String.duplicate("ab ", 60))

      assert String.length(slug) <= 80
      refute String.ends_with?(slug, "-")
    end

    test "falls back when nothing survives — a title in a script this drops" do
      assert Document.slugify("日本語", "form") == "form"
      assert Document.slugify("", "form") == "form"
      assert Document.slugify(nil, "form") == "form"
    end
  end
end
