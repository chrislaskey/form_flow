defmodule FormFlow.Web.Downloads.RendererTest do
  use ExUnit.Case, async: true

  alias FormFlow.Context
  alias FormFlow.Web.Downloads
  alias FormFlow.Web.Downloads.Document
  alias FormFlow.Web.Downloads.Document.Section
  alias FormFlow.Web.Downloads.Renderer
  alias FormFlow.Web.Downloads.Renderer.PDF.Writer

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

  describe "nested groups" do
    @nested %Document{
      title: "Directory",
      filename: "directory",
      sections: [
        %Section{
          title: "Registered Users",
          entries: [
            {:group, "User #1",
             [
               {:field, "Full Name", "one"},
               {:group, "Email Addresses",
                [
                  {:group, "Email Slot #1", [{:field, "Email Address", "hello@world.com"}]}
                ]}
             ]}
          ]
        }
      ]
    }

    test "both renderers draw every level, not just the first" do
      {:ok, pdf, _type} = Renderer.PDF.render(@nested, %Context{}, %{})
      {:ok, html, _type} = Renderer.HTML.render(@nested, %Context{}, %{})

      for body <- [pdf, html],
          text <- ["User #1", "Full Name", "Email Addresses", "Email Slot #1", "hello@world.com"] do
        assert body =~ text
      end
    end

    test "a group the definition heads with nothing draws no heading, in either renderer" do
      document = %Document{
        title: "Licence",
        filename: "licence",
        sections: [
          %Section{
            title: "Dogs",
            entries: [
              {:group, nil, [{:field, "Name", "Rex"}]},
              {:group, nil, [{:field, "Name", "Byte"}]}
            ]
          }
        ]
      }

      {:ok, pdf, _type} = Renderer.PDF.render(document, %Context{}, %{})
      {:ok, html, _type} = Renderer.HTML.render(document, %Context{}, %{})

      for body <- [pdf, html], text <- ["Rex", "Byte", "Dogs"], do: assert(body =~ text)

      refute html =~ ~s(<div class="title">)
      refute pdf =~ "() Tj"
    end

    test "the PDF indents each level, so the nesting is visible on paper" do
      {:ok, pdf, _type} = Renderer.PDF.render(@nested, %Context{}, %{})

      # Every drawn line carries its x in the text matrix; deeper labels sit further right
      x = fn text ->
        [x] =
          Regex.run(~r/1 0 0 1 ([\d.]+) [\d.]+ Tm\n\(#{Regex.escape(text)}\)/, pdf,
            capture: :all_but_first
          )

        String.to_float(x <> ".0")
      end

      assert x.("User #1") < x.("Email Addresses")
      assert x.("Email Addresses") < x.("Email Slot #1")
    end

    test "the indent stops growing, so a deep form keeps a readable column" do
      deep =
        Enum.reduce(10..1//-1, [{:field, "Leaf", "value"}], fn level, entries ->
          [{:group, "Level #{level}", entries}]
        end)

      document = %Document{
        title: "Deep",
        filename: "deep",
        sections: [%Section{entries: deep}]
      }

      {:ok, pdf, _type} = Renderer.PDF.render(document, %Context{}, %{})

      indents =
        Regex.scan(~r/1 0 0 1 ([\d.]+) [\d.]+ Tm/, pdf, capture: :all_but_first)
        |> Enum.map(fn [x] -> String.to_float(x <> ".0") end)

      assert Enum.max(indents) < Writer.content_width()
      assert pdf =~ "(Leaf)"
      assert pdf =~ "(value)"
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
