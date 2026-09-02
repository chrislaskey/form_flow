defmodule FormFlow.Web.Templates.SharedTest do
  use ExUnit.Case, async: true

  alias FormFlow.Config.Property
  alias FormFlow.Web.Templates.Shared

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

  test "display_value/2 shows a choice by its label, a list joined, a boolean as Yes or No" do
    assert Shared.display_value(@size, "l") == "Large"
    assert Shared.display_value(@size, "unknown") == "unknown"
    assert Shared.display_value(@days, ["mon", "tue"]) == "Mon, Tue"
    assert Shared.display_value(@urgent, true) == "Yes"
    assert Shared.display_value(@urgent, false) == "No"
    assert Shared.display_value(@count, Decimal.new("3")) == "3"
    assert Shared.display_value(@name, "Ada") == "Ada"
  end
end
