defmodule FormFlow.Config.PropertyTest do
  use ExUnit.Case, async: true

  alias FormFlow.Config.Property

  test "a property starts as a text field that is neither required nor cleared on copy" do
    property = %Property{id: "name", name: "Name"}

    assert property.type == :text
    assert property.required == false
    assert property.clear_on_copy == false
  end

  test "the form pointers are both choice types, and both are offered" do
    assert :related_form in Property.types()
    assert :related_form_in_any_flow in Property.types()

    assert Property.choice?(%Property{id: "a", name: "A", type: :related_form})
    assert Property.choice?(%Property{id: "b", name: "B", type: :related_form_in_any_flow})
    refute Property.choice?(%Property{id: "c", name: "C", type: :text})
  end

  describe "a related form in any flow" do
    test "names its flow and the position inside it, and reads back the same" do
      value = Property.flow_position("f1", ["n1", "n2"])

      assert value == "flow:f1/n1/n2"
      assert Property.parse_flow_position(value) == {"f1", ["n1", "n2"]}
    end

    test "does not look like a path, so a copy will not rebase it as one" do
      flow_id = Ecto.UUID.generate()
      node_id = Ecto.UUID.generate()

      segments = Property.flow_position(flow_id, [node_id]) |> String.split("/")

      refute Enum.all?(segments, &match?({:ok, _uuid}, Ecto.UUID.cast(&1)))
    end

    test "reads nothing back from a value that is not one" do
      assert Property.parse_flow_position(nil) == nil
      assert Property.parse_flow_position("") == nil
      assert Property.parse_flow_position("n1/n2") == nil
      assert Property.parse_flow_position("flow:f1") == nil
      assert Property.parse_flow_position(["f1", "n1"]) == nil
    end
  end
end
