// The flow editor: ordinary React + JSX, written the way the ReactFlow docs are
// written. This source never ships to an app installing form_flow — build.sh
// compiles it into priv/static/form_flow_editor.mjs, which is committed.
//
// The public surface is mount/unmount/injectStyles, called by the colocated
// hook in FormFlow.Web.Templates.Forms.Index.
import React, { useCallback, useEffect, useState } from "react";
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
  useReactFlow,
  ReactFlowProvider,
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

// The flow itself is defined in Elixir — see
// FormFlow.Web.Templates.Flows.Graph — serialized to JSON, and handed in as
// opts.graph. This is only the fallback for mounting with nothing at all, so it
// is deliberately empty rather than a second, competing definition of a flow.
const EMPTY_GRAPH = { nodes: [], edges: [] };

// Nodes are positioned by their top centre, so a node dropped at the cursor
// lands under it rather than to its right
const NODE_ORIGIN = [0.5, 0];

const NEW_STEP = { kind: "form", fields: 0 };

// Ids stay in the same simple numeric style the server sends, without colliding
// with the ids already in play
function nextId(nodes) {
  const used = new Set(nodes.map((node) => node.id));
  let candidate = nodes.length + 1;

  while (used.has(String(candidate))) candidate += 1;

  return String(candidate);
}

function stepNode(id, position) {
  return {
    id,
    type: "step",
    position,
    origin: NODE_ORIGIN,
    data: { label: `Step ${id}`, ...NEW_STEP },
  };
}

function stepEdge(source, target) {
  return {
    id: `e${source}-${target}`,
    source,
    target,
    markerEnd: { type: MarkerType.ArrowClosed },
  };
}

/* ----------------------------------------------------------------- editor -- */

function FlowEditor({ graph, onChange, editable = true }) {
  const [nodes, setNodes] = useState(() => normalize(graph).nodes);
  const [edges, setEdges] = useState(() => normalize(graph).edges);

  const { screenToFlowPosition } = useReactFlow();

  // Elixir can push new data at any time (see form_flow:set_graph). useState
  // ignores a changed initial value, so the canvas has to be told explicitly.
  useEffect(() => {
    const next = normalize(graph);

    setNodes(next.nodes);
    setEdges(next.edges);
  }, [graph]);

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

  // Dropping a connection on empty canvas creates the step it would have gone
  // to, wired up. https://reactflow.dev/examples/nodes/add-node-on-edge-drop
  const onConnectEnd = useCallback(
    (event, connectionState) => {
      // A drop that landed on a handle is an ordinary connection; onConnect has it
      if (connectionState.isValid) return;

      const source = connectionState.fromNode?.id;
      if (!source) return;

      const { clientX, clientY } = "changedTouches" in event ? event.changedTouches[0] : event;
      const position = screenToFlowPosition({ x: clientX, y: clientY });

      setNodes((currentNodes) => {
        const id = nextId(currentNodes);
        const nextNodes = currentNodes.concat(stepNode(id, position));

        setEdges((currentEdges) => {
          const nextEdges = currentEdges.concat(stepEdge(source, id));
          report(nextNodes, nextEdges);
          return nextEdges;
        });

        return nextNodes;
      });
    },
    [report, screenToFlowPosition],
  );

  const addStep = useCallback(() => {
    setNodes((current) => {
      const id = nextId(current);
      const last = current[current.length - 1];
      const position = {
        x: (last?.position.x ?? 240) + 220,
        y: last?.position.y ?? 120,
      };

      const next = current.concat(stepNode(id, position));
      report(next, edges);
      return next;
    });
  }, [edges, report]);

  return (
    <ReactFlow
      nodes={nodes}
      edges={edges}
      nodeTypes={nodeTypes}
      nodeOrigin={NODE_ORIGIN}
      onNodesChange={onNodesChange}
      onEdgesChange={onEdgesChange}
      onConnect={onConnect}
      onConnectEnd={onConnectEnd}
      nodesDraggable={editable}
      nodesConnectable={editable}
      elementsSelectable={editable}
      edgesReconnectable={editable}
      deleteKeyCode={editable ? "Backspace" : null}
      fitView
      fitViewOptions={{ padding: 0.4 }}
      proOptions={{ hideAttribution: false }}
    >
      <Background variant="dots" gap={16} size={1} />
      {/* showInteractive hides the lock button read-only pages, since it could
          re-enable interactivity from inside the canvas */}
      <Controls showInteractive={editable} />
      <MiniMap pannable zoomable />
      {editable && (
        <Panel position="top-left" className="ff-panel">
          <button type="button" onClick={addStep}>
            + Add step
          </button>
        </Panel>
      )}
    </ReactFlow>
  );
}

function normalize(graph) {
  if (!graph || !Array.isArray(graph.nodes)) return EMPTY_GRAPH;

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
 * Pass `editable: false` for a read-only canvas: pan and zoom still work, but
 * nothing can be selected, dragged, connected, or deleted.
 *
 * Returns a handle with `setGraph/1` so the server can push a new graph in, and
 * `unmount/0` for teardown.
 */
export function mount(el, opts = {}) {
  const root = createRoot(el);
  const render = (graph) =>
    root.render(
      // useReactFlow (used for screenToFlowPosition) requires this provider
      <ReactFlowProvider>
        <FlowEditor graph={graph} onChange={opts.onChange} editable={opts.editable !== false} />
      </ReactFlowProvider>,
    );

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
