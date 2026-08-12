defmodule FormFlow.Data.Repo do
  @moduledoc """
  `FormFlow.Data.Repo` module contains the wrapper for the parent app's Ecto.Repo instance
  """

  def repo, do: Application.get_env(:form_flow, :repo)
  def all(query), do: repo().all(query)
  def get(query), do: repo().get(query)
  def insert(query), do: repo().insert(query)
  def update(query), do: repo().update(query)
  def delete(query), do: repo().delete(query)
end
