defmodule FormFlow.Web.Components.Forms.Prefills do
  @moduledoc """
  `FormFlow.Web.Components.Forms.Prefills` is what every page that *writes* a
  prefill (`FormFlow.Data.Templates.Form.Prefill`) does with the dialog: what
  it opens with, what a capture fills it from, what its submission writes, and
  whether that write moves the selection.

  It sits beside the three components it serves —
  `FormFlow.Web.Components.Forms.PrefillPicker`,
  `FormFlow.Web.Components.Forms.PrefillMenu`, and
  `FormFlow.Web.Components.Forms.PrefillDialog` — and here rather than under
  either page family for the same reason they are: the two template pages and
  the instance's Edit page all write prefills, and each of them would
  otherwise keep its own copy of this.

  What is *not* here is anything a page owns: where the selection lives in
  that page's URL, what it does about unsaved content before a navigation,
  and when the menu is drawn at all. Those differ per page, and pretending
  they do not is what would make this module the wrong shape.

  The store itself is `FormFlow.Data.Templates.Forms` — `list_prefills/1`,
  `get_prefill/2`, and the three writers behind `save/4`.
  """

  alias FormFlow.Data.Templates.Form.Prefill
  alias FormFlow.Data.Templates.Forms

  @doc """
  What a prefill dialog opens with: an empty pair of fields for a new one,
  or the selected one's name and answers, as the JSON the field edits. A
  capture opens the same dialog through `captured_dialog/2`.

  The dialog's fields live in this assign rather than in the browser, so a
  refused write can hand back what was typed instead of what was stored.
  """
  def dialog(:create), do: %{action: :create, name: "", data: "{}", captured: false}

  def dialog(:update, %Prefill{} = prefill) do
    %{
      action: :update,
      name: prefill.name,
      data: Phoenix.json_library().encode!(prefill.data, pretty: true),
      captured: false
    }
  end

  @doc """
  What a Capture opens the same dialog with: the answers off the form on
  screen, and the name of the prefill in use — so capturing with one selected
  writes over it, and capturing with none writes a new one. Capture is not a
  third way to save a prefill; it is New or Edit with the answers already
  there.

  `params` is the form serialised by the browser
  (`FormFlow.Web.Components.Forms.PrefillMenu`), so it is decoded the way
  Phoenix decodes any form body, and the answers are lifted out of
  `DynamicForm`'s namespace — a prefill holds question names to values, with
  nothing wrapped around them.
  """
  def captured_dialog(prefill, params) do
    answers =
      params
      |> Plug.Conn.Query.decode()
      |> Map.get("dynamic_form", %{})

    %{
      action: (prefill && :update) || :create,
      name: (prefill && prefill.name) || "",
      data: Phoenix.json_library().encode!(answers, pretty: true),
      captured: true
    }
  end

  @doc """
  Writes what a prefill dialog submitted: `attrs` is its two fields —
  `:name`, and `:answers` as the JSON typed into them — plus the `:user_id`
  saving it. `prefill` is the one being updated, and is ignored when
  creating.

  Returns the written form, or the sentence to show over the dialog: the
  answers have to parse, and they have to be an object, since a prefill is
  question names to values.
  """
  def save(form, action, prefill, attrs) do
    with {:ok, data} <- decode_answers(attrs.answers) do
      write(action, form, prefill, %{
        name: attrs.name,
        data: data,
        user_id: attrs.user_id
      })
      |> case do
        {:ok, form} -> {:ok, form}
        {:error, reason} -> {:error, error(reason)}
      end
    end
  end

  @doc """
  Whether a write moves the selection, and so sends the page somewhere:
  creating selects what was created, and updating keeps the selection unless
  it renamed the prefill that is selected.
  """
  def selects_another?(:create, _prefill, _name), do: true
  def selects_another?(:update, %Prefill{name: name}, name), do: false
  def selects_another?(:update, _prefill, _name), do: true

  defp write(:create, form, _prefill, attrs), do: Forms.create_prefill(form, attrs)

  defp write(:update, form, prefill, attrs),
    do: Forms.update_prefill(form, prefill.name, attrs)

  defp decode_answers(json) do
    case Phoenix.json_library().decode(presence(json) || "{}") do
      {:ok, data} when is_map(data) -> {:ok, data}
      {:ok, _other} -> {:error, ~s(The answers are a JSON object, like {"full_name": "Rex"}.)}
      {:error, _reason} -> {:error, "The answers aren't valid JSON."}
    end
  end

  defp error(%Ecto.Changeset{} = changeset) do
    case changeset.errors[:name] do
      {message, _opts} -> "Name #{message}."
      nil -> "Could not save this prefill. Please try again."
    end
  end

  defp error(_reason), do: "Could not save this prefill. Please try again."

  defp presence(empty) when empty in [nil, ""], do: nil
  defp presence(value), do: value
end
