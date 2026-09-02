defmodule FormFlow.Config.Forms.Type do
  @moduledoc """
  Form type definition: one way a form behaves for the user filling it out.

  `FormFlow.Config.enabled_form_types/2` returns a list of these; the struct
  is what the config describes, and its `:module` — `use`ing this behaviour —
  is what the type does. `:id` is the value stored in the form's
  `properties["form_type"]`.

  Every callback takes the `FormFlow.Context` of one form in one flow
  instance — `:form` and `:form_version` are the template, `:form_instance`
  the user's answers so far — plus `config_data`. The defaults,
  `FormFlow.Config.Forms.Type.Default`, render the stored answers and nothing
  more. A type overrides only what it changes, and can call the defaults from
  its override, so prefilling a form is a `Map.merge/2` over what the default
  returns, and a type that draws more around the form still renders the form
  itself through the default `edit_component/1`.

  Two ship with the library, both enabled by default
  (`FormFlow.Config.Default.enabled_form_types/2`): `"default"`, the form as
  designed, and `"review"` (`FormFlow.Web.Components.Forms.Types.Review`),
  which shows an earlier form's answers beside it.
  """

  alias FormFlow.Context
  alias FormFlow.Data.Instances.FlowProgress
  alias FormFlow.Data.Instances.FormProgress
  alias FormFlow.Data.Templates.Form

  defstruct [:id, :module, :name, :description, properties: []]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          module: module(),
          name: String.t(),
          description: String.t() | nil,
          properties: [FormFlow.Config.Property.t()]
        }

  @doc """
  What an admin entered for the form's type's `:properties`, keyed by
  property key — stored on the form under
  `properties["form_type_property_values"]`. Empty when the type declares
  none or nothing was entered.
  """
  @spec property_values(Form.t() | nil) :: map()
  def property_values(%Form{properties: properties}) do
    Map.get(properties || %{}, "form_type_property_values", %{})
  end

  def property_values(nil), do: %{}

  @doc """
  The data the form renders with — keys are the definition's question names.
  Called when the edit page mounts, on the first start and on every later
  visit alike, so the default returns the user's stored answers and a type
  that prefills merges its values around them. Keep it deterministic for a
  given stored state: `DynamicForm` resets in-progress input when the initial
  data it receives changes.
  """
  @callback initial_data(Context.t(), map()) :: map()

  @doc """
  The edit page's form, drawn. `assigns` are `DynamicForm.form/1`'s — `:id`,
  `:instance` (the parsed definition), `:data` (from `initial_data/2`),
  `:on_success` — plus `:context` and `:config_data`. The default renders the
  form and nothing else; a type that draws more around it renders the form
  itself by calling the default with the same assigns.
  """
  @callback edit_component(map()) :: Phoenix.LiveView.Rendered.t()

  defmacro __using__(_opts) do
    quote do
      @behaviour FormFlow.Config.Forms.Type

      def initial_data(context, config_data) do
        FormFlow.Config.Forms.Type.Default.initial_data(context, config_data)
      end

      def edit_component(assigns) do
        FormFlow.Config.Forms.Type.Default.edit_component(assigns)
      end

      defoverridable initial_data: 2, edit_component: 1
    end
  end

  @doc """
  The form a `:related_form` property of the form's type points at, as it
  stands in this flow instance — the `FormProgress` whose path the property
  value names — or `nil` when the property is unset or the flow no longer has
  that position.
  """
  @spec related_form(Context.t(), String.t()) :: FormProgress.t() | nil
  def related_form(%Context{} = context, property_id) do
    with path when is_binary(path) <- (context.form_type_property_values || %{})[property_id] do
      FlowProgress.find_form(context.flow_instance_progress || [], String.split(path, "/"))
    end
  end
end
