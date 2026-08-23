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

  ## Persistence

  `to_graph_attrs/1` and `to_data/1` translate between ReactFlow's shape and
  `FormFlow.Data.Graph` records, and are inverses of each other:

    * A ReactFlow node becomes a `FormFlow.Data.Graph.Node` whose `properties`
      are the node map itself, minus `id` — position, type, data, and anything
      else ReactFlow supports round-trips untouched.
    * A ReactFlow edge becomes a `FormFlow.Data.Graph.Relationship` the same
      way, minus `id`, `source`, and `target`, which become columns. Every
      relationship gets the label `"CONNECTS_TO"` — the editor's
      edges all mean the same thing today.
    * Ids from the editor (`"1"`, `"4"`) are replaced with generated UUIDs at
      save time; ids that already are UUIDs are kept, so unchanged records are
      updated in place rather than recreated.

  Saved properties also carry a `"graph_id"` key — the schemas keep a copy of
  the `graph_id` column inside `properties` (see `FormFlow.Data.Graph.Node`).
  It rides through the editor and back as any other property; the column stays
  authoritative on save.
  """

  @edge_label "CONNECTS_TO"

  @doc """
  Encodes ReactFlow data as JSON, ready to hand to the editor.

  Uses the application's configured JSON library, so an app that has swapped
  Phoenix's default is respected.
  """
  def to_json(data) when is_map(data) do
    Phoenix.json_library().encode!(data)
  end

  @doc """
  Converts ReactFlow data into attributes for `FormFlow.Data.Graphs.create/1`
  and `FormFlow.Data.Graphs.update/2`.

  Accepts the shape the editor reports (string keys) or the shape flows are
  written in Elixir (atom keys). See the module documentation for the mapping.
  """
  def to_graph_attrs(data) when is_map(data) do
    %{"nodes" => nodes, "edges" => edges} =
      data
      |> string_keys()
      |> Map.put_new("nodes", [])
      |> Map.put_new("edges", [])

    ids = Map.new(nodes, fn node -> {node["id"], uuid(node["id"])} end)

    %{
      nodes:
        Enum.map(nodes, fn node ->
          %{id: ids[node["id"]], properties: Map.delete(node, "id")}
        end),
      relationships:
        Enum.map(edges, fn edge ->
          %{
            id: uuid(edge["id"]),
            source_id: Map.get(ids, edge["source"], edge["source"]),
            target_id: Map.get(ids, edge["target"], edge["target"]),
            label: @edge_label,
            properties: Map.drop(edge, ["id", "source", "target"])
          }
        end)
    }
  end

  @doc """
  Converts a loaded `FormFlow.Data.Graph` back into ReactFlow data — the
  inverse of `to_graph_attrs/1`. Node and edge ids are the records' UUIDs.
  """
  def to_data(%FormFlow.Data.Graph{} = graph) do
    %{
      nodes: Enum.map(graph.nodes, fn node -> Map.put(node.properties, "id", node.id) end),
      edges:
        Enum.map(graph.relationships, fn relationship ->
          relationship.properties
          |> Map.put("id", relationship.id)
          |> Map.put("source", relationship.source_id)
          |> Map.put("target", relationship.target_id)
        end)
    }
  end

  # Atom or string keys in, string keys out — the same normalization the data
  # goes through anyway on its way to the browser
  defp string_keys(data) do
    data |> Phoenix.json_library().encode!() |> Phoenix.json_library().decode!()
  end

  defp uuid(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> id
      :error -> Ecto.UUID.generate()
    end
  end
end
