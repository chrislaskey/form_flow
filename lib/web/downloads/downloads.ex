defmodule FormFlow.Web.Downloads do
  @moduledoc """
  `FormFlow.Web.Downloads` is the half of a download that never touches a
  connection: a resource becomes a `FormFlow.Web.Downloads.Document`, a
  `FormFlow.Web.Downloads.Renderer` turns that into bytes, and this module
  joins the two.

  `FormFlow.Web.Controllers.Downloads` is the other half — the request and
  the response — and it is the only caller today. Keeping them apart is what
  lets a download be produced without one: a scheduled job that files
  submitted forms somewhere calls `render/4` with the same context a request
  would have built.

  The library ships `FormFlow.Web.Downloads.Renderer.PDF` and
  `FormFlow.Web.Downloads.Renderer.HTML`, and a host mounts a renderer of its
  own when it wants more than either draws.
  """

  alias FormFlow.Context
  alias FormFlow.Web.Downloads.Document

  @default_renderer FormFlow.Web.Downloads.Renderer.PDF

  @doc """
  The renderer used when a mount names none —
  `FormFlow.Web.Downloads.Renderer.PDF`.
  """
  @spec default_renderer() :: module()
  def default_renderer, do: @default_renderer

  @doc """
  Renders a document, returning the bytes, the content type to send them as,
  and the filename to offer — the document's own `:filename` with the
  renderer's extension.

  `{:error, message}` is whatever the renderer refused with, passed through
  unchanged.
  """
  @spec render(Document.t(), Context.t(), map(), module()) ::
          {:ok, binary(), String.t(), String.t()} | {:error, String.t()}
  def render(%Document{} = document, context, callback_data, renderer) do
    case renderer.render(document, context, callback_data) do
      {:ok, body, content_type} ->
        {:ok, body, content_type, "#{document.filename}.#{renderer.extension()}"}

      {:error, message} when is_binary(message) ->
        {:error, message}

      other ->
        raise ArgumentError,
              "#{inspect(renderer)}.render/3 returned #{inspect(other)}; " <>
                "expected {:ok, body, content_type} or {:error, message}"
    end
  end
end
