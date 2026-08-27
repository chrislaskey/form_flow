defmodule FormFlow.Web.Instances.Positions do
  @moduledoc """
  `FormFlow.Web.Instances.Positions` module contains the one write both
  user-facing pages perform: opening a position, which is how they navigate.
  """

  alias FormFlow.Data.Instances

  @doc """
  Opens a journey position: `FormFlow.Data.Instances.Forms.update_status/4`
  with `:in_progress`, which creates the form instance on first open (and so
  pins the version the filler sees). Returns `{:ok, instance}` or
  `{:error, message}` — the failure wording lives here rather than in each
  page, since both the journey listing and a flow's drawn progress open
  positions.
  """
  def open(journey, path, user_id) do
    case Instances.Forms.update_status(journey, path, :in_progress, user_id: user_id) do
      {:ok, instance} ->
        {:ok, instance}

      {:error, :no_published_version} ->
        {:error, "That form has no published version yet — ask an administrator to publish it."}

      {:error, _reason} ->
        {:error, "Could not open the form. The flow may have changed — reload."}
    end
  end
end
