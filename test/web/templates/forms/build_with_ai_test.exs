defmodule FormFlow.Web.Templates.Forms.BuildWithAITest do
  use ExUnit.Case, async: true

  alias FormFlow.Config.AI.Request
  alias FormFlow.Web.Templates.Forms.Builder
  alias FormFlow.Web.Templates.Forms.BuildWithAI

  describe "instructions/0" do
    test "lists every element type the form builder offers, and no other" do
      types = for {_label, type} <- Builder.type_options(), do: type

      for type <- types do
        assert BuildWithAI.instructions() =~ "* #{type} — "
      end
    end

    # The assertion that catches a property named the way the builder names it
    # rather than the way a definition spells it: "children" is the entry's
    # key, and an element written with it in is one `unsupported/1` rejects.
    test "lists each type's properties as the definition spells them" do
      for {_label, type} <- Builder.type_options() do
        assert properties_listed_for(type) == Enum.sort(Builder.allowed_properties(type))
      end
    end

    # The model that invented `"groupType": "row"` reasoned aloud that the
    # allowed values were "not specified" — because they were not
    test "spells out the values of the two properties that take a fixed set" do
      instructions = BuildWithAI.instructions()

      assert instructions =~ "* groupType: horizontal, vertical"

      for {_label, group_type} <- Builder.group_type_options() do
        assert instructions =~ group_type
      end

      for {_label, input_type} <- Builder.input_type_options() do
        assert instructions =~ input_type
      end
    end

    test "names the container keys, and never the builder's own" do
      instructions = BuildWithAI.instructions()

      assert "elements" in properties_listed_for("panel")
      assert "templateElements" in properties_listed_for("paneldynamic")
      refute instructions =~ "children"
    end
  end

  describe "request/3" do
    test "carries the model, the definition as it stands, and what the admin asked for" do
      request = BuildWithAI.request("Add a breed field.", ~s({"elements": []}), "openai/gpt-5")

      assert %Request{model: "openai/gpt-5", max_tokens: 16_000} = request
      assert request.system == BuildWithAI.instructions()
      assert request.prompt =~ ~s({"elements": []})
      assert request.prompt =~ "Add a breed field."
    end

    test "takes no model when the configuration offers none to pick" do
      assert %Request{model: nil} = BuildWithAI.request("A dog form.", "{}", nil)
    end
  end

  describe "definition/1" do
    test "reads a bare JSON object" do
      text = ~s({"title": "Dogs", "elements": [{"type": "text", "name": "dog_name"}]})

      assert BuildWithAI.definition(text) ==
               {:ok,
                %{
                  "title" => "Dogs",
                  "elements" => [%{"type" => "text", "name" => "dog_name"}]
                }}
    end

    test "reads an object out of a code fence" do
      text = """
      Here you go:

      ```json
      {"elements": []}
      ```
      """

      assert BuildWithAI.definition(text) == {:ok, %{"elements" => []}}
    end

    test "reads an object out of a fence with no language" do
      assert BuildWithAI.definition("```\n{\"elements\": []}\n```") == {:ok, %{"elements" => []}}
    end

    test "refuses an answer that is not JSON" do
      assert BuildWithAI.definition("I can't do that.") ==
               {:error, "Build with AI returned an answer that is not valid JSON."}
    end

    test "refuses an answer that is not an object" do
      assert BuildWithAI.definition(~s([{"type": "text", "name": "dog_name"}])) ==
               {:error, "Build with AI returned something that is not a form definition."}
    end

    test "refuses an empty object, which the form builder would have accepted" do
      assert Builder.unsupported(%{}) == []

      assert BuildWithAI.definition("{}") ==
               {:error, "Build with AI returned an answer with no form elements."}
    end

    test "refuses a refusal dressed as JSON" do
      assert BuildWithAI.definition(~s({"error": "I can't do that"})) ==
               {:error, "Build with AI returned an answer with no form elements."}
    end

    test "refuses an elements key that is not a list" do
      assert BuildWithAI.definition(~s({"elements": "a dog form"})) ==
               {:error, "Build with AI returned an answer with no form elements."}
    end
  end

  describe "changes/2" do
    @before ~s({"elements":[
      {"type":"panel","name":"who","title":"Who","elements":[
        {"type":"text","name":"given_name","title":"Given"},
        {"type":"text","name":"middle_name"},
        {"type":"text","name":"family_name"}]},
      {"type":"paneldynamic","name":"addresses","templateElements":[
        {"type":"text","name":"city"}]},
      {"type":"html","name":"intro","html":"<p>Hi</p>"}]})

    defp definition(elements), do: %{"elements" => elements}

    defp who(members), do: %{"type" => "panel", "name" => "who", "elements" => members}

    defp addresses(members),
      do: %{"type" => "paneldynamic", "name" => "addresses", "templateElements" => members}

    defp given_name, do: %{"type" => "text", "name" => "given_name", "title" => "Given"}
    defp middle_name, do: %{"type" => "text", "name" => "middle_name"}
    defp family_name, do: %{"type" => "text", "name" => "family_name"}
    defp city, do: %{"type" => "text", "name" => "city"}

    test "names the questions an answer merged away, in the order they were asked" do
      merged =
        definition([who([%{"type" => "text", "name" => "full_name"}]), addresses([city()])])

      assert %{removed: ["given_name", "middle_name", "family_name"], added: ["full_name"]} =
               BuildWithAI.changes(@before, merged)
    end

    test "a renamed question is a removed one and an added one" do
      previous = ~s({"elements":[{"type":"text","name":"read_ordinances"}]})
      renamed = definition([%{"type" => "text", "name" => "agreements"}])

      assert BuildWithAI.changes(previous, renamed) == %{
               added: ["agreements"],
               removed: ["read_ordinances"],
               changed: []
             }
    end

    test "a question kept but altered is changed" do
      retitled =
        definition([
          who([%{given_name() | "title" => "Given name"}, middle_name(), family_name()]),
          addresses([city()])
        ])

      assert BuildWithAI.changes(@before, retitled) == %{
               added: [],
               removed: [],
               changed: ["given_name"]
             }
    end

    # The shape of most correct answers: groups moved about, questions kept.
    # A warning that fired here would fire on nearly everything.
    test "rearranging groups, and dropping one, changes nothing" do
      regrouped =
        definition([
          %{
            "type" => "panel",
            "name" => "names_row",
            "groupType" => "horizontal",
            "elements" => [given_name(), middle_name(), family_name()]
          },
          addresses([city()])
        ])

      assert BuildWithAI.changes(@before, regrouped) == %{added: [], removed: [], changed: []}
    end

    test "a nested form losing a question of its template counts" do
      emptied =
        definition([who([given_name(), middle_name(), family_name()]), addresses([])])

      assert %{removed: ["city"], added: [], changed: []} = BuildWithAI.changes(@before, emptied)
    end

    test "a form built from a blank draft has nothing to compare against" do
      built = definition([%{"type" => "text", "name" => "dog_name"}])

      assert BuildWithAI.changes("{}", built) == %{added: [], removed: [], changed: []}

      assert BuildWithAI.changes(~s({"elements":[]}), built) == %{
               added: [],
               removed: [],
               changed: []
             }

      assert BuildWithAI.changes("{nope", built) == %{added: [], removed: [], changed: []}
    end
  end

  describe "changes?/1" do
    test "is false only when nothing moved" do
      refute BuildWithAI.changes?(%{added: [], removed: [], changed: []})
      assert BuildWithAI.changes?(%{added: ["a"], removed: [], changed: []})
      assert BuildWithAI.changes?(%{added: [], removed: ["a"], changed: []})
      assert BuildWithAI.changes?(%{added: [], removed: [], changed: ["a"]})
    end
  end

  defp properties_listed_for(type) do
    [listed] =
      Regex.run(~r/^\s*\* #{type}: (.+)$/m, BuildWithAI.instructions(), capture: :all_but_first)

    listed |> String.split(", ") |> Enum.sort()
  end
end
