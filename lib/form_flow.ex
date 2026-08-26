defmodule FormFlow do
  @moduledoc """
  `FormFlow` module has two primary parts:

  - `FormFlow.Data` for all backend and data related code
  - `FormFlow.Web`  for all UI, UX, presentation, and web related code
  """

  def app_config(key), do: Application.get_env(:form_flow, key)
end
