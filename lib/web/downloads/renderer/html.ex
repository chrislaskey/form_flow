defmodule FormFlow.Web.Downloads.Renderer.HTML do
  @moduledoc """
  A `FormFlow.Web.Downloads.Renderer` that writes a printable HTML page rather
  than a PDF: one self-contained file, its styles inline, with a `@page` rule
  so a browser's own Print gives sensible margins.

  It is not the default — `FormFlow.Web.Downloads.Renderer.PDF` is — but it is
  the renderer to mount when the host would rather print through the
  browser than through the library, and it is the worked example of the
  behaviour having more than one implementation:

      form_flow_router_download_routes(renderer: FormFlow.Web.Downloads.Renderer.HTML)

  It also makes a useful target while building a document: the same
  `FormFlow.Web.Downloads.Document` the PDF renderer draws, in a form that can be
  read in a browser's inspector.
  """

  @behaviour FormFlow.Web.Downloads.Renderer

  alias FormFlow.Web.Downloads.Document

  @impl true
  def extension, do: "html"

  @impl true
  def render(%Document{} = document, _context, _callback_data) do
    body = """
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <title>#{escape(document.title)}</title>
    <style>#{styles()}</style>
    </head>
    <body>
    <header>
    <h1>#{escape(document.title)}</h1>
    #{subtitle(document)}
    #{details(document)}
    </header>
    #{content(document)}
    </body>
    </html>
    """

    {:ok, body, "text/html; charset=utf-8"}
  end

  defp styles do
    """
    @page { margin: 18mm; }
    body { font: 11pt/1.5 system-ui, -apple-system, "Segoe UI", Helvetica, sans-serif;
           color: #18181b; margin: 0 auto; max-width: 46rem; padding: 2rem 1.5rem; }
    header { border-bottom: 1px solid #d4d4d8; padding-bottom: 1rem; margin-bottom: 1.5rem; }
    h1 { font-size: 1.5rem; margin: 0; }
    h2 { font-size: 1rem; margin: 2rem 0 0.5rem; }
    p.subtitle, dl.details { color: #71717a; font-size: 0.85rem; margin: 0.25rem 0 0; }
    dl.details div { display: flex; gap: 0.5rem; }
    dl.details dt::after { content: ":"; }
    dl.details dd { margin: 0; }
    section { break-inside: auto; }
    .field { margin-top: 0.85rem; }
    .field .label { font-size: 0.75rem; font-weight: 600; color: #71717a;
                    text-transform: uppercase; letter-spacing: 0.03em; }
    .field .value { white-space: pre-wrap; }
    .field .value.blank { color: #a1a1aa; }
    .group { margin: 1rem 0 0 1rem; padding-left: 0.75rem; border-left: 2px solid #e4e4e7; }
    .group > .title { font-weight: 600; }
    .text { color: #52525b; margin-top: 0.85rem; }
    .empty { color: #71717a; }
    """
  end

  defp subtitle(%Document{subtitle: nil}), do: ""

  defp subtitle(%Document{subtitle: subtitle}),
    do: ~s(<p class="subtitle">#{escape(subtitle)}</p>)

  defp details(%Document{details: []}), do: ""

  defp details(%Document{details: details}) do
    rows =
      Enum.map_join(details, fn {label, value} ->
        "<div><dt>#{escape(label)}</dt><dd>#{escape(value)}</dd></div>"
      end)

    ~s(<dl class="details">#{rows}</dl>)
  end

  defp content(document) do
    if Document.any_content?(document) do
      Enum.map_join(document.sections, "\n", &section/1)
    else
      ~s(<p class="empty">Nothing has been filled in here yet.</p>)
    end
  end

  defp section(%Document.Section{entries: []}), do: ""

  defp section(%Document.Section{} = section) do
    heading = if section.title, do: "<h2>#{escape(section.title)}</h2>", else: ""

    "<section>#{heading}#{Enum.map_join(section.entries, "\n", &entry/1)}</section>"
  end

  defp entry({:field, label, value}) do
    class = if value in ["", nil], do: "value blank", else: "value"

    ~s(<div class="field"><div class="label">#{escape(label)}</div>) <>
      ~s(<div class="#{class}">#{escape(blank(value))}</div></div>)
  end

  defp entry({:text, text}), do: ~s(<p class="text">#{escape(text)}</p>)

  defp entry({:group, title, entries}) do
    heading = if title, do: ~s(<div class="title">#{escape(title)}</div>), else: ""

    ~s(<div class="group">#{heading}) <> Enum.map_join(entries, "\n", &entry/1) <> "</div>"
  end

  defp blank(value) when value in ["", nil], do: "—"
  defp blank(value), do: value

  # The document's strings are user answers and admin-authored labels, so
  # every one of them is escaped on the way out — a printable page is still
  # a page a browser will run
  defp escape(value) do
    value |> to_string() |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
  end
end
