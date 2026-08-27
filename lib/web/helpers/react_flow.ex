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
            data: %{label: "Start", kind: "start"}
          },
          %{
            id: "2",
            type: "step",
            position: %{x: 240, y: 140},
            data: %{label: "Form", kind: "form"}
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

  `type: "step"` selects FormFlow's own node, which reads two keys out of
  `data`:

    * `label` - the text drawn on the node
    * `kind` - `"start"`, `"form"`, or `"end"`. Sets the node's colour, and
      which connection handles it gets

  `to_data/1` adds a third key, `labels` — the node's stored
  `FormFlow.Data.Templates.Flow.Node.labels`, shown under the title. It isn't
  something you set by hand in the map above; see Persistence below.

  Any other node type you register in the editor is passed through the same way.

  ## Persistence

  `to_flow_attrs/1` and `to_data/1` translate between ReactFlow's shape and
  `FormFlow.Data.Templates.Flow` records, and are inverses of each other:

    * A ReactFlow node becomes a `FormFlow.Data.Templates.Flow.Node` whose
      `properties` are the node map itself, minus `id` — position, type, data,
      and anything else ReactFlow supports round-trips untouched.
    * A ReactFlow edge becomes a `FormFlow.Data.Templates.Flow.Relationship`
      the same way, minus `id`, `source`, and `target`, which become columns.
      Every relationship gets the label `"CONNECTS_TO"` — the editor's edges
      all mean the same thing today.
    * Ids from the editor (`"1"`, `"4"`) are replaced with generated UUIDs at
      save time; ids that already are UUIDs are kept, so unchanged records are
      updated in place rather than recreated. `to_flow_attrs/1`'s `id_map`
      return value is how a caller finds out what a given editor id became.

  Saved properties also carry a `"flow_id"` key — the schemas keep a copy of
  the `flow_id` column inside `properties` (see
  `FormFlow.Data.Templates.Flow.Node`). It rides through the editor and back
  as any other property; the column stays authoritative on save.

  Two exceptions to the pure pass-through, both display projections
  `to_data/1` merges into a node's `data`:

    * `labels` — the node's stored `FormFlow.Data.Templates.Flow.Node.labels`.
      Nothing sets it the other way — the editor never writes labels back, so
      `to_flow_attrs/1` just carries whatever it finds there like any other
      property, and the changeset re-derives the authoritative value on save.
    * `form_flow_type` — the *embedded flow's* `properties["form_flow_type"]`,
      on subflow nodes (requires the node's `:subflow` preloaded, which
      `FormFlow.Data.Templates.Flows.get/1` does). This one does flow back:
      the canvas dropdown edits it, and `FormFlow.Data.Templates.Flows`
      pops it out of the node's properties at save and writes it through to
      the embedded flow — the single stored copy.
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
  Converts ReactFlow data into attributes for
  `FormFlow.Data.Templates.Flows.create/1` and
  `FormFlow.Data.Templates.Flows.update/2`.

  Accepts the shape the editor reports (string keys) or the shape flows are
  written in Elixir (atom keys). See the module documentation for the mapping.

  The result also carries `id_map`: editor node/edge id (string) to the id it
  was saved under. For an id that was already a UUID this is the identity —
  the mapping only does real work for the editor's temporary ids (`"1"`,
  `"4"`), generated fresh on every call since nothing here is stored yet. A
  caller that needs to know what a just-created node's id became — e.g. to
  navigate straight to it after the save this attrs map is about to go
  into — reads it from here rather than guessing.
  """
  def to_flow_attrs(data) when is_map(data) do
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
        end),
      id_map: ids
    }
  end

  @doc """
  Converts a loaded `FormFlow.Data.Templates.Flow` back into ReactFlow data —
  the inverse of `to_flow_attrs/1`. Node and edge ids are the records' UUIDs.
  """
  def to_data(%FormFlow.Data.Templates.Flow{} = flow) do
    %{
      nodes: Enum.map(flow.nodes, &node_data/1),
      edges:
        Enum.map(flow.relationships, fn relationship ->
          relationship.properties
          |> Map.put("id", relationship.id)
          |> Map.put("source", relationship.source_id)
          |> Map.put("target", relationship.target_id)
        end)
    }
  end

  defp node_data(node) do
    node.properties
    |> Map.put("id", node.id)
    |> put_labels(node.labels)
    |> put_form_flow_type(node)
  end

  # A node with no labels (nothing has run its changeset yet) is left exactly
  # as stored, matching to_data/1's otherwise-untouched pass-through.
  defp put_labels(properties, []), do: properties

  defp put_labels(properties, labels) do
    Map.update(properties, "data", %{"labels" => labels}, &Map.put(&1, "labels", labels))
  end

  # The embedded flow's type, projected into data for the canvas dropdown —
  # the load-side mirror of the save-side pop in
  # FormFlow.Data.Templates.Flows. An untyped, absent, or unloaded subflow
  # (%Ecto.Association.NotLoaded{} has no :properties) merges nothing.
  defp put_form_flow_type(properties, node) do
    case node.subflow do
      %{properties: %{"form_flow_type" => type}} ->
        Map.update(
          properties,
          "data",
          %{"form_flow_type" => type},
          &Map.put(&1, "form_flow_type", type)
        )

      _other ->
        properties
    end
  end

  # Atom or string keys in, string keys out — the same normalization the data
  # goes through anyway on its way to the browser
  defp string_keys(data) do
    data |> Phoenix.json_library().encode!() |> Phoenix.json_library().decode!()
  end

  # Existing UUIDs pass through unchanged — a load-bearing invariant, not a
  # convenience: form-instance `path`s (the visit identity of in-journey
  # fills) reference node ids, so a save that re-idented existing nodes
  # would strand every in-flight journey (instances plan, "path
  # stability"). Only non-UUID ids — ReactFlow's temp ids for newly added
  # nodes — get fresh UUIDs.
  defp uuid(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> id
      :error -> Ecto.UUID.generate()
    end
  end
end
