defmodule FormFlow.Data.Instances.Form.Draft do
  @moduledoc """
  `FormFlow.Data.Instances.Form.Draft` is what a user saved of a form
  before submitting it: the form as it stood on the page, valid or not,
  with who saved it and when.

  `data` is keyed by the definition's question names - the same map
  `FormFlow.Data.Instances.Form`'s `data` holds - but nothing has checked
  it: a half-typed date, a word in a number field, and a required question
  left blank are all kept exactly as typed, because a draft's whole job is
  to keep the user's place. Nothing here is ever a user's *answers*. Show,
  the PDF, a review's snapshot, and a move to a new version read `data` on the
  instance; a draft is drawn on the Edit page, over the stored answers, and
  nowhere else.

  ## The stored entry

  The instance's `draft` column is one entry, or `NULL` when there is no
  draft:

      %{
        "data" => %{"pet_name" => "Rex", "vaccination_date" => "not sure"},
        "user_id" => "dog_owner",
        "saved_at" => "2026-09-17T15:04:11.412000Z"
      }

  The answers sit under `"data"` rather than being the entry itself, as a
  prefill's do (`FormFlow.Data.Templates.Form.Prefill`), which is what
  leaves room beside them for who saved the draft and when without a reader
  ever having to tell a set of answers from an entry holding one.

  `from_entry/1`, `to_entry/1`, and `entry?/1` are the only places that know
  the string keys; `FormFlow.Data.Instances.Forms` reads and writes the
  column through them, and pages see structs.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field(:data, :map, default: %{})
    field(:user_id, :string)
    field(:saved_at, :utc_datetime_usec)
  end

  @type t :: %__MODULE__{
          data: map(),
          user_id: String.t() | nil,
          saved_at: DateTime.t() | nil
        }

  @doc """
  Builds a changeset for a draft. `saved_at` is not castable:
  `FormFlow.Data.Instances.Forms.save_draft/4` stamps it as it writes.
  """
  def changeset(draft, attrs \\ %{}) do
    cast(draft, attrs, [:data, :user_id])
  end

  @doc "The struct for the stored entry."
  def from_entry(entry) when is_map(entry) do
    %__MODULE__{
      data: entry["data"] || %{},
      user_id: entry["user_id"],
      saved_at: timestamp(entry["saved_at"])
    }
  end

  @doc """
  The entry to store. Keys with nothing in them are left out, so an entry
  says only what was set.
  """
  def to_entry(%__MODULE__{} = draft) do
    %{
      "data" => draft.data || %{},
      "user_id" => draft.user_id,
      "saved_at" => iso8601(draft.saved_at)
    }
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  @doc """
  Whether a value is an entry this can read back: a map whose answers are a
  map. `FormFlow.Data.Instances.Form.draft_changeset/2` refuses a column
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
