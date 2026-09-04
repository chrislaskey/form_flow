defmodule FormFlow.Config.Forms.Type do
  @moduledoc """
  Form type definition: one way a form behaves for the user filling it out.

  A host passes a list of these as the `form_types` attr of
  `FormFlow.Web.router/1` and the LiveComponents — the same list on the
  admin pages, where a type is chosen, and on every instance page, where it
  acts — usually from one function of its own that starts from `defaults/0`.
  The struct is what the host describes, and its `:module` — `use`ing this
  behaviour — is what the type does. `:id` is the value stored in the form's
  `properties["form_type"]`.

  Every callback takes the `FormFlow.Context` of one form in one flow
  instance — `:form` and `:form_version` are the template, `:form_instance`
  the user's answers so far — plus `callback_data`, the host's own map from
  the attr of that name, or the assigns of the page drawing the form. The defaults, `FormFlow.Config.Forms.Type.Default`,
  render the stored answers and nothing more, on the edit page and the Show
  page alike, record nothing when the form is submitted, and react to
  nothing. A type overrides only what it changes, and
  can call the defaults from its override, so prefilling a form is a
  `Map.merge/2` over what the default returns, and a type that draws more
  around the form still renders the form itself through the default
  `edit_component/1`.

  Two ship with the library, both in `defaults/0`: `"default"`, the form as
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
  The library's form types, in display order: the default first — the form
  as designed, and the fallback for a form that never chose — then the
  review type. What the `form_types` attr defaults to, and what a host's own
  list starts from:

      def form_types do
        FormFlow.Config.Forms.Type.defaults() ++ [prefill()]
      end
  """
  @spec defaults() :: [t()]
  def defaults do
    [
      %__MODULE__{
        id: "default",
        module: FormFlow.Config.Forms.Type.Default,
        name: "Default",
        description: "The form as designed, nothing more."
      },
      %__MODULE__{
        id: "review",
        module: FormFlow.Web.Components.Forms.Types.Review,
        name: "Review",
        description: "Shows an earlier form's answers beside this one, for checking them.",
        properties: FormFlow.Web.Components.Forms.Types.Review.properties()
      }
    ]
  end

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
  `:on_success` — plus `:context` and `:callback_data`. The default renders the
  form and nothing else; a type that draws more around it renders the form
  itself by calling the default with the same assigns.
  """
  @callback edit_component(map()) :: Phoenix.LiveView.Rendered.t()

  @doc """
  The Show page's answers, drawn read-only. `assigns` are `edit_component/1`'s
  minus `:on_success`, with `:data` the stored answers; the default renders
  the form in a disabled fieldset with no submit. A type that draws more
  around the answers renders them by calling the default.
  """
  @callback show_component(map()) :: Phoenix.LiveView.Rendered.t()

  @doc """
  What to record on the form's completion event, in its `snapshot_data`,
  when the user submits — free-form, `%{}` for nothing. A type that needs to
  remember what it saw at submit time records it here; the Review type
  records the form it reviewed. The context is the edit page's: `:form_instance`
  is the row being completed, `:flow_instance_progress` the flow instance as
  the user saw it. Runs before the completion is written: an error here
  refuses the submit rather than completing a form without its record.
  """
  @callback snapshot_data(Context.t(), map()) :: map()

  @doc """
  Called after the user submits the form and the instance is completed — the
  context is derived fresh, so the form counts as done and `:form_instance`
  is the completed row. The moment a host reacts at: notify someone, write
  answers out to its own tables, enqueue a job. The return value is ignored;
  an error is logged and never undoes the completion. The default does
  nothing.

  `FormFlow.Config.Flows.Type` has a `handle_complete/2` too, and the two
  receive the same context; the flow type's answers where the user goes
  next, this one is a hook and answers nothing.
  """
  @callback handle_complete(Context.t(), map()) :: any()

  defmacro __using__(_opts) do
    quote do
      @behaviour FormFlow.Config.Forms.Type

      def initial_data(context, callback_data) do
        FormFlow.Config.Forms.Type.Default.initial_data(context, callback_data)
      end

      def edit_component(assigns) do
        FormFlow.Config.Forms.Type.Default.edit_component(assigns)
      end

      def show_component(assigns) do
        FormFlow.Config.Forms.Type.Default.show_component(assigns)
      end

      def snapshot_data(context, callback_data) do
        FormFlow.Config.Forms.Type.Default.snapshot_data(context, callback_data)
      end

      def handle_complete(context, callback_data) do
        FormFlow.Config.Forms.Type.Default.handle_complete(context, callback_data)
      end

      defoverridable initial_data: 2,
                     edit_component: 1,
                     show_component: 1,
                     snapshot_data: 2,
                     handle_complete: 2
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
