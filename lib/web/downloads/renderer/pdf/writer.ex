defmodule FormFlow.Web.Downloads.Renderer.PDF.Writer do
  @moduledoc """
  A small PDF writer: enough of the format to lay text down a page, break to
  the next one when it runs out, and assemble the result into a valid file.

  It exists so that `FormFlow.Web.Downloads.Renderer.PDF` can produce a real PDF
  with no dependency — no Chrome, no wkhtmltopdf, nothing to install
  alongside the application. That buys downloads that work the moment the
  library is mounted, and costs everything a browser engine would have given:
  the two standard fonts below, no images, no colour beyond greys, no
  hyphenation.

  ## Using it

  A caller opens a writer, draws down the page, and asks for the bytes:

      Writer.new(title: "Dog Licence")
      |> Writer.text("Dog Licence", font: :bold, size: 18)
      |> Writer.rule()
      |> Writer.text("Name", font: :bold, size: 9, color: :grey)
      |> Writer.text("Rex")
      |> Writer.to_binary()

  Every draw call advances the cursor and starts a new page when what it is
  about to draw would not fit, so a caller never tracks the y position or
  counts pages. `space/2` moves the cursor without drawing, and never breaks
  a page by itself — trailing whitespace at a page boundary would otherwise
  push a heading onto a page of its own.

  ## Fonts and text

  Two fonts, the ones every PDF reader has without embedding: Helvetica
  (`:regular`) and Helvetica-Bold (`:bold`). Their WinAnsi widths are built
  in for the ASCII range, so wrapping is measured rather than guessed;
  characters outside it are measured at an average width, which is close
  enough for the accented Latin they are mostly used for.

  Text is encoded as WinAnsi, the standard-font encoding: ASCII passes
  through, Latin-1 accents pass through, the handful of typographic
  characters that keep appearing in pasted text (curly quotes, en and em
  dashes, the ellipsis and bullet) are mapped to their WinAnsi bytes, and
  anything else — anything outside Latin-1, so every non-Latin script —
  becomes `?`. A host serving those needs a renderer with a real font
  engine behind it, which is what `FormFlow.Web.Downloads.Renderer` is for.
  """

  @page_width 612
  @page_height 792
  @margin 54
  @footer_baseline 30

  @content_width @page_width - 2 * @margin
  @top @page_height - @margin
  @bottom @margin

  # Helvetica and Helvetica-Bold advance widths, in 1/1000 em, for codepoints
  # 32..126 — the Adobe core-font metrics. Anything else measures at
  # @default_width, which is about the average of each table.
  @helvetica_widths [
                      278,
                      278,
                      355,
                      556,
                      556,
                      889,
                      667,
                      191,
                      333,
                      333,
                      389,
                      584,
                      278,
                      333,
                      278,
                      278,
                      556,
                      556,
                      556,
                      556,
                      556,
                      556,
                      556,
                      556,
                      556,
                      556,
                      278,
                      278,
                      584,
                      584,
                      584,
                      556,
                      1015,
                      667,
                      667,
                      722,
                      722,
                      667,
                      611,
                      778,
                      722,
                      278,
                      500,
                      667,
                      556,
                      833,
                      722,
                      778,
                      667,
                      778,
                      722,
                      667,
                      611,
                      722,
                      667,
                      944,
                      667,
                      667,
                      611,
                      278,
                      278,
                      278,
                      469,
                      556,
                      333,
                      556,
                      556,
                      500,
                      556,
                      556,
                      278,
                      556,
                      556,
                      222,
                      222,
                      500,
                      222,
                      833,
                      556,
                      556,
                      556,
                      556,
                      333,
                      500,
                      278,
                      556,
                      500,
                      722,
                      500,
                      500,
                      500,
                      334,
                      260,
                      334,
                      584
                    ]
                    |> Enum.with_index(32)
                    |> Map.new(fn {width, code} -> {code, width} end)

  @helvetica_bold_widths [
                           278,
                           333,
                           474,
                           556,
                           556,
                           889,
                           722,
                           238,
                           333,
                           333,
                           389,
                           584,
                           278,
                           333,
                           278,
                           278,
                           556,
                           556,
                           556,
                           556,
                           556,
                           556,
                           556,
                           556,
                           556,
                           556,
                           333,
                           333,
                           584,
                           584,
                           584,
                           611,
                           975,
                           722,
                           722,
                           722,
                           722,
                           667,
                           611,
                           778,
                           722,
                           278,
                           556,
                           722,
                           611,
                           833,
                           722,
                           778,
                           667,
                           778,
                           722,
                           667,
                           611,
                           722,
                           667,
                           944,
                           667,
                           667,
                           611,
                           333,
                           278,
                           333,
                           584,
                           556,
                           333,
                           556,
                           611,
                           556,
                           611,
                           556,
                           333,
                           611,
                           611,
                           278,
                           278,
                           556,
                           278,
                           889,
                           611,
                           611,
                           611,
                           611,
                           389,
                           556,
                           333,
                           611,
                           556,
                           778,
                           556,
                           556,
                           500,
                           389,
                           280,
                           389,
                           584
                         ]
                         |> Enum.with_index(32)
                         |> Map.new(fn {width, code} -> {code, width} end)

  @default_width 556

  # The typographic characters common enough in pasted text to be worth
  # mapping rather than dropping; everything else outside Latin-1 becomes "?".
  @winansi %{
    0x20AC => 0x80,
    0x201A => 0x82,
    0x0192 => 0x83,
    0x201E => 0x84,
    0x2026 => 0x85,
    0x2020 => 0x86,
    0x2021 => 0x87,
    0x02C6 => 0x88,
    0x2030 => 0x89,
    0x0160 => 0x8A,
    0x2039 => 0x8B,
    0x0152 => 0x8C,
    0x017D => 0x8E,
    0x2018 => 0x91,
    0x2019 => 0x92,
    0x201C => 0x93,
    0x201D => 0x94,
    0x2022 => 0x95,
    0x2013 => 0x96,
    0x2014 => 0x97,
    0x02DC => 0x98,
    0x2122 => 0x99,
    0x0161 => 0x9A,
    0x203A => 0x9B,
    0x0153 => 0x9C,
    0x017E => 0x9E,
    0x0178 => 0x9F
  }

  @greys %{black: "0 0 0", grey: "0.45 0.45 0.45", light: "0.6 0.6 0.6"}

  defstruct [:title, pages: [], current: [], y: @top, footer: nil]

  @type t :: %__MODULE__{
          title: String.t() | nil,
          pages: [iodata()],
          current: iodata(),
          y: number(),
          footer: String.t() | nil
        }

  @doc """
  A writer positioned at the top of its first page.

  ## Options

    * `:title` - the document title, written into the PDF's metadata, which
      is what a reader shows in its window and what a browser suggests when
      printing. Not drawn — a caller draws its own heading
    * `:footer` - a line drawn small and grey at the foot of every page,
      before the page number. `nil` for the page number alone
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{title: opts[:title], footer: opts[:footer]}
  end

  @doc """
  The page width available to a caller, in points — what `text/3` wraps
  within, less any `:indent`.
  """
  @spec content_width() :: number()
  def content_width, do: @content_width

  @doc """
  Draws a paragraph at the cursor, wrapped to the content width, and leaves
  the cursor under its last line.

  ## Options

    * `:font` - `:regular` (the default) or `:bold`
    * `:size` - point size, `10` by default
    * `:color` - `:black` (the default), `:grey`, or `:light`
    * `:indent` - points to inset from the left margin, `0` by default; the
      wrap width narrows to match
    * `:leading` - baseline-to-baseline distance, `1.35` times the size by
      default
  """
  @spec text(t(), String.t() | nil, keyword()) :: t()
  def text(writer, text, opts \\ [])

  def text(writer, nil, opts), do: text(writer, "", opts)

  def text(writer, "", opts) do
    # An empty value still occupies its line, so a field with no answer keeps
    # the shape of one that has an answer
    space(writer, leading(opts))
  end

  def text(writer, text, opts) when is_binary(text) do
    font = Keyword.get(opts, :font, :regular)
    size = Keyword.get(opts, :size, 10)
    color = Map.fetch!(@greys, Keyword.get(opts, :color, :black))
    indent = Keyword.get(opts, :indent, 0)
    leading = leading(opts)

    text
    |> wrap(@content_width - indent, font, size)
    |> Enum.reduce(writer, fn line, writer ->
      writer = break_if_needed(writer, leading)
      y = writer.y - leading

      %{writer | y: y, current: [writer.current, line_ops(line, font, size, color, indent, y)]}
    end)
  end

  @doc """
  Moves the cursor down without drawing.

  Never breaks the page on its own: space that would run off the bottom is
  simply not taken, so the next thing drawn starts at the top of the next
  page rather than under a gap.
  """
  @spec space(t(), number()) :: t()
  def space(writer, points) do
    if writer.y - points < @bottom, do: writer, else: %{writer | y: writer.y - points}
  end

  @doc """
  Draws a hairline rule across the content width, with a little air above
  and below it.
  """
  @spec rule(t()) :: t()
  def rule(writer) do
    writer = writer |> space(4) |> break_if_needed(6)
    y = writer.y

    ops = [
      "0.85 0.85 0.85 RG\n0.5 w\n",
      float(@margin),
      " ",
      float(y),
      " m\n",
      float(@page_width - @margin),
      " ",
      float(y),
      " l\nS\n"
    ]

    %{writer | y: y - 6, current: [writer.current, ops]}
  end

  @doc """
  Starts a new page, leaving the cursor at its top. A page nothing has been
  drawn on yet is left alone, so a caller can ask for a fresh page without
  risking a blank one.
  """
  @spec page_break(t()) :: t()
  def page_break(%__MODULE__{current: [], y: @top} = writer), do: writer

  def page_break(writer) do
    %{writer | pages: writer.pages ++ [writer.current], current: [], y: @top}
  end

  @doc """
  The finished PDF.

  The cursor's page is closed, page numbers are stamped ("1 of 3", which
  needs the total and so cannot be drawn before now), and the objects are
  assembled with the cross-reference table the format requires.
  """
  @spec to_binary(t()) :: binary()
  def to_binary(writer) do
    pages =
      case writer.pages ++ [writer.current] do
        [[]] -> [[]]
        pages -> pages
      end

    total = length(pages)

    pages
    |> Enum.with_index(1)
    |> Enum.map(fn {page, number} ->
      IO.iodata_to_binary([page, footer_ops(writer.footer, number, total)])
    end)
    |> assemble(writer.title)
  end

  @doc """
  The width of a string set in one of the two fonts at a point size, in
  points. What `text/3` wraps with, and public because a caller laying out
  columns of its own needs the same measure.
  """
  @spec text_width(String.t(), :regular | :bold, number()) :: float()
  def text_width(text, font, size) do
    widths = if font == :bold, do: @helvetica_bold_widths, else: @helvetica_widths

    text
    |> encode()
    |> :binary.bin_to_list()
    |> Enum.reduce(0, fn byte, total -> total + Map.get(widths, byte, @default_width) end)
    |> Kernel.*(size / 1000)
  end

  @doc """
  A string as WinAnsi bytes: ASCII and Latin-1 through, the mapped
  typographic characters converted, everything else `?`.
  """
  @spec encode(String.t()) :: binary()
  def encode(text) do
    text
    |> String.replace(~r/[\r\n\t]+/, " ")
    |> String.to_charlist()
    |> Enum.map(fn
      code when code in 32..126 -> code
      code when code in 160..255 -> code
      code -> Map.get(@winansi, code, ?\?)
    end)
    |> :erlang.list_to_binary()
  end

  # --- layout -----------------------------------------------------------------

  defp leading(opts) do
    Keyword.get(opts, :leading, Keyword.get(opts, :size, 10) * 1.35)
  end

  defp break_if_needed(writer, needed) do
    if writer.y - needed < @bottom, do: page_break(writer), else: writer
  end

  # Greedy wrap on spaces. A single word wider than the line is broken at the
  # last character that fits, so a pasted URL or a long identifier stays on
  # the page instead of running off it.
  defp wrap(text, width, font, size) do
    text
    |> String.split(~r/\s+/, trim: true)
    |> Enum.reduce([], &append_word(&2, &1, width, font, size))
    |> Enum.reverse()
    |> case do
      [] -> [""]
      lines -> lines
    end
  end

  # Lines accumulate in reverse, so the line being filled is the head
  defp append_word([], word, width, font, size) do
    Enum.reverse(split_word(word, width, font, size))
  end

  defp append_word([current | rest] = lines, word, width, font, size) do
    candidate = current <> " " <> word

    if text_width(candidate, font, size) <= width do
      [candidate | rest]
    else
      Enum.reverse(split_word(word, width, font, size)) ++ lines
    end
  end

  defp split_word("", _width, _font, _size), do: []

  defp split_word(word, width, font, size) do
    if text_width(word, font, size) <= width do
      [word]
    else
      {head, rest} = take_while_fits(word, width, font, size)

      [head | split_word(rest, width, font, size)]
    end
  end

  defp take_while_fits(word, width, font, size) do
    graphemes = String.graphemes(word)

    count =
      Enum.reduce_while(1..length(graphemes)//1, 1, fn index, _last ->
        candidate = graphemes |> Enum.take(index) |> Enum.join()

        if text_width(candidate, font, size) <= width,
          do: {:cont, index},
          else: {:halt, max(index - 1, 1)}
      end)

    {Enum.join(Enum.take(graphemes, count)), Enum.join(Enum.drop(graphemes, count))}
  end

  defp line_ops(line, font, size, color, indent, y) do
    [
      "BT\n/",
      font_resource(font),
      " ",
      float(size),
      " Tf\n",
      color,
      " rg\n1 0 0 1 ",
      float(@margin + indent),
      " ",
      float(y),
      " Tm\n(",
      escape(line),
      ") Tj\nET\n"
    ]
  end

  defp footer_ops(footer, number, total) do
    label = [footer, footer && "  ·  ", "#{number} of #{total}"] |> Enum.reject(&is_nil/1)

    line_ops(
      IO.iodata_to_binary(label),
      :regular,
      8,
      @greys.light,
      0,
      @footer_baseline
    )
  end

  defp font_resource(:bold), do: "F2"
  defp font_resource(_regular), do: "F1"

  # Byte-level on purpose: WinAnsi bytes above 127 are not valid UTF-8, so the
  # three characters PDF string syntax reserves are escaped as bytes
  defp escape(text) do
    text
    |> encode()
    |> :binary.replace("\\", "\\\\", [:global])
    |> :binary.replace("(", "\\(", [:global])
    |> :binary.replace(")", "\\)", [:global])
  end

  # PDF numbers have no exponent form, so a float is written plainly and
  # trimmed of the noise two decimals of rounding leaves behind
  defp float(number) when is_integer(number), do: Integer.to_string(number)

  defp float(number) do
    number
    |> Float.round(2)
    |> :erlang.float_to_binary(decimals: 2)
    |> String.replace(~r/\.?0+$/, "")
    |> case do
      "" -> "0"
      "-" -> "0"
      trimmed -> trimmed
    end
  end

  # --- file assembly ----------------------------------------------------------

  # Object numbers are fixed so the page and content objects can reference
  # each other without a second pass: 1 catalog, 2 page tree, 3 and 4 the
  # fonts, 5 the metadata, then a page object and its content stream per page.
  @catalog 1
  @page_tree 2
  @font_regular 3
  @font_bold 4
  @info 5
  @first_page 6

  defp assemble(streams, title) do
    count = length(streams)

    kids =
      Enum.map_join(0..(count - 1)//1, " ", fn index -> "#{@first_page + 2 * index} 0 R" end)

    objects =
      [
        {@catalog, "<< /Type /Catalog /Pages #{@page_tree} 0 R >>"},
        {@page_tree, "<< /Type /Pages /Kids [#{kids}] /Count #{count} >>"},
        {@font_regular, font_object("Helvetica")},
        {@font_bold, font_object("Helvetica-Bold")},
        {@info, info_object(title)}
      ] ++
        Enum.flat_map(Enum.with_index(streams), fn {stream, index} ->
          page = @first_page + 2 * index

          [{page, page_object(page + 1)}, {page + 1, content_object(stream)}]
        end)

    body(objects)
  end

  defp font_object(name) do
    "<< /Type /Font /Subtype /Type1 /BaseFont /#{name} /Encoding /WinAnsiEncoding >>"
  end

  defp page_object(contents) do
    "<< /Type /Page /Parent #{@page_tree} 0 R " <>
      "/MediaBox [0 0 #{@page_width} #{@page_height}] " <>
      "/Resources << /Font << /F1 #{@font_regular} 0 R /F2 #{@font_bold} 0 R >> >> " <>
      "/Contents #{contents} 0 R >>"
  end

  defp content_object(stream) do
    "<< /Length #{byte_size(stream)} >>\nstream\n#{stream}endstream"
  end

  defp info_object(title) do
    stamp = Calendar.strftime(DateTime.utc_now(), "D:%Y%m%d%H%M%SZ")

    "<< /Producer (FormFlow) /Title (#{escape(title || "")}) /CreationDate (#{stamp}) >>"
  end

  defp body(objects) do
    header = "%PDF-1.4\n%\xE2\xE3\xCF\xD3\n"

    {chunks, offsets, size} =
      objects
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.reduce({[], %{}, byte_size(header)}, fn {number, content}, {chunks, offsets, at} ->
        chunk = "#{number} 0 obj\n#{content}\nendobj\n"

        {[chunk | chunks], Map.put(offsets, number, at), at + byte_size(chunk)}
      end)

    highest = objects |> Enum.map(&elem(&1, 0)) |> Enum.max()

    xref =
      Enum.map_join(0..highest//1, fn
        0 -> "0000000000 65535 f \n"
        number -> "#{String.pad_leading("#{Map.fetch!(offsets, number)}", 10, "0")} 00000 n \n"
      end)

    trailer =
      "trailer\n<< /Size #{highest + 1} /Root #{@catalog} 0 R /Info #{@info} 0 R >>\n" <>
        "startxref\n#{size}\n%%EOF\n"

    IO.iodata_to_binary([
      header,
      Enum.reverse(chunks),
      "xref\n0 #{highest + 1}\n",
      xref,
      trailer
    ])
  end
end
