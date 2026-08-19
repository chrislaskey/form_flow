defmodule FormFlow.Web.Helpers.ReactFlow do
  @moduledoc """
  `FormFlow.Web.Helpers.ReactFlow` module hands Elixir-defined data to
  [ReactFlow](https://reactflow.dev).

  The data is passed through unchanged. Nothing is defaulted, renamed, derived,
  or reordered: what you write in Elixir is what ReactFlow receives, so its own
  documentation describes the shape you write, and anything ReactFlow supports
  works here without this module knowing about it.

      data = %{
        nodes: [
          %{
            id: "1",
            type: "step",
            position: %{x: 240, y: 0},
            data: %{label: "Start", kind: "start", fields: 0}
          },
          %{
            id: "2",
            type: "step",
            position: %{x: 240, y: 140},
            data: %{label: "Form", kind: "form", fields: 4}
          }
        ],
        edges: [
          %{id: "e1-2", source: "1", target: "2", markerEnd: %{type: "arrowclosed"}}
        ]
      }

      ReactFlow.to_json(data)

  Keys stay exactly as ReactFlow spells them, camel case included — `markerEnd`,
  `sourceHandle`, `animated`.

  ## What ReactFlow requires

  Worth knowing, since this module adds nothing on your behalf:

    * **`position` is required on every node.** ReactFlow's layout reads
      `node.position.x` directly; there is no default and no automatic layout in
      ReactFlow core.
    * **Edges are never inferred.** ReactFlow draws exactly the edges you list —
      listing nodes in order does not connect them. An edge needs `id`, `source`,
      and `target`.
    * `type` is optional and falls back to ReactFlow's `"default"` node.
    * Arrowheads are opt-in per edge, via `markerEnd`.

  ## The node type FormFlow ships

  `type: "step"` selects FormFlow's own node, which reads three keys out of
  `data`:

    * `label` - the text drawn on the node
    * `kind` - `"start"`, `"form"`, or `"end"`. Sets the node's colour, and
      which connection handles it gets
    * `fields` - the field count shown under the label

  Any other node type you register in the editor is passed through the same way.
  """

  @doc """
  Encodes ReactFlow data as JSON, ready to hand to the editor.

  Uses the application's configured JSON library, so an app that has swapped
  Phoenix's default is respected.
  """
  def to_json(data) when is_map(data) do
    Phoenix.json_library().encode!(data)
  end
end
