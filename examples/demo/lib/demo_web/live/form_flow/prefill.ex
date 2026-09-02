defmodule DemoWeb.FormFlowLive.Prefill do
  @moduledoc """
  The demo's own form type, behind the `"demo_prefill"` option
  `DemoWeb.FormFlowLive.Config` offers: a form whose `name` question starts
  filled in.

  What it starts filled in *with* comes from the type's properties — declared
  here as `FormFlow.Config.Property` structs, entered by an admin on the form
  edit page under the type dropdown, and read back at render through the
  context as the type's property values. A real host would look the name up
  in its own database; the properties stand in for that. The salutation shows
  a choice property alongside the text one.

  It shows the shape every prefill takes: load the host's data, then merge
  the user's stored answers *over* it, so a returning user never sees their
  edits replaced. The stored answers come from the default type's
  `initial_data/2`, reached the same way a custom config module reaches
  `FormFlow.Config.Default`.
  """

  use FormFlow.Config.Forms.Type

  alias FormFlow.Config.Forms.Type
  alias FormFlow.Config.Property

  def properties do
    [
      %Property{
        id: "name",
        name: "Name to prefill",
        description: "What the form's name question starts filled in with.",
        required: true
      },
      %Property{
        id: "salutation",
        name: "Salutation",
        type: :dropdown,
        options: [{"Ms.", "ms"}, {"Mr.", "mr"}, {"Dr.", "dr"}]
      }
    ]
  end

  @impl true
  def initial_data(context, config_data) do
    stored = Type.Default.initial_data(context, config_data)

    case prefilled_name(context.form_type_property_values) do
      nil -> stored
      name -> Map.merge(%{"name" => name}, stored)
    end
  end

  defp prefilled_name(%{"name" => name} = values) do
    case List.keyfind(Enum.at(properties(), 1).options, values["salutation"], 1) do
      {salutation, _value} -> "#{salutation} #{name}"
      nil -> name
    end
  end

  defp prefilled_name(_values), do: nil
end
