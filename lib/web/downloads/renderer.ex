defmodule FormFlow.Web.Downloads.Renderer do
  @moduledoc """
  The behaviour a module implements to turn a `FormFlow.Web.Downloads.Document`
  into the bytes a browser receives.

  FormFlow ships two: `FormFlow.Web.Downloads.Renderer.PDF`, the default, which
  writes a PDF with no dependency of any kind, and
  `FormFlow.Web.Downloads.Renderer.HTML`, a printable HTML page. Both take the
  same document, so which one a host mounts changes the file and nothing
  about what it says.

  The built-in PDF renderer is deliberately plain: Helvetica, a heading, and
  the answers under it. A host that wants its own typography, letterhead, or
  page furniture writes a renderer instead of configuring one, usually by
  handing the document's parts to a real HTML-to-PDF engine:

      defmodule MyApp.FormFlowRenderer do
        @behaviour FormFlow.Web.Downloads.Renderer

        @impl true
        def extension, do: "pdf"

        @impl true
        def render(document, _context, _callback_data) do
          html = Phoenix.Template.render_to_string(MyApp.PDFHTML, "form", "html", document: document)

          {:ok, ChromicPDF.print_to_pdf({:html, html}), "application/pdf"}
        end
      end

  and mounting it:

      form_flow_router_download_routes(renderer: MyApp.FormFlowRenderer)

  ## Why a document and a context

  `render/3` gets both because they answer different questions. The
  `FormFlow.Web.Downloads.Document` is the resource already flattened into
  headings, fields, and values — everything a renderer needs to print
  something correct without knowing what a flow instance is. The
  `FormFlow.Context` is the request FormFlow answered, the same struct every
  other callback in the library receives, for a renderer that wants more
  than the document carries: the tenant, to pick a letterhead; the flow, to
  title the page its own way. `callback_data` is the host's own map, the
  third argument every FormFlow callback takes.

  A renderer that only needs the document ignores the other two, which is
  what both built-ins do.
  """

  alias FormFlow.Context
  alias FormFlow.Web.Downloads.Document

  @doc """
  The bytes to send, and the content type to send them as.

  `{:error, message}` is a rendering failure the host should see — the
  controller turns it into a 500 with the message. Returning an error is for
  a renderer that cannot draw this document; a renderer that simply has
  nothing to say draws an empty page and returns `:ok`.
  """
  @callback render(Document.t(), Context.t(), map()) ::
              {:ok, binary(), content_type :: String.t()} | {:error, String.t()}

  @doc """
  The file extension, without a dot — `"pdf"`, `"html"`. Appended to the
  document's `:filename` to name the download.
  """
  @callback extension() :: String.t()
end
