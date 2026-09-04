defmodule FormFlow.Config.Forms.TypesTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias FormFlow.Config.Forms.Type
  alias FormFlow.Context
  alias FormFlow.Data.Instances

  # A host's own type: prefills around the stored answers by reaching the
  # defaults from its override, the way a host's type list extends the
  # library's defaults.
  defmodule Prefill do
    use FormFlow.Config.Forms.Type

    @impl true
    def initial_data(context, callback_data) do
      Map.merge(
        %{"name" => "Prefilled", "email" => "p@example.com"},
        Type.Default.initial_data(context, callback_data)
      )
    end
  end

  defp context(data) do
    %Context{form_instance: data && %Instances.Form{data: data}}
  end

  describe "Type.Default.initial_data/2" do
    test "renders the user's stored answers" do
      assert Type.Default.initial_data(context(%{"name" => "Grace"}), %{}) == %{
               "name" => "Grace"
             }
    end

    test "renders nothing for a form with no instance yet" do
      assert Type.Default.initial_data(context(nil), %{}) == %{}
    end
  end

  describe "Type.Default.show_component/1" do
    test "renders the answers read-only: a disabled fieldset, no submit" do
      parsed =
        DynamicForm.Parser.FromData.parse!(%{
          "elements" => [%{"type" => "text", "name" => "name", "title" => "Name"}]
        })

      html =
        render_component(&Type.Default.show_component/1,
          id: "answers",
          instance: parsed,
          data: %{"name" => "Grace"},
          context: %Context{},
          callback_data: %{}
        )

      assert html =~ ~r/<fieldset[^>]*disabled/
      assert html =~ "Grace"
      refute html =~ ~r/type="submit"/
    end
  end

  describe "Type.Default.snapshot_data/2 and handle_complete/2" do
    test "record nothing and do nothing" do
      context = context(%{"name" => "Grace"})

      assert Type.Default.snapshot_data(context, %{}) == %{}
      assert Type.Default.handle_complete(context, %{}) == :ok
    end

    test "are what a type inherits when it doesn't override them" do
      context = context(%{"name" => "Grace"})

      assert Prefill.snapshot_data(context, %{}) == %{}
      assert Prefill.handle_complete(context, %{}) == :ok
    end
  end

  describe "a custom type" do
    test "prefills what the user hasn't answered and keeps what they have" do
      assert Prefill.initial_data(context(%{"name" => "Grace"}), %{}) ==
               %{"name" => "Grace", "email" => "p@example.com"}

      assert Prefill.initial_data(context(%{}), %{}) ==
               %{"name" => "Prefilled", "email" => "p@example.com"}
    end
  end

  describe "property_values/1" do
    test "reads what an admin entered for the form's type, under the type's own key" do
      form = %FormFlow.Data.Templates.Form{
        properties: %{"form_type" => "typed", "form_type_property_values" => %{"name" => "Ada"}}
      }

      assert Type.property_values(form) == %{"name" => "Ada"}
      assert Type.property_values(%FormFlow.Data.Templates.Form{properties: %{}}) == %{}
      assert Type.property_values(nil) == %{}
    end
  end

  describe "related_form/2" do
    setup do
      intake = %Instances.FormProgress{path: ["intake"], label: "Intake", status: :completed}

      proof = %Instances.FormProgress{
        path: ["documents", "proof"],
        label: "Proof",
        status: :pending
      }

      %{forms: [intake, proof], intake: intake, proof: proof}
    end

    test "resolves a related-form property value to that form in the flow instance", ctx do
      context = %Context{
        form_type_property_values: %{"source" => "documents/proof"},
        flow_instance_progress: ctx.forms
      }

      assert Type.related_form(context, "source") == ctx.proof
    end

    test "is nil when the property is unset or the flow no longer has the position", ctx do
      unset = %Context{form_type_property_values: %{}, flow_instance_progress: ctx.forms}

      gone = %Context{
        form_type_property_values: %{"source" => "gone"},
        flow_instance_progress: ctx.forms
      }

      assert is_nil(Type.related_form(unset, "source"))
      assert is_nil(Type.related_form(gone, "source"))
      assert is_nil(Type.related_form(%Context{}, "source"))
    end
  end
end
