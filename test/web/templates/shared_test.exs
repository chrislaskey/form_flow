defmodule FormFlow.Web.Templates.SharedTest do
  use ExUnit.Case, async: true

  alias FormFlow.Config.Flows.Perspective
  alias FormFlow.Config.Property
  alias FormFlow.Data.Instances.FormProgress
  alias FormFlow.Data.Templates.Flow
  alias FormFlow.Web.Templates.Shared

  @perspectives [
    %Perspective{id: "applicant", name: "Applicant"},
    %Perspective{id: "reviewer", name: "Reviewer"}
  ]
  @flow_types [
    %FormFlow.Config.Flows.Type{id: "wizard", module: __MODULE__, name: "Wizard"},
    %FormFlow.Config.Flows.Type{
      id: "review",
      module: __MODULE__,
      name: "Review",
      perspectives: @perspectives
    }
  ]

  @name %Property{id: "name", name: "Name", required: true}
  @greeting %Property{id: "greeting", name: "Greeting", type: :comment, default_value: "Hello"}
  @count %Property{id: "count", name: "Count", type: :number}
  @size %Property{
    id: "size",
    name: "Size",
    type: :dropdown,
    options: [{"Small", "s"}, {"Large", "l"}]
  }
  @days %Property{
    id: "days",
    name: "Days",
    type: :checkbox,
    options: [{"Mon", "mon"}, {"Tue", "tue"}]
  }
  @urgent %Property{id: "urgent", name: "Urgent", type: :boolean}
  @types [
    %FormFlow.Config.Forms.Type{id: "plain", module: __MODULE__, name: "Plain"},
    %FormFlow.Config.Forms.Type{
      id: "typed",
      module: __MODULE__,
      name: "Typed",
      properties: [@name, @greeting]
    }
  ]

  test "properties/2 are the picked type's — none for no type or an unknown one" do
    assert Shared.properties(@types, "typed") == [@name, @greeting]
    assert Shared.properties(@types, "plain") == []
    assert Shared.properties(@types, nil) == []
    assert Shared.properties(@types, "nonsense") == []
  end

  test "field names carry a prefix, so a property can't collide with the form's own fields" do
    assert Shared.field_name(@name) == "property_name"
  end

  test "every property type is a DynamicForm question type, number being a text input" do
    assert Shared.field_type(@name) == "text"
    assert Shared.field_type(@greeting) == "comment"
    assert Shared.field_type(@size) == "dropdown"
    assert Shared.field_type(@days) == "checkbox"
    assert Shared.field_type(@urgent) == "boolean"

    source = %Property{id: "source", name: "Source", type: :related_form}
    assert Shared.field_type(%Property{source | options: [{"Intake", "intake"}]}) == "dropdown"
    # With no earlier forms to offer it renders read-only text with its note
    assert Shared.field_type(%Property{source | options: []}) == "text"
    assert Shared.read_only?(%Property{source | options: []})
    refute Shared.read_only?(@size)

    assert Shared.field_type(@count) == "text"
    assert Shared.input_type(@count) == "number"
    assert is_nil(Shared.input_type(@name))
  end

  test "only the choice types carry options" do
    assert Shared.field_options(@size) == [{"Small", "s"}, {"Large", "l"}]
    assert Shared.field_options(%Property{@size | options: nil}) == []
    assert is_nil(Shared.field_options(@name))
    assert is_nil(Shared.field_options(@urgent))
  end

  test "field_data/2 lays stored values under the field names, one per property" do
    assert Shared.field_data([@name, @greeting], %{"name" => "Ada"}) ==
             %{property_name: "Ada", property_greeting: nil}
  end

  test "payload_property_values/2 picks the properties' values out of a payload, dropping blanks" do
    payload = %{
      name: "Typed",
      property_name: "Ada",
      property_greeting: "",
      property_days: [],
      property_urgent: false,
      property_other: "x"
    }

    assert Shared.payload_property_values(payload, [@name, @greeting, @days, @urgent]) ==
             %{"name" => "Ada", "urgent" => false}

    assert Shared.payload_property_values(payload, []) == %{}
  end

  test "earlier_forms/2 cuts a flow's forms at the node being edited, in flow order" do
    documents = %FormFlow.Data.Templates.Flow.Node{
      id: "documents",
      labels: ["Subflow"],
      properties: %{"data" => %{"label" => "Documents"}}
    }

    forms = [
      %FormProgress{path: ["intake"], label: "Intake", ancestors: []},
      %FormProgress{path: ["documents", "id"], label: "ID", ancestors: [documents]},
      %FormProgress{
        path: ["documents", "proof"],
        label: "Proof of address",
        ancestors: [documents]
      },
      %FormProgress{path: ["review"], label: "Review", ancestors: []}
    ]

    # A form node: everything before it, labeled as the user-facing pages do
    assert Shared.earlier_forms(forms, "review") ==
             [
               {"Intake", "intake"},
               {"Documents / ID", "documents/id"},
               {"Documents / Proof of address", "documents/proof"}
             ]

    # A form inside a subflow: the cut is that form, not the subflow
    assert Shared.earlier_forms(forms, "proof") == [
             {"Intake", "intake"},
             {"Documents / ID", "documents/id"}
           ]

    # A subflow node: nothing inside it or after it
    assert Shared.earlier_forms(forms, "documents") == [{"Intake", "intake"}]

    # The first form, or a node the tree doesn't have yet, gets what precedes it
    assert Shared.earlier_forms(forms, "intake") == []
    assert length(Shared.earlier_forms(forms, "unsaved")) == 4
  end

  test "display_value/2 shows a choice by its label, a list joined, a boolean as Yes or No" do
    assert Shared.display_value(@size, "l") == "Large"
    assert Shared.display_value(@size, "unknown") == "unknown"
    assert Shared.display_value(@days, ["mon", "tue"]) == "Mon, Tue"
    assert Shared.display_value(@urgent, true) == "Yes"
    assert Shared.display_value(@urgent, false) == "No"
    assert Shared.display_value(@count, Decimal.new("3")) == "3"

    source = %Property{
      id: "source",
      name: "Source",
      type: :related_form,
      options: [{"Intake", "intake"}]
    }

    assert Shared.display_value(source, "intake") == "Intake"
    assert Shared.display_value(source, "gone") == "Missing — no longer in this flow"
    assert Shared.display_value(@name, "Ada") == "Ada"
  end

  test "effective_type/2 is the stored id, or the first type an unset one amounts to" do
    assert Shared.effective_type(@flow_types, "review") == "review"
    assert Shared.effective_type(@flow_types, "unknown") == "unknown"
    assert Shared.effective_type(@flow_types, nil) == "wizard"
    assert Shared.effective_type([], nil) == nil
  end

  describe "perspectives" do
    test "the chosen type's; none for no type or a type declaring none" do
      assert Shared.perspectives(@flow_types, "review") == @perspectives
      assert Shared.perspectives(@flow_types, "wizard") == []
      assert Shared.perspectives(@flow_types, nil) == []
      assert Shared.perspectives(@flow_types, "unknown") == []
    end

    test "all_perspectives/1 is every type's, once each" do
      twice = [
        %FormFlow.Config.Flows.Type{
          id: "x",
          module: __MODULE__,
          name: "X",
          perspectives: @perspectives
        }
      ]

      assert Shared.all_perspectives(@flow_types ++ twice) == @perspectives
      assert Shared.all_perspectives([]) == []
    end

    test "the field's options and help text, with a note for a stale stored id" do
      perspectives = Shared.perspectives(@flow_types, "review")

      assert Shared.perspective_options(perspectives) == [
               {"Applicant", "applicant"},
               {"Reviewer", "reviewer"}
             ]

      current = %Flow{label: "forms", properties: %{"perspectives" => ["reviewer"]}}
      refute Shared.perspectives_description(current, perspectives) =~ "no longer offered"

      stale = %Flow{label: "forms", properties: %{"perspectives" => ["reviewer", "approver"]}}

      assert Shared.perspectives_description(stale, perspectives) =~
               "approver is no longer offered"
    end
  end
end
