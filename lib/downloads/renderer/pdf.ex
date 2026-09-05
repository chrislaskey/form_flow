defmodule FormFlow.Downloads.Renderer.PDF do
  @moduledoc """
  The default `FormFlow.Downloads.Renderer`: a `FormFlow.Downloads.Document`
  laid out as a PDF, with no dependency to install.

  The layout is one column and deliberately plain — a heading, the details
  under it, then each section's fields as a small bold label with its value
  beneath. It is a record of what someone answered, meant to be filed and
  read, not a designed document. Everything about how it is drawn lives in
  `FormFlow.Downloads.Renderer.PDF.Writer`, which is where the format's
  limits are written down.

  A host that wants more than this — letterhead, columns, a typeface of its
  own — writes its own renderer around a real HTML-to-PDF engine and mounts
  that instead; the document it receives is the same one this module draws.
  See `FormFlow.Downloads.Renderer`.
  """

  @behaviour FormFlow.Downloads.Renderer

  alias FormFlow.Downloads.Document
  alias FormFlow.Downloads.Renderer.PDF.Writer

  @impl true
  def extension, do: "pdf"

  @impl true
  def render(%Document{} = document, _context, _callback_data) do
    body =
      [title: document.title, footer: document.subtitle]
      |> Writer.new()
      |> heading(document)
      |> details(document)
      |> content(document)
      |> Writer.to_binary()

    {:ok, body, "application/pdf"}
  end

  defp heading(writer, document) do
    writer
    |> Writer.text(document.title, font: :bold, size: 18)
    |> Writer.text(document.subtitle, size: 10, color: :grey)
    |> Writer.rule()
  end

  defp details(writer, %Document{details: []}), do: writer

  defp details(writer, %Document{details: details}) do
    writer =
      Enum.reduce(details, writer, fn {label, value}, writer ->
        Writer.text(writer, "#{label}: #{value}", size: 9, color: :grey, leading: 12)
      end)

    Writer.space(writer, 10)
  end

  defp content(writer, document) do
    if Document.any_content?(document) do
      Enum.reduce(document.sections, writer, &section(&2, &1))
    else
      Writer.text(writer, "Nothing has been filled in here yet.", size: 10, color: :grey)
    end
  end

  defp section(writer, %Document.Section{entries: []}), do: writer

  defp section(writer, %Document.Section{title: nil} = section) do
    entries(writer, section.entries, 0)
  end

  defp section(writer, %Document.Section{} = section) do
    writer
    |> Writer.space(8)
    |> Writer.text(section.title, font: :bold, size: 12)
    |> Writer.space(2)
    |> entries(section.entries, 0)
  end

  defp entries(writer, entries, indent) do
    Enum.reduce(entries, writer, &entry(&2, &1, indent))
  end

  defp entry(writer, {:field, label, value}, indent) do
    writer
    |> Writer.space(6)
    |> Writer.text(label, font: :bold, size: 9, color: :grey, leading: 11, indent: indent)
    |> Writer.text(blank(value), size: 10, indent: indent)
  end

  defp entry(writer, {:text, text}, indent) do
    writer
    |> Writer.space(6)
    |> Writer.text(text, size: 10, color: :grey, indent: indent)
  end

  defp entry(writer, {:group, title, entries}, indent) do
    writer
    |> Writer.space(8)
    |> Writer.text(title, font: :bold, size: 10, indent: indent)
    |> entries(entries, indent + 14)
  end

  # An unanswered question prints an em dash rather than a gap, so a reader
  # can tell "no answer" from "the renderer lost it"
  defp blank(""), do: "—"
  defp blank(nil), do: "—"
  defp blank(value), do: value
end
