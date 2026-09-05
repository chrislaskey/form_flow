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

  @doc """
  `path` with `keys` from `params` reattached as a query string — the
  whitelist a page forwards across its own internal navigation, so context
  that only the URL carries (a `mode`, say) survives following one of that
  page's own links rather than evaporating at the next hop. A key missing
  from `params`, or blank, is dropped rather than written as an empty pair;
  `path` comes back unchanged when none of `keys` are present.

  Assumes `path` carries no query string of its own — true of every path
  this library builds today.
  """
  def preserve_query_params(path, params, keys) do
    query =
      for key <- keys, value = params[key], value not in [nil, ""], into: %{}, do: {key, value}

    case query do
      empty when empty == %{} -> path
      query -> path <> "?" <> URI.encode_query(query)
    end
  end
end
