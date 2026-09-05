defmodule FormFlow.Web.Downloads.Document do
  @moduledoc """
  `FormFlow.Web.Downloads.Document` is what FormFlow hands a
  `FormFlow.Web.Downloads.Renderer`: one resource, flattened into the parts a
  printable page is made of, with nothing of the format it will be printed
  in.

  It sits between the two halves of a download on purpose. On one side, a
  parser turns a resource into this — the parsers live beside the components
  that draw the same resource on screen, and
  `FormFlow.Web.Components.Forms.Downloads.Parsers.FormInstance` is the one
  that reads a form instance today. On the other, a renderer turns this into
  bytes. Neither half knows the other, so a new resource is a new parser and
  a new format is a new renderer, and the two never multiply.

  ## Fields

    * `:title` - the heading, the one line that says what this is
    * `:subtitle` - what it belongs to, drawn under the title; `nil` for none
    * `:details` - `{label, value}` pairs about the resource itself rather
      than its content — when it was submitted, what version it is against —
      drawn as a block under the heading
    * `:sections` - the content, in order, as `t:section/0` structs
    * `:filename` - the base name a download is saved as, without an
      extension; the renderer appends its own

  ## Sections and entries

  A section is a titled run of entries; a section with no title is the run
  before the first heading, which is where a form's top-level questions
  land. Entries are one of three shapes, each a tagged tuple so a renderer
  can pattern match rather than inspect:

    * `{:field, label, value}` - a label and its value, both already
      strings. An unanswered question is a field with an empty value; it is
      drawn rather than dropped, because a printed record says what was not
      answered as much as what was
    * `{:text, text}` - prose that is not a field, from a definition's
      static content
    * `{:group, title, entries}` - a run inside a section: one entry of a
      repeating question, or a panel inside one. `title` is `nil` for a run
      the definition heads with nothing, which is still its own group —
      where the entries begin and end is the point, and a heading is not the
      only thing that says so. Groups nest, and hold the same three shapes,
      because the forms they come from nest: a repeating question inside a
      repeating question is a group of groups

  Every value is a string by the time it reaches here. Formatting a stored
  answer — a list, a choice's stored value, a boolean — is the parser's
  job, so that every renderer prints the same words.
  """

  alias FormFlow.Web.Downloads.Document.Section

  defstruct [:title, :subtitle, :filename, details: [], sections: []]

  @type entry ::
          {:field, String.t(), String.t()}
          | {:text, String.t()}
          | {:group, String.t() | nil, [entry()]}

  @type section :: Section.t()

  @type t :: %__MODULE__{
          title: String.t(),
          subtitle: String.t() | nil,
          filename: String.t(),
          details: [{String.t(), String.t()}],
          sections: [section()]
        }

  defmodule Section do
    @moduledoc """
    One titled run of a `FormFlow.Web.Downloads.Document`'s content.

    `:title` is `nil` for the run before the first heading — a form's
    top-level questions, drawn with no heading of their own.
    """

    defstruct [:title, entries: []]

    @type t :: %__MODULE__{
            title: String.t() | nil,
            entries: [FormFlow.Web.Downloads.Document.entry()]
          }
  end

  @doc """
  Whether the document has any content to draw — a section holding at least
  one entry. A renderer draws its "nothing here" line instead when it does
  not; the heading and details are still worth printing, since they say what
  the empty thing was.
  """
  @spec any_content?(t()) :: boolean()
  def any_content?(%__MODULE__{sections: sections}) do
    Enum.any?(sections, &(&1.entries != []))
  end

  @doc """
  A string made safe to use as a filename: anything outside letters, digits,
  and `-` collapses to a single `-`, the result trimmed of leading and
  trailing dashes and cut to 80 characters. Falls back to `fallback` when
  nothing is left, so a form titled entirely in a script this drops still
  downloads under a usable name.
  """
  @spec slugify(String.t() | nil, String.t()) :: String.t()
  def slugify(value, fallback \\ "download")

  def slugify(value, fallback) when is_binary(value) do
    slug =
      value
      |> String.replace(~r/[^A-Za-z0-9-]+/u, "-")
      |> String.trim("-")
      |> String.slice(0, 80)
      |> String.trim("-")

    if slug == "", do: fallback, else: String.downcase(slug)
  end

  def slugify(_value, fallback), do: fallback
end
