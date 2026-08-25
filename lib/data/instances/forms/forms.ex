defmodule FormFlow.Data.Instances.Forms do
  @moduledoc """
  `FormFlow.Data.Instances.Forms` context module for form instances.

  Deliberately minimal this iteration — the fill/runner surface comes later.
  What lives here now is the one operation that must exist somewhere
  concrete: explicit instance deletion. Events never cascade-delete with
  their instance (a reset event's `data_snapshot` is the only surviving copy
  of discarded answers), so removing an instance is `delete_instance/2` —
  the host app's retention decision, made visibly, in one named place.
  """

  import Ecto.Query

  alias FormFlow.Data.Instances
  alias FormFlow.Data.Instances.Form.Event
  alias FormFlow.Data.Repo

  @doc "Fetches an instance by id, or nil."
  def get(instance_form_id), do: Repo.get(Instances.Form, instance_form_id)

  @doc """
  Deletes an instance and its event trail, deliberately and in order:
  events first (the `restrict` FK forbids any other order), then the
  instance. This is the only deletion path — there is no cascade.
  """
  def delete_instance(%Instances.Form{} = instance, _opts \\ []) do
    Repo.transaction(fn ->
      Repo.delete_all(from(e in Event, where: e.instance_form_id == ^instance.id))

      case Repo.delete(instance) do
        {:ok, deleted} -> deleted
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end
end
