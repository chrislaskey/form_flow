defmodule FormFlow.Downloads.RendererTest do
  use ExUnit.Case, async: true

  alias FormFlow.Context
  alias FormFlow.Downloads
  alias FormFlow.Downloads.Document
  alias FormFlow.Downloads.Document.Section
  alias FormFlow.Downloads.Renderer

  defmodule Refusing do
    @behaviour Renderer

    @impl true
    def extension, do: "pdf"

    @impl true
    def render(_document, _context, _callback_data), do: {:error, "the engine is down"}
  end

  defmodule Confused do
    @behaviour Renderer

    @impl true
    def extension, do: "pdf"

    @impl true
    def render(_document, _context, _callback_data), do: :ok
  end

  defmodule Echoing do
    @behaviour Renderer

    @impl true
    def extension, do: "txt"

    @impl true
    def render(document, context, callback_data) do
      {:ok, "#{document.title}|#{context.user_id}|#{callback_data[:hello]}", "text/plain"}
    end
  end

  @document %Document{
    title: "Owner details",
    filename: "owner-details",
    sections: [%Section{entries: [{:field, "Name", "Ada"}]}]
  }

  describe "the two renderers the library ships" do
    test "the PDF renderer is the default" do
      assert Downloads.default_renderer() == Renderer.PDF
    end

    test "both draw the same document, and say which format they drew" do
      assert {:ok, pdf, "application/pdf"} = Renderer.PDF.render(@document, %Context{}, %{})
      assert {:ok, html, "text/html" <> _} = Renderer.HTML.render(@document, %Context{}, %{})

      assert String.starts_with?(pdf, "%PDF")
      assert html =~ "<!doctype html>"

      for body <- [pdf, html], do: assert(body =~ "Owner details")
    end

    test "their extensions name the file, so a mount swaps the format and nothing else" do
      assert Renderer.PDF.extension() == "pdf"
      assert Renderer.HTML.extension() == "html"
    end
  end

  describe "render/4" do
    test "names the file from the document and the renderer, which is the only place it is joined" do
      assert {:ok, _body, "application/pdf", "owner-details.pdf"} =
               Downloads.render(@document, %Context{}, %{}, Renderer.PDF)

      assert {:ok, _body, "text/html" <> _, "owner-details.html"} =
               Downloads.render(@document, %Context{}, %{}, Renderer.HTML)
    end

    test "hands a renderer the context and the host's callback_data alongside the document" do
      context = %Context{user_id: "user-1"}

      assert {:ok, "Owner details|user-1|world", "text/plain", "owner-details.txt"} =
               Downloads.render(@document, context, %{hello: "world"}, Echoing)
    end

    test "passes a renderer's refusal through unchanged" do
      assert {:error, "the engine is down"} =
               Downloads.render(@document, %Context{}, %{}, Refusing)
    end

    test "a renderer returning something else is a bug in that renderer, and says so" do
      assert_raise ArgumentError, ~r/Confused.render\/3 returned :ok/, fn ->
        Downloads.render(@document, %Context{}, %{}, Confused)
      end
    end
  end

  describe "the HTML renderer" do
    test "escapes what it draws — a printable page is still a page a browser will run" do
      document = %Document{
        title: "<script>alert(1)</script>",
        filename: "x",
        sections: [%Section{entries: [{:field, "Name", "<b>Ada</b>"}]}]
      }

      {:ok, html, _type} = Renderer.HTML.render(document, %Context{}, %{})

      refute html =~ "<script>alert"
      refute html =~ "<b>Ada</b>"
      assert html =~ "&lt;b&gt;Ada&lt;/b&gt;"
    end

    test "carries its own styles, so the file prints on its own" do
      {:ok, html, _type} = Renderer.HTML.render(@document, %Context{}, %{})

      assert html =~ "@page"
      refute html =~ "<link"
    end
  end

  describe "an empty document" do
    test "still prints its heading, and says the answers are what is missing" do
      document = %Document{title: "Owner details", subtitle: "Dog Licence", filename: "x"}

      {:ok, pdf, _type} = Renderer.PDF.render(document, %Context{}, %{})
      {:ok, html, _type} = Renderer.HTML.render(document, %Context{}, %{})

      for body <- [pdf, html] do
        assert body =~ "Owner details"
        assert body =~ "Nothing has been filled in here yet."
      end
    end

    test "an unanswered field is drawn as one, not dropped" do
      document = %Document{
        title: "T",
        filename: "x",
        sections: [%Section{entries: [{:field, "Middle name", ""}]}]
      }

      {:ok, html, _type} = Renderer.HTML.render(document, %Context{}, %{})

      assert html =~ "Middle name"
      assert html =~ "—"
    end
  end
end
