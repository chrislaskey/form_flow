defmodule FormFlow.Web do
  @moduledoc """
  `FormFlow.Web` module contains UI, UX, presentation, and web related code

  Within this module there are two primary areas:

  - `Templates` which define the flow itself
  - `Instances` which capture the instances of users going through the templated defined flow
  """

  def router(assigns), do: FormFlow.Web.Router.router(assigns)
end
