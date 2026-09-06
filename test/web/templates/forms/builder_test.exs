defmodule FormFlow.Web.Templates.Forms.BuilderTest do
  use ExUnit.Case, async: true

  alias FormFlow.Web.Templates.Forms.Builder

  @definition %{
    "title" => "Contact",
    "elements" => [
      %{"type" => "text", "name" => "email", "inputType" => "email", "isRequired" => true},
      %{
        "type" => "dropdown",
        "name" => "subject",
        "title" => "Subject",
        "choices" => ["Sales", %{"value" => "support", "text" => "Support"}]
      },
      %{"type" => "rating", "name" => "score", "rateMin" => 1, "rateMax" => 5},
      %{
        "type" => "html",
        "name" => "intro",
        "html" => "<p>Hi</p>",
        "visibleIf" => "{email} notempty"
      }
    ]
  }

  describe "entries/1" do
    test "one string-keyed entry per element, choices typed one per line" do
      assert [email, subject, score, intro] = Builder.entries(@definition)

      assert email == %{
               "type" => "text",
               "name" => "email",
               "inputType" => "email",
               "isRequired" => true
             }

      assert subject["choices"] == "Sales\nsupport | Support"
      assert score == %{"type" => "rating", "name" => "score", "rateMin" => 1, "rateMax" => 5}
      assert intro["html"] == "<p>Hi</p>"
      assert intro["visibleIf"] == "{email} notempty"
    end

    test "a blank definition, or one without elements, has none" do
      assert Builder.entries(%{}) == []
      assert Builder.entries(%{"title" => "Untitled"}) == []
    end
  end

  describe "definition/2" do
    test "round-trips its own entries and keeps the other top-level keys" do
      assert Builder.definition(@definition, Builder.entries(@definition)) == @definition
    end

    test "accepts a payload's atom-keyed, cast entries" do
      entries = [
        %{type: "text", name: "email", inputType: "email", isRequired: true, title: ""},
        %{type: "rating", name: "score", rateMin: Decimal.new("1"), rateStep: Decimal.new("0.5")},
        %{type: "checkbox", name: "days", choices: "mon | Monday\r\n\r\n tue \n"}
      ]

      assert Builder.definition(%{}, entries) == %{
               "elements" => [
                 %{
                   "type" => "text",
                   "name" => "email",
                   "inputType" => "email",
                   "isRequired" => true
                 },
                 %{"type" => "rating", "name" => "score", "rateMin" => 1, "rateStep" => 0.5},
                 %{
                   "type" => "checkbox",
                   "name" => "days",
                   "choices" => [%{"value" => "mon", "text" => "Monday"}, "tue"]
                 }
               ]
             }
    end

    test "writes only the properties that apply to the element's type" do
      # A hidden field keeps the value it held before the type changed — the
      # choices typed for a dropdown must not follow the element into text
      entry = %{type: "text", name: "email", choices: "a\nb", rateMin: 1, html: "<b>x</b>"}

      assert Builder.definition(%{}, [entry]) == %{
               "elements" => [%{"type" => "text", "name" => "email"}]
             }
    end

    test "an unfinished entry writes what it has, never a null" do
      assert Builder.definition(%{}, [%{type: "text", name: nil, title: "Soon"}]) == %{
               "elements" => [%{"type" => "text", "title" => "Soon"}]
             }
    end

    test "leaves out blanks and an unchecked Required" do
      entry = %{type: "comment", name: "notes", title: "", placeholder: nil, isRequired: false}

      assert Builder.definition(%{}, [entry]) == %{
               "elements" => [%{"type" => "comment", "name" => "notes"}]
             }
    end
  end

  describe "unsupported/1" do
    test "nothing for a blank definition or one the builder covers" do
      assert Builder.unsupported(%{}) == []
      assert Builder.unsupported(@definition) == []
    end

    test "names the element and what it uses" do
      definition = %{
        "elements" => [
          %{"type" => "text", "name" => "ssn", "readOnly" => true, "validators" => []},
          %{"type" => "file", "name" => "scan"},
          %{"type" => "text", "name" => "age", "defaultValue" => 3},
          %{"type" => "dropdown", "name" => "kind", "choices" => [%{"value" => "a"}]},
          %{"type" => "text"}
        ]
      }

      assert Builder.unsupported(definition) == [
               ~s(Element "ssn" uses "readOnly", "validators".),
               ~s(Element "scan" has type "file", which the form builder does not offer.),
               ~s(Element "age" has a "defaultValue" the form builder cannot edit.),
               ~s(Element "kind" has a "choices" the form builder cannot edit.),
               "Element 5 has no name."
             ]
    end

    test "a property outside its type is unsupported, even one the builder knows" do
      definition = %{"elements" => [%{"type" => "text", "name" => "email", "choices" => ["a"]}]}
      assert Builder.unsupported(definition) == [~s(Element "email" uses "choices".)]
    end
  end

  test "complete_entries/1 keeps the entries with both a type and a name" do
    entries = [
      %{type: "text", name: "a"},
      %{type: "text", name: ""},
      %{"type" => nil, "name" => "b"}
    ]

    assert Builder.complete_entries(entries) == [%{type: "text", name: "a"}]
  end

  test "visible_if/1 shows a property's field for its types only, once a type is picked" do
    assert Builder.visible_if("inputType") ==
             "{panel.type} notempty and {panel.type} anyof ['text']"

    assert Builder.visible_if("choices") ==
             "{panel.type} notempty and {panel.type} anyof ['dropdown', 'radiogroup', 'checkbox', 'tagbox']"
  end
end
