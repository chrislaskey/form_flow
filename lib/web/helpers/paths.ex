defmodule FormFlow.Web.Helpers.Paths do
  @moduledoc """
  `FormFlow.Web.Helpers.Paths` module contains shared path helpers for the
  template pages.
  """

  @doc """
  The router's mount root — where the Templates landing lives, and where
  every breadcrumb starts. `base` is the mount prefix (`"/admin"` for
  `live "/admin/*path", ...`); with the default empty base the root is `/`.
  """
  def templates_path(""), do: "/"
  def templates_path(base), do: base
end
