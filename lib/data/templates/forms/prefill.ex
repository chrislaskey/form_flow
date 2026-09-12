defmodule FormFlow.Data.Templates.Form.Prefill do
  @moduledoc """
  `FormFlow.Data.Templates.Form.Prefill` is one named set of answers an admin
  saved against a form, to fill it with while trying it out.

  `data` is the answers, keyed by the definition's question names — the same
  map as `FormFlow.Data.Instances.Form`'s `data`, so what a prefill holds is
  what `DynamicForm.form/1` renders with, on the template side's preview and
  on a form instance's page alike. Nothing here is ever a user's answers: a
  prefill is offered, applied, and then merged *under* whatever the user has
  already stored, so filling one in can never replace something they typed.

  ## Not version specific

  A prefill belongs to the lineage (`FormFlow.Data.Templates.Form`), not to a
  version, and nothing pins one to the definition it was written against. A
  publish therefore leaves every prefill where it is, and an older set
  applied to a newer definition lands softly: `DynamicForm` casts only the
  names the definition declares, so answers to questions that went away are
  dropped and questions that arrived come up blank. The blanks are the
  reason to look — they are what a user will see when the definition moves
  under them.

  ## The stored entry

  The lineage's `prefills` column is a map of name to entry, and this struct
  is one entry with its name alongside it:

      %{
        "Happy path" => %{
          "data" => %{"pet_name" => "Rex", "breed" => "Beagle"},
          "description" => "Everything filled in, nothing unusual.",
          "user_id" => "admin",
          "inserted_at" => "2026-09-11T14:02:11.412000Z",
          "updated_at" => "2026-09-11T14:02:11.412000Z"
        }
      }

  The name is the key, so names are unique per form and renaming moves the
  entry. The answers sit under `"data"` rather than being the entry itself,
  which is what leaves room beside them for what is worth saying about a
  prefill — who saved it, when, what it is for — without a reader ever
  having to tell a set of answers from an entry holding one.

  `from_entry/2`, `to_entry/1`, and `entry?/1` are the only places that know
  the string keys; `FormFlow.Data.Templates.Forms` reads and writes prefills
  through them, and pages see structs. `changeset/2` is what a page edits one
  through.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field(:name, :string)
    field(:description, :string)
    field(:data, :map, default: %{})
    field(:user_id, :string)
    field(:inserted_at, :utc_datetime_usec)
    field(:updated_at, :utc_datetime_usec)
  end

  @type t :: %__MODULE__{
          name: String.t() | nil,
          description: String.t() | nil,
          data: map(),
          user_id: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @doc """
  Builds a changeset for one prefill.

  The name is required and trimmed — it is the key the set is stored under,
  and the word an admin says to pick it. The timestamps are not castable:
  `FormFlow.Data.Templates.Forms` stamps them as it writes.
  """
  def changeset(prefill, attrs \\ %{}) do
    prefill
    |> cast(attrs, [:name, :description, :data, :user_id])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name])
    |> validate_length(:name, max: 255)
  end

  @doc "The struct for one stored entry, given the name it is stored under."
  def from_entry(name, entry) when is_binary(name) and is_map(entry) do
    %__MODULE__{
      name: name,
      description: entry["description"],
      data: entry["data"] || %{},
      user_id: entry["user_id"],
      inserted_at: timestamp(entry["inserted_at"]),
      updated_at: timestamp(entry["updated_at"])
    }
  end

  @doc """
  The entry to store, without the name — the key it goes under. Keys with
  nothing in them are left out, so an entry says only what was set.
  """
  def to_entry(%__MODULE__{} = prefill) do
    %{
      "data" => prefill.data || %{},
      "description" => prefill.description,
      "user_id" => prefill.user_id,
      "inserted_at" => iso8601(prefill.inserted_at),
      "updated_at" => iso8601(prefill.updated_at)
    }
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  @doc """
  Whether a value is an entry this can read back: a map whose answers are a
  map. `FormFlow.Data.Templates.Form.prefills_changeset/2` refuses a column
  that holds anything else.
  """
  def entry?(%{"data" => data}) when is_map(data), do: true
  def entry?(_value), do: false

  defp timestamp(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, timestamp, _offset} -> timestamp
      {:error, _reason} -> nil
    end
  end

  defp timestamp(_value), do: nil

  defp iso8601(%DateTime{} = timestamp), do: DateTime.to_iso8601(timestamp)
  defp iso8601(nil), do: nil
end
