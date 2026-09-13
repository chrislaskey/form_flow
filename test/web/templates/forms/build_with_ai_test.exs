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

  defp properties_listed_for(type) do
    [listed] =
      Regex.run(~r/^\s*\* #{type}: (.+)$/m, BuildWithAI.instructions(), capture: :all_but_first)

    listed |> String.split(", ") |> Enum.sort()
  end
end
