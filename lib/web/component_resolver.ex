defmodule FormFlow.Web.ComponentResolver do
  @moduledoc """
  Resolution and dispatch for the pluggable `components` module.

  FormFlow renders its own UI — buttons, tables, lists, headers — through
  `FormFlow.Web.CoreComponents` by default. A host points FormFlow at its own
  components module instead — typically the Phoenix-generated
  `MyAppWeb.CoreComponents` — by passing it as the `components` attr on
  `FormFlow.Web.router/1` or directly on a LiveComponent:

      <FormFlow.Web.router components={MyAppWeb.CoreComponents} ... />

  Unlike `DynamicForm.ComponentResolver` (the sibling library's version of
  this same pattern), there is no application-config fallback — FormFlow
  moved away from anything reaching back into a host module by convention
  when it removed `FormFlow.Config` in v0.16.0, so `components` is an
  explicit attr only, with `nil` meaning "use the built-ins."

  ## The contract, and per-function fallback

  Dispatch is per function: each component FormFlow needs is looked up on
  the given module with `function_exported?/3`, falling back to
  `FormFlow.Web.CoreComponents` when the module doesn't define it. A module
  only needs to define the functions it wants to own — typically all of them,
  since a real generated `CoreComponents` module already exports the whole
  set: `flash/1`, `button/1`, `input/1`, `error/1`, `header/1`, `table/1`,
  `list/1`, `icon/1`, `translate_error/1`, `translate_errors/2`.

  Two components FormFlow renders are not in that generated set:
  `alert/1`, the status message a page draws about the state of what it is
  showing, and `badge/1`, the state of one row or step. A host's
  `CoreComponents` will not define them, so they fall back to FormFlow's own
  the way any other undefined function does — and a host that wants them to
  match the rest of its application can define them and own them too.

  `error/1` is the one function Phoenix 1.8's own generated `CoreComponents`
  keeps private (it has nothing to delegate to when a host doesn't override
  it), so `FormFlow.Web.CoreComponents.error/1` is public — a host overriding
  it must make theirs public too.
  """

  alias FormFlow.Web.CoreComponents

  @doc """
  Resolves the components module: the given value when it is a module,
  `nil` (built-in only) otherwise.

  Raises `ArgumentError` when the module cannot be loaded, so a typo fails
  loudly instead of silently falling back to the built-in components.
  """
  def resolve(nil), do: nil

  def resolve(module) when is_atom(module), do: ensure_loaded!(module)

  @doc """
  Whether the components module provides its own `fun/1` implementation.
  """
  def provides?(nil, _fun), do: false
  def provides?(module, fun) when is_atom(module), do: function_exported?(module, fun, 1)

  @doc """
  Renders the component `fun` with `assigns`, delegating to `components`
  when it exports the function and falling back to
  `FormFlow.Web.CoreComponents` otherwise.
  """
  def render(components, fun, assigns) when is_map(assigns) do
    module = if provides?(components, fun), do: components, else: CoreComponents

    Phoenix.LiveView.TagEngine.component(
      Function.capture(module, fun, 1),
      assigns,
      {module, {fun, 1}, __ENV__.file, __ENV__.line}
    )
  end

  defp ensure_loaded!(module) do
    if Code.ensure_loaded?(module) do
      module
    else
      raise ArgumentError,
            "FormFlow components module #{inspect(module)} could not be loaded — " <>
              "check the components attribute passed to FormFlow.Web.router/1 or a LiveComponent"
    end
  end
end
