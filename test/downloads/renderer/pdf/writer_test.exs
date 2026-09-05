defmodule FormFlow.Downloads.Renderer.PDF.WriterTest do
  use ExUnit.Case, async: true

  alias FormFlow.Downloads.Renderer.PDF.Writer

  defp pdf(writer), do: Writer.to_binary(writer)

  defp page_count(binary) do
    [_ | rest] = String.split(binary, "/Type /Pages /Kids")
    [count] = Regex.run(~r/\/Count (\d+)/, hd(rest), capture: :all_but_first)

    String.to_integer(count)
  end

  describe "to_binary/1" do
    test "writes a file a reader can open: header, xref, and a trailer that points at it" do
      binary = Writer.new() |> Writer.text("Hello") |> pdf()

      assert String.starts_with?(binary, "%PDF-1.4\n")
      assert String.ends_with?(binary, "%%EOF\n")

      [offset] = Regex.run(~r/startxref\n(\d+)\n%%EOF/, binary, capture: :all_but_first)

      assert binary |> binary_part(String.to_integer(offset), 4) == "xref"
    end

    test "every object the xref claims is at the offset it claims" do
      binary = Writer.new() |> Writer.text("Hello") |> pdf()

      {at, length} = :binary.match(binary, "xref\n0 ")

      [count] =
        Regex.run(~r/^(\d+)\n/, binary_part(binary, at + length, 20), capture: :all_but_first)

      count = String.to_integer(count)
      table_at = at + length + String.length("#{count}") + 1

      # Entry 0 is the free head; the rest are the objects, in order
      for number <- 1..(count - 1) do
        entry = binary_part(binary, table_at + 20 * number, 20)

        assert [offset] = Regex.run(~r/^(\d{10}) 00000 n $/, entry, capture: :all_but_first)

        header = "#{number} 0 obj"

        assert binary_part(binary, String.to_integer(offset), byte_size(header)) == header
      end
    end

    test "a writer nothing was drawn on still produces one valid page" do
      binary = pdf(Writer.new())

      assert page_count(binary) == 1
    end

    test "the title reaches the metadata, where a reader and a print dialog read it" do
      binary = Writer.new(title: "Dog Licence") |> pdf()

      assert binary =~ "/Title (Dog Licence)"
    end
  end

  describe "pagination" do
    test "text past the bottom of the page continues on the next one" do
      binary =
        Enum.reduce(1..200, Writer.new(), fn n, writer -> Writer.text(writer, "line #{n}") end)
        |> pdf()

      assert page_count(binary) > 1
    end

    test "each page is numbered with the total, which is only known at the end" do
      binary =
        Enum.reduce(1..200, Writer.new(), fn n, writer -> Writer.text(writer, "line #{n}") end)
        |> pdf()

      count = page_count(binary)

      for number <- 1..count, do: assert(binary =~ "(#{number} of #{count})")
    end

    test "the footer line is drawn on every page, before the number" do
      binary =
        Enum.reduce(1..200, Writer.new(footer: "Dog Licence"), fn n, writer ->
          Writer.text(writer, "line #{n}")
        end)
        |> pdf()

      assert binary =~ "(Dog Licence  " <> <<0xB7>> <> "  1 of "
    end

    test "space/2 that would run off the bottom is not taken, so a heading never trails a gap" do
      near_bottom = Writer.new() |> Writer.space(650)

      assert Writer.space(near_bottom, 200) == near_bottom
    end

    test "page_break/1 on an untouched page does not leave a blank one" do
      assert page_count(pdf(Writer.page_break(Writer.new()))) == 1
    end
  end

  describe "text/3" do
    test "wraps to the content width rather than running off the page" do
      binary = Writer.new() |> Writer.text(String.duplicate("word ", 200)) |> pdf()

      lines = Regex.scan(~r/\((.*?)\) Tj/, binary, capture: :all_but_first)

      assert length(lines) > 1

      for [line] <- lines,
          do: assert(Writer.text_width(line, :regular, 10) <= Writer.content_width())
    end

    test "breaks a word too long to fit rather than letting it overflow" do
      word = String.duplicate("supercalifragilistic", 20)
      binary = Writer.new() |> Writer.text(word) |> pdf()

      lines = Regex.scan(~r/\((.*?)\) Tj/, binary, capture: :all_but_first)

      assert length(lines) > 1
      assert Enum.map_join(lines, &hd/1) =~ "supercalifragilistic"
    end

    test "escapes the three characters PDF string syntax reserves" do
      binary = Writer.new() |> Writer.text("a (b) c \\ d") |> pdf()

      assert binary =~ "(a \\(b\\) c \\\\ d) Tj"
    end

    test "an empty value takes its line without drawing one" do
      drawn = Writer.new() |> Writer.text("") |> pdf()

      refute drawn =~ "() Tj"
    end

    test "newlines and tabs collapse to spaces — a PDF string has no line breaks" do
      binary = Writer.new() |> Writer.text("one\ntwo\tthree") |> pdf()

      assert binary =~ "(one two three) Tj"
    end
  end

  describe "encode/1" do
    test "passes ASCII and Latin-1 through as their own bytes" do
      assert Writer.encode("café") == <<?c, ?a, ?f, 0xE9>>
    end

    test "maps the typographic characters that keep appearing in pasted text" do
      assert Writer.encode("“a” — b… •") ==
               <<0x93, ?a, 0x94, ?\s, 0x97, ?\s, ?b, 0x85, ?\s, 0x95>>
    end

    test "replaces what WinAnsi cannot say, rather than writing a byte that lies" do
      assert Writer.encode("日本") == "??"
    end
  end

  describe "text_width/3" do
    test "measures with the real Helvetica metrics, so an i is not an m" do
      assert Writer.text_width("i", :regular, 10) < Writer.text_width("m", :regular, 10)
    end

    test "bold is wider than regular at the same size" do
      assert Writer.text_width("Hello", :bold, 10) > Writer.text_width("Hello", :regular, 10)
    end

    test "scales with the point size" do
      assert_in_delta Writer.text_width("Hello", :regular, 20),
                      2 * Writer.text_width("Hello", :regular, 10),
                      0.001
    end

    test "an empty string is no width at all" do
      assert Writer.text_width("", :regular, 10) == 0
    end
  end
end
