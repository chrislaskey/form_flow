defmodule FormFlow.Config do
  @moduledoc """
  Module for configuring FormFlow from the parent app

  ## Implementation details

  Every callback takes a `FormFlow.Context` — one common shape every callback
  shares, so adding a new callback never means learning a new payload — and
  `config_data`, passed through unmodified from wherever `use`s this (see
  `FormFlow.Web.Router`'s `:config_data` attr).

  The defaults are `FormFlow.Config.Default`. A custom module `use`s this
  behaviour and overrides only what it changes; an override that wants to
  extend a default rather than replace it calls `FormFlow.Config.Default`'s
  and adds to the result. The pages resolve the module to ask with
  `config_module/1` — the host's, or the defaults when the host set none —
  and then call its callbacks directly.

  A host passes one config module per use of `FormFlow.Web.router/1`, so a
  config is where per-use behavior lives — which types a section offers, who
  may see its pages (`handle_instance_mount/2`), whose flow instances its
  listing shows (`flow_instances_query/2`), and which flows it offers to
  start (`enabled_instance_flows/2`) — while a type describes how a form or
  flow behaves wherever it is used.

  A callback only one side of the router reads says which in its name —
  `handle_instance_mount/2`, `enabled_instance_flows/2` — while the type
  lists, which both sides read, stay unqualified.
  """

  alias FormFlow.Context

  @doc "The flow types a flow may be given, in display order."
  @callback enabled_flow_types(Context.t(), map()) :: [FormFlow.Config.Flows.Type.t()]

  @doc "The form types a form may be given, in display order."
  @callback enabled_form_types(Context.t(), map()) :: [FormFlow.Config.Forms.Type.t()]

  @doc """
  The perspectives a "forms" flow may be for, in display order — the kinds of
  user a host distinguishes (`FormFlow.Config.Flows.Perspective`). The
  identity form of every "forms" flow offers them as a multi-select; the
  picked ids are stored on the flow, and the flow type's `visible?/2` and
  `editable?/2` read them for the viewer whose perspectives the router's
  `perspectives` attr names. The default is none, which shows no field and
  stores nothing:

      def enabled_perspectives(_context, _config_data) do
        [
          %FormFlow.Config.Flows.Perspective{id: "applicant", name: "Applicant"},
          %FormFlow.Config.Flows.Perspective{
            id: "reviewer",
            name: "Regional reviewer",
            metadata: %{queue: :regional}
          }
        ]
      end

  Both sides read it: the template pages to offer and label the choices, the
  instance pages to hand the flow's perspectives to the types as structs
  (`FormFlow.Context.flow_perspectives`). The context is the flow's —
  `:subflow` is the "forms" flow in question.
  """
  @callback enabled_perspectives(Context.t(), map()) :: [FormFlow.Config.Flows.Perspective.t()]

  @doc """
  The flow instances the listing page shows, as a composable query over
  `FormFlow.Data.Instances.Flow` — `FormFlow.Data.Instances.Flows.list_query/1`
  is the building block. The default narrows to the current user's own:

      def flow_instances_query(context, _config_data) do
        FormFlow.Data.Instances.Flows.list_query(user_id: context.user_id)
      end

  A reviewer's desk lists everyone's by returning `list_query()` bare; a host
  with finer rules layers its own `where` on top. Tenant narrowing is not the
  host's to do or undo: the page applies the router's `tenant_id` after this
  returns, so a multitenant host never lists across tenants by accident.
  The context carries `:user_id` and `:tenant_id` and nothing else — the
  listing spans every flow, so there is no flow in scope. A listing
  convenience, not access control: gate the page with `handle_instance_mount/2`.
  """
  @callback flow_instances_query(Context.t(), map()) :: Ecto.Query.t()

  @doc """
  The flow templates the listing page offers to start, in display order —
  the twin of `flow_instances_query/2` for templates. The default is every
  root flow in the tenant that has not been made reusable. An entry point
  for one flow names it by slug; a reviewer's desk offers nothing:

      def enabled_instance_flows(context, _config_data) do
        [FormFlow.Data.Templates.Flows.get_by_slug("dog-license", tenant_id: context.tenant_id)]
      end

      def enabled_instance_flows(_context, _config_data), do: []

  `nil` entries are dropped, so a slug that resolves to nothing offers
  nothing rather than failing. The router's `tenant_id` is applied on top:
  a flow of another tenant is never offered, whatever the host answers. The
  page also refuses to start a flow it did not offer. The context carries
  `:user_id` and `:tenant_id` and nothing else. Ignored by the template
  pages, which list every root in the tenant.
  """
  @callback enabled_instance_flows(Context.t(), map()) :: [FormFlow.Data.Templates.Flow.t() | nil]

  @doc """
  Whether a user-facing page may render for this user, asked once the page
  has resolved what it addresses and before anything is drawn. The pages that
  ask are the listing, the flow instance's page, and the two form pages, edit
  and Show; on the edit page it is asked before the form is started, so a
  refused visitor starts nothing. The context is the page's: on the listing
  only `:user_id` and `:tenant_id` are set; on the flow instance's page
  `:flow` and `:subflow` are the root flow and `:flow_instance_progress` its
  forms, with no form in scope; on a form page it is the form's, with
  `:form_instance` the live instance or nil for a form not yet started.
  Return one of:

    * `{:ok, assigns}` — render, with `assigns` merged into the page's; `%{}`
      for nothing. The types' callbacks have already run with the original
      `config_data` by then.
    * `{:error, message}` — render the message alone, with a way back.
    * `{:redirect, to}` — navigate to `to`, rendering nothing meanwhile.

  Where a host authorizes: who may see this flow instance, or this form in it.
  Not rescued — an exception fails closed rather than falling through to the
  page. Runs whenever the page's assigns come in: on mount, and on every later
  render of the parent LiveView. The default allows everything.
  """
  @callback handle_instance_mount(Context.t(), map()) ::
              {:ok, map()} | {:error, String.t()} | {:redirect, String.t()}

  defmacro __using__(_opts) do
    quote do
      @behaviour FormFlow.Config

      def enabled_flow_types(context, config_data) do
        FormFlow.Config.Default.enabled_flow_types(context, config_data)
      end

      def enabled_form_types(context, config_data) do
        FormFlow.Config.Default.enabled_form_types(context, config_data)
      end

      def enabled_perspectives(context, config_data) do
        FormFlow.Config.Default.enabled_perspectives(context, config_data)
      end

      def handle_instance_mount(context, config_data) do
        FormFlow.Config.Default.handle_instance_mount(context, config_data)
      end

      def flow_instances_query(context, config_data) do
        FormFlow.Config.Default.flow_instances_query(context, config_data)
      end

      def enabled_instance_flows(context, config_data) do
        FormFlow.Config.Default.enabled_instance_flows(context, config_data)
      end

      defoverridable enabled_flow_types: 2,
                     enabled_form_types: 2,
                     enabled_perspectives: 2,
                     handle_instance_mount: 2,
                     flow_instances_query: 2,
                     enabled_instance_flows: 2
    end
  end

  @doc "Return the FormFlow.Config module, either the one passed in or the default"
  @spec config_module(module() | nil) :: module()
  def config_module(nil), do: FormFlow.Config.Default
  def config_module(config), do: config
end
