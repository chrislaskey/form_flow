defmodule FormFlow.Downloads.Instances.FormTest do
  use ExUnit.Case, async: true

  alias FormFlow.Context
  alias FormFlow.Data.Instances
  alias FormFlow.Data.Instances.FormProgress
  alias FormFlow.Data.Templates
  alias FormFlow.Downloads.Document.Section
  alias FormFlow.Downloads.Instances.Form

  @definition %{
    "id" => "owner",
    "elements" => [
      %{"name" => "full_name", "type" => "text", "title" => "Full name"},
      %{
        "name" => "size",
        "type" => "dropdown",
        "title" => "Size",
        "choices" => [
          %{"value" => "s", "text" => "Small"},
          %{"value" => "l", "text" => "Large"}
        ]
      },
      %{
        "name" => "intro",
        "type" => "html",
        "html" => "<h2>About you</h2><p>Tell us&nbsp;more.</p>"
      },
      %{
        "name" => "address",
        "type" => "panel",
        "title" => "Address",
        "elements" => [
          %{"name" => "city", "type" => "text", "title" => "City"},
          %{
            "name" => "abroad",
            "type" => "text",
            "title" => "Country",
            "visibleIf" => "{city} = 'Paris'"
          }
        ]
      },
      %{
        "name" => "dogs",
        "type" => "paneldynamic",
        "title" => "Dogs",
        "templateTitle" => "Dog",
        "templateElements" => [
          %{"name" => "dog_name", "type" => "text", "title" => "Name"},
          %{"name" => "chipped", "type" => "boolean", "title" => "Microchipped"}
        ]
      }
    ]
  }

  defp parsed, do: DynamicForm.Parser.FromData.parse!(@definition)

  defp context(data, overrides \\ []) do
    instance = %Instances.Form{
      id: "instance-1",
      status: "completed",
      data: data,
      template_form_version_id: "version-1",
      inserted_at: ~U[2026-09-01 09:14:00.000000Z],
      completed_at: ~U[2026-09-02 11:02:00.000000Z]
    }

    context = %Context{
      flow: %Templates.Flow{name: "Dog Licence"},
      flow_instance: %Instances.Flow{id: "flow-instance-1"},
      form_instance: struct(instance, Keyword.get(overrides, :instance, [])),
      form_progress: %FormProgress{path: ["node-1"], label: "Owner details", ancestors: []}
    }

    struct(context, Keyword.drop(overrides, [:instance]))
  end

  defp document(data, overrides \\ []) do
    {:ok, document} = Form.document(context(data, overrides), parsed())

    document
  end

  defp entries(document, title) do
    Enum.find_value(document.sections, [], fn
      %Section{title: ^title} = section -> section.entries
      _other -> nil
    end)
  end

  describe "the heading" do
    test "titles the document with the form's place in the flow, and names the flow under it" do
      document = document(%{})

      assert document.title == "Owner details"
      assert document.subtitle == "Dog Licence"
    end

    test "names the file from both, so a folder of downloads stays sortable" do
      assert document(%{}).filename == "dog-licence-owner-details"
    end

    test "reports the state a reader needs to trust the paper" do
      assert document(%{}).details == [
               {"Status", "Submitted"},
               {"Started", "2026-09-01 09:14 UTC"},
               {"Submitted", "2026-09-02 11:02 UTC"},
               {"Flow instance", "flow-instance-1"},
               {"Form version", "version-1"}
             ]
    end

    test "leaves out what has not happened — an unsubmitted form has no submitted line" do
      details = document(%{}, instance: [status: "in_progress", completed_at: nil]).details

      assert {"Status", "In progress"} in details
      refute Enum.any?(details, &match?({"Submitted", _}, &1))
    end
  end

  describe "the content" do
    test "questions outside any panel land in the run before the first heading" do
      assert entries(document(%{"full_name" => "Ada"}), nil) == [
               {:field, "Full name", "Ada"},
               {:field, "Size", ""},
               {:text, "About you Tell us more."}
             ]
    end

    test "a titled panel becomes a section of its own" do
      assert entries(document(%{"city" => "London"}), "Address") == [{:field, "City", "London"}]
    end

    test "a question the definition hides at these answers is not printed" do
      refute entries(document(%{"city" => "London"}), "Address")
             |> Enum.any?(&match?({:field, "Country", _}, &1))

      assert entries(document(%{"city" => "Paris", "abroad" => "FR"}), "Address") == [
               {:field, "City", "Paris"},
               {:field, "Country", "FR"}
             ]
    end

    test "a repeating question becomes a section of one group per entry" do
      data = %{
        "dogs" => [
          %{"dog_name" => "Rex", "chipped" => true},
          %{"dog_name" => "Byte", "chipped" => false}
        ]
      }

      assert entries(document(data), "Dogs") == [
               {:group, "Dog 1", [{:field, "Name", "Rex"}, {:field, "Microchipped", "Yes"}]},
               {:group, "Dog 2", [{:field, "Name", "Byte"}, {:field, "Microchipped", "No"}]}
             ]
    end

    test "a repeating question nobody added to is an empty section, which draws nothing" do
      assert entries(document(%{}), "Dogs") == []
    end

    test "a question left blank is kept — a record says what was not answered" do
      assert {:field, "Full name", ""} in entries(document(%{}), nil)
    end

    test "static content is printed as prose, its markup stripped" do
      assert {:text, "About you Tell us more."} in entries(document(%{}), nil)
    end
  end

  describe "render_value/2" do
    test "prints the text an admin wrote beside a choice, not the value stored under it" do
      assert {:field, "Size", "Large"} in entries(document(%{"size" => "l"}), nil)
    end

    test "a stored value the question no longer offers prints as itself" do
      assert {:field, "Size", "xl"} in entries(document(%{"size" => "xl"}), nil)
    end

    test "booleans read as Yes and No, not true and false" do
      assert Form.render_value(true) == "Yes"
      assert Form.render_value(false) == "No"
    end

    test "nothing is nothing, not the word nil" do
      assert Form.render_value(nil) == ""
    end

    test "a list joins with commas, each member through the same rules" do
      assert Form.render_value(["a", "b"]) == "a, b"
      assert Form.render_value([true, false]) == "Yes, No"
    end

    test "a map — an answer no question explains — falls back to compact JSON" do
      assert Form.render_value(%{"a" => 1}) == ~s({"a":1})
    end

    test "numbers print as themselves" do
      assert Form.render_value(42) == "42"
    end
  end

  describe "document/2" do
    test "refuses a position nobody has opened, rather than sending an empty file" do
      context = %Context{form_instance: nil}

      assert Form.document(context, parsed()) == {:error, :not_started}
    end

    test "refuses a definition that will not parse, the way the page reports one inline" do
      context = context(%{}) |> struct(form_version: %Templates.Form.Version{definition: "{{{"})

      assert Form.document(context) == {:error, :no_definition}
    end

    test "parses the pinned version when the caller has not already" do
      context =
        struct(context(%{"full_name" => "Ada"}),
          form_version: %Templates.Form.Version{definition: @definition}
        )

      assert {:ok, document} = Form.document(context)
      assert {:field, "Full name", "Ada"} in entries(document, nil)
    end

    test "falls back to the form's own name when the position is no longer in the tree" do
      {:ok, document} =
        Form.document(
          context(%{}, form_progress: nil, form: %Templates.Form{name: "Owner"}),
          parsed()
        )

      assert document.title == "Owner"
    end
  end
end
