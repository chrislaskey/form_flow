defmodule FormFlow.Data.Repo do
  @moduledoc """
  `FormFlow.Data.Repo` module contains the wrapper for the parent app's Ecto.Repo instance
  """

  def repo, do: Application.get_env(:form_flow, :repo)
  def all(query), do: repo().all(query)
  def one(query), do: repo().one(query)
  def get(queryable, id), do: repo().get(queryable, id)
  def preload(structs, preloads), do: repo().preload(structs, preloads)
  def insert(changeset), do: repo().insert(changeset)
  def update(changeset), do: repo().update(changeset)
  def delete(struct), do: repo().delete(struct)
  def delete_all(query), do: repo().delete_all(query)
  def update_all(query, updates), do: repo().update_all(query, updates)
  def exists?(query), do: repo().exists?(query)
  def transaction(fun), do: repo().transaction(fun)
  def rollback(value), do: repo().rollback(value)
end
