// The flow editor: ordinary React + JSX, written the way the ReactFlow docs are
// written. This source never ships to an app installing form_flow — build.sh
// compiles it into priv/static/form_flow_editor.mjs, which is committed.
//
// The public surface is mount/unmount/injectStyles, called by the colocated
// hook in FormFlow.Web.Templates.Forms.Index.
import React, { createContext, useCallback, useContext, useEffect, useState } from "react";
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

// Callbacks the custom nodes need but that must never live in node.data —
// data round-trips to the server as JSON, and functions don't survive that
const EditorContext = createContext({ onOpenSubflow: null, onOpenForm: null });

// isConnectable must be passed through to every Handle: it is how ReactFlow
// delivers nodesConnectable to custom nodes, and Handle defaults to true
// when it is omitted — which would leave handles live on read-only canvases.
function StepNode({ id, data, selected, isConnectable }) {
  const { onOpenForm } = useContext(EditorContext);

  return (
    <div className={`ff-node ff-node--${data.kind} ${selected ? "is-selected" : ""}`}>
      {data.kind !== "start" && (
        <Handle type="target" position={Position.Top} isConnectable={isConnectable} />
      )}
      <div className="ff-node__title">{data.label}</div>
      <div className="ff-node__meta">{(data.labels ?? []).join(", ")}</div>
      {data.kind === "form" && (
        <button
          type="button"
          className="ff-node__open"
          onClick={(event) => {
            event.stopPropagation();
            onOpenForm?.(id);
          }}
        >
          Open →
        </button>
      )}
      {data.kind !== "end" && (
        <Handle type="source" position={Position.Bottom} isConnectable={isConnectable} />
      )}
    </div>
  );
}

function SubflowNode({ id, data, selected, isConnectable }) {
  const { onOpenSubflow } = useContext(EditorContext);

  return (
    <div className={`ff-node ff-node--subflow ${selected ? "is-selected" : ""}`}>
      <Handle type="target" position={Position.Top} isConnectable={isConnectable} />
      <div className="ff-node__title">⧉ {data.label}</div>
      <div className="ff-node__meta">
        {data.subflow_label === "subflows" ? "Complex subflow" : "Form subflow"}
      </div>
      <button
        type="button"
        className="ff-node__open"
        onClick={(event) => {
          event.stopPropagation();
          onOpenSubflow?.(id);
        }}
      >
        Open →
      </button>
      <Handle type="source" position={Position.Bottom} isConnectable={isConnectable} />
    </div>
  );
}

// Must be module-level (or useMemo'd): a new object each render remounts every node
const nodeTypes = { step: StepNode, subflow: SubflowNode };

// The flow itself is defined in Elixir — see
// FormFlow.Web.Templates.Flows.Graph — serialized to JSON, and handed in as
// opts.graph. This is only the fallback for mounting with nothing at all, so it
// is deliberately empty rather than a second, competing definition of a flow.
const EMPTY_GRAPH = { nodes: [], edges: [] };

// Nodes are positioned by their top centre, so a node dropped at the cursor
// lands under it rather than to its right
const NODE_ORIGIN = [0.5, 0];

// Ids stay in the same simple numeric style the server sends, without colliding
// with the ids already in play
function nextId(nodes) {
  const used = new Set(nodes.map((node) => node.id));
  let candidate = nodes.length + 1;

  while (used.has(String(candidate))) candidate += 1;

  return String(candidate);
}

// What the add actions create. In a "forms" flow the only kind is a form
// step; in a "subflows" flow the node embeds a child whose flavor was chosen
// by the button (data.subflow_label) — the server reads it at save to create
// the child.
function newNode(flowLabel, subflowLabel, id, position) {
  if (flowLabel === "subflows") {
    return {
      id,
      type: "subflow",
      position,
      origin: NODE_ORIGIN,
      data: { label: `Subflow ${id}`, subflow_label: subflowLabel },
    };
  }

  return {
    id,
    type: "step",
    position,
    origin: NODE_ORIGIN,
    data: { label: `Form ${id}`, kind: "form" },
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

function FlowEditor({
  graph,
  onChange,
  editable = true,
  flowLabel = "forms",
  onOpenSubflow,
  onOpenForm,
}) {
  // One state object on purpose. With separate node/edge states, a handler
  // reporting to the server reads the *other* collection from a stale render
  // closure — deleting a node (which also auto-removes its edges) once
  // reported "node still present, edges gone", and saving persisted the
  // ghost. Functional updates over the combined state always see the whole
  // current picture.
  const [state, setState] = useState(() => normalize(graph));

  const { screenToFlowPosition } = useReactFlow();

  // Elixir can push new data at any time (see form_flow:set_graph). useState
  // ignores a changed initial value, so the canvas has to be told explicitly.
  useEffect(() => {
    setState(normalize(graph));
  }, [graph]);

  const report = useCallback(
    (next) => {
      if (onChange) onChange({ nodes: next.nodes, edges: next.edges });
    },
    [onChange],
  );

  const onNodesChange = useCallback(
    (changes) =>
      setState((current) => {
        const next = { ...current, nodes: applyNodeChanges(changes, current.nodes) };

        // Report what's worth persisting: drag-ends (dragging fires
        // continuously) and removals. Additions report from their creators.
        if (
          changes.some(
            (change) =>
              (change.type === "position" && change.dragging === false) ||
              change.type === "remove",
          )
        ) {
          report(next);
        }

        return next;
      }),
    [report],
  );

  const onEdgesChange = useCallback(
    (changes) =>
      setState((current) => {
        const next = { ...current, edges: applyEdgeChanges(changes, current.edges) };

        if (changes.some((change) => change.type === "remove")) {
          report(next);
        }

        return next;
      }),
    [report],
  );

  const onConnect = useCallback(
    (connection) => {
      if (!editable) return;

      setState((current) => {
        const next = {
          ...current,
          edges: addEdge({ ...connection, markerEnd: { type: MarkerType.ArrowClosed } }, current.edges),
        };

        report(next);
        return next;
      });
    },
    [editable, report],
  );

  // Dropping a connection on empty canvas creates the node it would have gone
  // to, wired up — a form step, or in a subflows flow a Form subflow, the
  // common case. https://reactflow.dev/examples/nodes/add-node-on-edge-drop
  const onConnectEnd = useCallback(
    (event, connectionState) => {
      // Belt and braces: with isConnectable wired through, no connection can
      // start on a read-only canvas — but node creation must never slip in
      if (!editable) return;

      // A drop that landed on a handle is an ordinary connection; onConnect has it
      if (connectionState.isValid) return;

      const source = connectionState.fromNode?.id;
      if (!source) return;

      const { clientX, clientY } = "changedTouches" in event ? event.changedTouches[0] : event;
      const position = screenToFlowPosition({ x: clientX, y: clientY });

      setState((current) => {
        const id = nextId(current.nodes);
        const next = {
          nodes: current.nodes.concat(newNode(flowLabel, "forms", id, position)),
          edges: current.edges.concat(stepEdge(source, id)),
        };

        report(next);
        return next;
      });
    },
    [editable, flowLabel, report, screenToFlowPosition],
  );

  const addNode = useCallback(
    (subflowLabel) => {
      setState((current) => {
        const id = nextId(current.nodes);
        const last = current.nodes[current.nodes.length - 1];
        const position = {
          x: (last?.position.x ?? 240) + 220,
          y: last?.position.y ?? 120,
        };

        const next = {
          ...current,
          nodes: current.nodes.concat(newNode(flowLabel, subflowLabel, id, position)),
        };

        report(next);
        return next;
      });
    },
    [flowLabel, report],
  );

  return (
    <EditorContext.Provider value={{ onOpenSubflow, onOpenForm }}>
    <ReactFlow
      nodes={state.nodes}
      edges={state.edges}
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
      connectionRadius={40}
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
          {flowLabel === "subflows" ? (
            <>
              <button type="button" onClick={() => addNode("forms")}>
                + Form subflow
              </button>
              <button type="button" onClick={() => addNode("subflows")}>
                + Complex subflow
              </button>
            </>
          ) : (
            <button type="button" onClick={() => addNode(null)}>
              + Form
            </button>
          )}
        </Panel>
      )}
    </ReactFlow>
    </EditorContext.Provider>
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
 * nothing can be selected, dragged, connected, or deleted. Opening a subflow
 * still works — it is navigation, not editing.
 *
 * `flowLabel` ("forms" | "subflows") picks the add actions and what edge-drop
 * autocreate makes; `onOpenSubflow(nodeId)` is called by a subflow node's
 * Open button, `onOpenForm(nodeId)` by a form step's.
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
        <FlowEditor
          graph={graph}
          onChange={opts.onChange}
          editable={opts.editable !== false}
          flowLabel={opts.flowLabel}
          onOpenSubflow={opts.onOpenSubflow}
          onOpenForm={opts.onOpenForm}
        />
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
