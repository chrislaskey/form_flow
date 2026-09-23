defmodule FormFlow.Config.Forms.Type.Default do
  @moduledoc """
  The public face of `FormFlow.Config.Forms.Type`'s defaults - the stored
  answers and nothing more, for a custom type to reach when it prefills
  around them:

      def initial_data(context, callback_data) do
        Map.merge(%{"email" => user_email(context)}, FormFlow.Config.Forms.Type.Default.initial_data(context, callback_data))
      end

  `properties/0` is the other half of what a custom type reaches for: the
  properties every form type inherits - "Prefill with answers from" - which
  a type declaring its own puts after them.

  Delegates to the private internal implementation in
  `FormFlow.Web.Components.Forms.Types.Default`
  """

  @behaviour FormFlow.Config.Forms.Type

  alias FormFlow.Web.Components.Forms.Types

  defdelegate properties(), to: Types.Default
  defdelegate initial_data(context, callback_data), to: Types.Default
  defdelegate edit_component(assigns), to: Types.Default
  defdelegate show_component(assigns), to: Types.Default
  defdelegate snapshot(context, callback_data), to: Types.Default
  defdelegate handle_complete(context, callback_data), to: Types.Default
end
