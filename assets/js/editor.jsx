// The flow editor: ordinary React + JSX, written the way the ReactFlow docs are
// written. This source never ships to an app installing form_flow — build.sh
// compiles it into priv/static/form_flow_editor.mjs, which is committed.
//
// The public surface is mount/unmount/injectStyles, called by the colocated
// hook in FormFlow.Web.Templates.Forms.Index.
import React, { useCallback, useMemo, useState } from "react";
import { createRoot } from "react-dom/client";
import {
  ReactFlow,
  Background,
  Controls,
  MiniMap,
  Panel,
  Handle,
  Position,
  MarkerType,
  addEdge,
  applyNodeChanges,
  applyEdgeChanges,
} from "@xyflow/react";

import flowStyles from "@xyflow/react/dist/style.css";
import editorStyles from "../css/editor.css";

/* ------------------------------------------------------------------ nodes -- */

function StepNode({ data, selected }) {
  return (
    <div className={`ff-node ff-node--${data.kind} ${selected ? "is-selected" : ""}`}>
      {data.kind !== "start" && <Handle type="target" position={Position.Top} />}
      <div className="ff-node__title">{data.label}</div>
      <div className="ff-node__meta">
        {data.fields} field{data.fields === 1 ? "" : "s"}
      </div>
      {data.kind !== "end" && <Handle type="source" position={Position.Bottom} />}
    </div>
  );
}

// Must be module-level (or useMemo'd): a new object each render remounts every node
const nodeTypes = { step: StepNode };

const DEFAULT_GRAPH = {
  nodes: [
    { id: "1", type: "step", position: { x: 240, y: 0 }, data: { label: "Start", kind: "start", fields: 0 } },
    { id: "2", type: "step", position: { x: 240, y: 120 }, data: { label: "Contact details", kind: "form", fields: 4 } },
    { id: "3", type: "step", position: { x: 240, y: 260 }, data: { label: "Review", kind: "end", fields: 1 } },
  ],
  edges: [
    { id: "e1-2", source: "1", target: "2", markerEnd: { type: MarkerType.ArrowClosed } },
    { id: "e2-3", source: "2", target: "3", markerEnd: { type: MarkerType.ArrowClosed } },
  ],
};

/* ----------------------------------------------------------------- editor -- */

function FlowEditor({ graph, onChange }) {
  const initial = useMemo(() => normalize(graph), [graph]);

  const [nodes, setNodes] = useState(initial.nodes);
  const [edges, setEdges] = useState(initial.edges);

  // Only report the changes worth persisting; dragging fires continuously
  const report = useCallback(
    (nextNodes, nextEdges) => {
      if (onChange) onChange({ nodes: nextNodes, edges: nextEdges });
    },
    [onChange],
  );

  const onNodesChange = useCallback(
    (changes) =>
      setNodes((current) => {
        const next = applyNodeChanges(changes, current);
        if (changes.some((change) => change.type === "position" && change.dragging === false)) {
          report(next, edges);
        }
        return next;
      }),
    [edges, report],
  );

  const onEdgesChange = useCallback(
    (changes) =>
      setEdges((current) => {
        const next = applyEdgeChanges(changes, current);
        report(nodes, next);
        return next;
      }),
    [nodes, report],
  );

  const onConnect = useCallback(
    (connection) =>
      setEdges((current) => {
        const next = addEdge({ ...connection, markerEnd: { type: MarkerType.ArrowClosed } }, current);
        report(nodes, next);
        return next;
      }),
    [nodes, report],
  );

  const addStep = useCallback(() => {
    const id = String(Date.now());
    const last = nodes[nodes.length - 1];

    const node = {
      id,
      type: "step",
      position: { x: (last?.position.x ?? 240) + 220, y: last?.position.y ?? 120 },
      data: { label: "New step", kind: "form", fields: 0 },
    };

    setNodes((current) => {
      const next = [...current, node];
      report(next, edges);
      return next;
    });
  }, [edges, nodes, report]);

  return (
    <ReactFlow
      nodes={nodes}
      edges={edges}
      nodeTypes={nodeTypes}
      onNodesChange={onNodesChange}
      onEdgesChange={onEdgesChange}
      onConnect={onConnect}
      fitView
      proOptions={{ hideAttribution: false }}
    >
      <Background variant="dots" gap={16} size={1} />
      <Controls />
      <MiniMap pannable zoomable />
      <Panel position="top-left" className="ff-panel">
        <button type="button" onClick={addStep}>
          + Add step
        </button>
      </Panel>
    </ReactFlow>
  );
}

function normalize(graph) {
  if (!graph || !Array.isArray(graph.nodes) || graph.nodes.length === 0) return DEFAULT_GRAPH;

  return { nodes: graph.nodes, edges: Array.isArray(graph.edges) ? graph.edges : [] };
}

/* ----------------------------------------------------------------- public -- */

const roots = new WeakMap();

/**
 * Appends the editor's stylesheet once per document. Called by the hook before
 * mounting, so no stylesheet has to be served or imported separately.
 */
export function injectStyles(doc = document) {
  if (doc.getElementById("form-flow-editor-styles")) return;

  const style = doc.createElement("style");
  style.id = "form-flow-editor-styles";
  style.textContent = flowStyles + editorStyles;
  doc.head.appendChild(style);
}

/**
 * Renders the editor into `el`.
 *
 * Returns a handle with `setGraph/1` so the server can push a new graph in, and
 * `unmount/0` for teardown.
 */
export function mount(el, opts = {}) {
  const root = createRoot(el);
  const render = (graph) => root.render(<FlowEditor graph={graph} onChange={opts.onChange} />);

  roots.set(el, root);
  render(opts.graph);

  return {
    setGraph: (graph) => render(graph),
    unmount: () => unmount(el),
  };
}

export function unmount(el) {
  roots.get(el)?.unmount();
  roots.delete(el);
}
