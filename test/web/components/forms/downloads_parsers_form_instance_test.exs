defmodule FormFlow.Web.Components.Forms.Downloads.Parsers.FormInstanceTest do
  use ExUnit.Case, async: true

  alias FormFlow.Context
  alias FormFlow.Data.Instances
  alias FormFlow.Data.Instances.FormProgress
  alias FormFlow.Data.Templates
  alias FormFlow.Web.Components.Forms.Downloads.Parsers.FormInstance
  alias FormFlow.Web.Downloads.Document.Section

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
    {:ok, document} = FormInstance.document(context(data, overrides), parsed())

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
               {:group, "Dog", [{:field, "Name", "Rex"}, {:field, "Microchipped", "Yes"}]},
               {:group, "Dog", [{:field, "Name", "Byte"}, {:field, "Microchipped", "No"}]}
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

  describe "nested repeating questions" do
    @nested %{
      "elements" => [
        %{
          "name" => "users",
          "type" => "paneldynamic",
          "title" => "Registered Users",
          "templateTitle" => "User #" <> "{panelIndex}",
          "templateElements" => [
            %{"name" => "fullName", "type" => "text", "title" => "Full Name"},
            %{
              "name" => "emails",
              "type" => "paneldynamic",
              "title" => "Email Addresses",
              "templateTitle" => "Email Slot #" <> "{panelIndex}",
              "templateElements" => [
                %{"name" => "emailAddress", "type" => "text", "title" => "Email Address"},
                %{
                  "name" => "emailType",
                  "type" => "dropdown",
                  "title" => "Type",
                  "choices" => ["Personal", "Work"]
                }
              ]
            }
          ]
        }
      ]
    }

    defp nested_document(data) do
      {:ok, document} =
        FormInstance.document(context(data), DynamicForm.Parser.FromData.parse!(@nested))

      document
    end

    test "a repeating question inside a repeating question is a group of groups" do
      data = %{
        "users" => [
          %{
            "fullName" => "one",
            "emails" => [
              %{"emailAddress" => "hello@world.com", "emailType" => "Work"},
              %{"emailAddress" => "three@four.com", "emailType" => "Personal"}
            ]
          }
        ]
      }

      assert entries(nested_document(data), "Registered Users") == [
               {:group, "User #1",
                [
                  {:field, "Full Name", "one"},
                  {:group, "Email Addresses",
                   [
                     {:group, "Email Slot #1",
                      [
                        {:field, "Email Address", "hello@world.com"},
                        {:field, "Type", "Work"}
                      ]},
                     {:group, "Email Slot #2",
                      [
                        {:field, "Email Address", "three@four.com"},
                        {:field, "Type", "Personal"}
                      ]}
                   ]}
                ]}
             ]
    end

    test "each entry of each level keeps its own answers" do
      data = %{
        "users" => [
          %{"fullName" => "one", "emails" => [%{"emailAddress" => "a@b.com"}]},
          %{"fullName" => "two", "emails" => [%{"emailAddress" => "c@d.com"}]}
        ]
      }

      assert [{:group, "User #1", first}, {:group, "User #2", second}] =
               entries(nested_document(data), "Registered Users")

      assert {:field, "Full Name", "one"} in first
      assert {:field, "Full Name", "two"} in second

      assert [{:group, "Email Addresses", [{:group, _, [{:field, _, "a@b.com"} | _]}]}] =
               Enum.filter(first, &match?({:group, _, _}, &1))
    end

    test "a definition written as SurveyJS pages is walked the same way" do
      paged = %{"pages" => [%{"name" => "p1", "elements" => @nested["elements"]}]}

      {:ok, document} =
        FormInstance.document(
          context(%{"users" => [%{"fullName" => "one"}]}),
          DynamicForm.Parser.FromData.parse!(paged)
        )

      assert [{:group, "User #1", [{:field, "Full Name", "one"} | _]}] =
               entries(document, "Registered Users")
    end

    test "an entry the user added but left empty is still a group, so the count is right" do
      data = %{"users" => [%{"fullName" => "one"}, %{}]}

      assert [{:group, "User #1", _}, {:group, "User #2", second}] =
               entries(nested_document(data), "Registered Users")

      assert {:field, "Full Name", ""} in second
    end
  end

  describe "an entry's heading" do
    test "puts the number where the template author put {panelIndex}" do
      assert [{:group, "User #1", _}] =
               entries(nested_document(%{"users" => [%{}]}), "Registered Users")
    end

    test "repeats a heading the template wrote without one, exactly as the page does" do
      assert [{:group, "Dog", _}, {:group, "Dog", _}] = dog_entries("Dog")
    end

    test "heads an entry with nothing when the template heads it with nothing" do
      assert [{:group, nil, _}, {:group, nil, _}] = dog_entries(nil)
    end

    test "an unheaded entry is still its own group, so the answers stay together" do
      assert [{:group, nil, [{:field, "Name", "Rex"}]}, {:group, nil, [{:field, "Name", "Byte"}]}] =
               dog_entries(nil)
    end

    defp dog_entries(template_title) do
      question =
        %{
          "name" => "dogs",
          "type" => "paneldynamic",
          "title" => "Dogs",
          "templateElements" => [%{"name" => "n", "type" => "text", "title" => "Name"}]
        }
        |> then(&if template_title, do: Map.put(&1, "templateTitle", template_title), else: &1)

      {:ok, document} =
        FormInstance.document(
          context(%{"dogs" => [%{"n" => "Rex"}, %{"n" => "Byte"}]}),
          DynamicForm.Parser.FromData.parse!(%{"elements" => [question]})
        )

      entries(document, "Dogs")
    end
  end

  describe "inside an entry" do
    @scoped %{
      "elements" => [
        %{"name" => "country", "type" => "text", "title" => "Country"},
        %{
          "name" => "pets",
          "type" => "paneldynamic",
          "title" => "Pets",
          "templateElements" => [
            %{"name" => "species", "type" => "text", "title" => "Species"},
            %{
              "name" => "breed",
              "type" => "text",
              "title" => "Breed",
              "visibleIf" => "{panel.species} = 'dog'"
            },
            %{
              "name" => "permit",
              "type" => "text",
              "title" => "Permit",
              "visibleIf" => "{country} = 'UK'"
            },
            %{
              "name" => "panel",
              "type" => "panel",
              "title" => "Vet",
              "elements" => [%{"name" => "vet", "type" => "text", "title" => "Practice"}]
            }
          ]
        }
      ]
    }

    defp scoped_entries(data) do
      {:ok, document} =
        FormInstance.document(context(data), DynamicForm.Parser.FromData.parse!(@scoped))

      [{:group, _title, entries}] = entries(document, "Pets")

      entries
    end

    test "a {panel.field} condition is judged against the entry, as the browser judges it" do
      shown = scoped_entries(%{"pets" => [%{"species" => "dog", "breed" => "Collie"}]})
      hidden = scoped_entries(%{"pets" => [%{"species" => "cat", "breed" => "Collie"}]})

      assert {:field, "Breed", "Collie"} in shown
      refute Enum.any?(hidden, &match?({:field, "Breed", _}, &1))
    end

    test "a form-level condition still reaches into the entry" do
      shown = scoped_entries(%{"country" => "UK", "pets" => [%{"permit" => "P-1"}]})
      hidden = scoped_entries(%{"country" => "IE", "pets" => [%{"permit" => "P-1"}]})

      assert {:field, "Permit", "P-1"} in shown
      refute Enum.any?(hidden, &match?({:field, "Permit", _}, &1))
    end

    test "answers come from the entry, never from a form-level question of the same name" do
      entries = scoped_entries(%{"species" => "form-level", "pets" => [%{}]})

      assert {:field, "Species", ""} in entries
    end

    test "a panel inside the template is a group inside the entry" do
      entries = scoped_entries(%{"pets" => [%{"vet" => "Elm Street"}]})

      assert {:group, "Vet", [{:field, "Practice", "Elm Street"}]} in entries
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
      assert FormInstance.render_value(true) == "Yes"
      assert FormInstance.render_value(false) == "No"
    end

    test "nothing is nothing, not the word nil" do
      assert FormInstance.render_value(nil) == ""
    end

    test "a list joins with commas, each member through the same rules" do
      assert FormInstance.render_value(["a", "b"]) == "a, b"
      assert FormInstance.render_value([true, false]) == "Yes, No"
    end

    test "a map — an answer no question explains — falls back to compact JSON" do
      assert FormInstance.render_value(%{"a" => 1}) == ~s({"a":1})
    end

    test "numbers print as themselves" do
      assert FormInstance.render_value(42) == "42"
    end
  end

  describe "document/2" do
    test "refuses a position nobody has opened, rather than sending an empty file" do
      context = %Context{form_instance: nil}

      assert FormInstance.document(context, parsed()) == {:error, :not_started}
    end

    test "refuses a definition that will not parse, the way the page reports one inline" do
      context = context(%{}) |> struct(form_version: %Templates.Form.Version{definition: "{{{"})

      assert FormInstance.document(context) == {:error, :no_definition}
    end

    test "parses the pinned version when the caller has not already" do
      context =
        struct(context(%{"full_name" => "Ada"}),
          form_version: %Templates.Form.Version{definition: @definition}
        )

      assert {:ok, document} = FormInstance.document(context)
      assert {:field, "Full name", "Ada"} in entries(document, nil)
    end

    test "falls back to the form's own name when the position is no longer in the tree" do
      {:ok, document} =
        FormInstance.document(
          context(%{}, form_progress: nil, form: %Templates.Form{name: "Owner"}),
          parsed()
        )

      assert document.title == "Owner"
    end
  end
end
