// The flow editor: ordinary React + JSX, written the way the ReactFlow docs are
// written. This source never ships to an app installing form_flow — build.sh
// compiles it into priv/static/form_flow_editor.mjs, which is committed.
//
// The public surface is mount/unmount/injectStyles, called by the colocated
// hook in FormFlow.Web.Templates.Forms.Index.
import React, { createContext, useCallback, useContext, useEffect, useRef, useState } from "react";
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

// Callbacks and editor-level settings the custom nodes need but that must
// never live in node.data — data round-trips to the server as JSON, and
// functions don't survive that
const EditorContext = createContext({
  onOpenSubflow: null,
  onOpenForm: null,
  onNodeDataChange: null,
  editable: true,
  formFlowTypeOptions: [],
  formTypeOptions: [],
  focusId: null,
  clearFocus: null,
});

// The node's name as an inline input (edit mode only) — renaming without the
// drill-in to each node's dedicated page. The label lives in node.data like
// every canvas edit; for nodes backed by a real entity (a subflow's embedded
// flow, a form step's form) the server writes the rename through to that
// entity's name at save, so this and the dedicated page's Name field edit the
// same value. A just-created node's input autofocuses with its placeholder
// name selected, so typing renames it immediately (focusId, set by the node
// creators).
function NodeTitleInput({ id, label }) {
  const { onNodeDataChange, focusId, clearFocus } = useContext(EditorContext);
  const ref = useRef(null);

  // The just-created-node autofocus, with the placeholder name selected so
  // typing replaces it. Not React's autoFocus attribute: ReactFlow renders a
  // fresh node with visibility: hidden until it has been measured, and
  // focus() on a hidden element silently does nothing — so this retries
  // across a few frames until the focus actually takes.
  useEffect(() => {
    if (focusId !== id) return undefined;

    let attempts = 0;
    let frame;

    const tryFocus = () => {
      const input = ref.current;
      if (!input) return;

      input.focus({ preventScroll: true });

      if (document.activeElement === input) {
        input.select();
      } else if ((attempts += 1) < 30) {
        frame = requestAnimationFrame(tryFocus);
      }
    };

    frame = requestAnimationFrame(tryFocus);
    return () => cancelAnimationFrame(frame);
  }, [focusId, id]);

  return (
    <input
      ref={ref}
      type="text"
      className="ff-node__title-input nodrag nopan"
      value={label ?? ""}
      aria-label="Node name"
      onBlur={() => focusId === id && clearFocus?.()}
      onChange={(event) => onNodeDataChange?.(id, { label: event.target.value })}
      onKeyDown={(event) => event.key === "Enter" && event.target.blur()}
    />
  );
}

// The ⋮ menu every node carries: a general-purpose dropdown for managing the
// node through the UI. ReactFlow has no native menu component (its closest
// natives are <NodeToolbar> and the hand-rolled context-menu example), so this
// is ours: `items` is a list of {label, destructive?, confirm?, onSelect} —
// node types compose it from the shared entries (useNodeMenuItems) plus their
// own. An item with `confirm` asks before acting, so a misclick in a growing
// menu can't fire anything destructive. Renders nothing with no items, e.g.
// read-only canvases today.
function NodeMenu({ items }) {
  const [open, setOpen] = useState(false);
  const ref = useRef(null);

  // Close on click-away or Escape. pointerdown (not click) so starting any
  // interaction elsewhere — a drag, another node's menu — dismisses this one.
  useEffect(() => {
    if (!open) return undefined;

    const onPointerDown = (event) => {
      if (!ref.current?.contains(event.target)) setOpen(false);
    };
    const onKeyDown = (event) => {
      if (event.key === "Escape") setOpen(false);
    };

    document.addEventListener("pointerdown", onPointerDown);
    document.addEventListener("keydown", onKeyDown);

    return () => {
      document.removeEventListener("pointerdown", onPointerDown);
      document.removeEventListener("keydown", onKeyDown);
    };
  }, [open]);

  if (!items.length) return null;

  return (
    <div className="ff-node__menu nodrag nopan" ref={ref}>
      <button
        type="button"
        className="ff-node__menu-button"
        aria-haspopup="menu"
        aria-expanded={open}
        aria-label="Node actions"
        onClick={(event) => {
          event.stopPropagation();
          setOpen((current) => !current);
        }}
      >
        ⋮
      </button>
      {open && (
        <div className="ff-node__menu-list" role="menu">
          {items.map((item) => (
            <button
              key={item.label}
              type="button"
              role="menuitem"
              className={`ff-node__menu-item ${item.destructive ? "is-destructive" : ""}`}
              onClick={(event) => {
                event.stopPropagation();
                setOpen(false);

                if (item.confirm && !window.confirm(item.confirm)) return;

                item.onSelect();
              }}
            >
              {item.label}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

// The menu entries every node type shares; specific node types concat their
// own after these. Delete goes through ReactFlow's deleteElements — the same
// path as the Backspace key — so connected edges cascade, deletable: false is
// respected, and the removal reaches the server through the ordinary
// onNodesChange/onEdgesChange reports.
function useNodeMenuItems(id, deletable) {
  const { editable } = useContext(EditorContext);
  const { deleteElements } = useReactFlow();

  const items = [];

  if (editable && deletable !== false) {
    items.push({
      label: "Delete",
      destructive: true,
      confirm: "Delete this node? Its connections go with it. Nothing is final until you save.",
      onSelect: () => deleteElements({ nodes: [{ id }] }),
    });
  }

  return items;
}

// isConnectable must be passed through to every Handle: it is how ReactFlow
// delivers nodesConnectable to custom nodes, and Handle defaults to true
// when it is omitted — which would leave handles live on read-only canvases.
function StepNode({ id, data, selected, isConnectable, deletable }) {
  const { onOpenForm, onNodeDataChange, editable, formTypeOptions } = useContext(EditorContext);
  const menuItems = useNodeMenuItems(id, deletable);

  // The form_type dropdown, on form steps: how the collected form behaves
  // for the user filling it out. Stored in node.data like a subflow's
  // form_flow_type, and written through to the form at save the same way.
  // The options are exactly the configured types; an unset type shows the
  // first, which is what the server resolves it to. A type's properties are
  // set on the form's own page, not here.
  const typeLabel =
    formTypeOptions.find((option) => option.value === data.form_type)?.label ?? data.form_type;

  return (
    <div className={`ff-node ff-node--${data.kind} ${selected ? "is-selected" : ""}`}>
      <NodeMenu items={menuItems} />
      {data.kind !== "start" && (
        <Handle type="target" position={Position.Top} isConnectable={isConnectable} />
      )}
      <div className="ff-node__title">
        {editable ? <NodeTitleInput id={id} label={data.label} /> : data.label}
      </div>
      <div className="ff-node__meta">{(data.labels ?? []).join(", ")}</div>
      {data.kind === "form" &&
        (editable ? (
          <select
            className="ff-node__type nodrag nopan"
            value={data.form_type ?? formTypeOptions[0]?.value ?? ""}
            onChange={(event) => onNodeDataChange?.(id, { form_type: event.target.value })}
          >
            {formTypeOptions.map((option) => (
              <option key={option.value} value={option.value}>
                {option.label}
              </option>
            ))}
          </select>
        ) : (
          data.form_type && <div className="ff-node__type-label">{typeLabel}</div>
        ))}
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

function SubflowNode({ id, data, selected, isConnectable, deletable }) {
  const { onOpenSubflow, onNodeDataChange, editable, formFlowTypeOptions } =
    useContext(EditorContext);
  const menuItems = useNodeMenuItems(id, deletable);

  // The form_flow_type dropdown, on form subflows only: how the embedded
  // flow's steps are presented to the user filling it out. Stored in
  // node.data, so it rides the ordinary properties round-trip to the server.
  // The options are exactly the configured types; an unset type shows the
  // first, which is what the server resolves it to.
  const isFormSubflow = data.subflow_label !== "subflows";
  const typeLabel =
    formFlowTypeOptions.find((option) => option.value === data.form_flow_type)?.label ??
    data.form_flow_type;

  return (
    <div className={`ff-node ff-node--subflow ${selected ? "is-selected" : ""}`}>
      <NodeMenu items={menuItems} />
      <Handle type="target" position={Position.Top} isConnectable={isConnectable} />
      <div className="ff-node__title">
        <span aria-hidden="true">⧉</span>
        {editable ? <NodeTitleInput id={id} label={data.label} /> : data.label}
      </div>
      <div className="ff-node__meta">
        {data.subflow_label === "subflows" ? "Complex subflow" : "Form subflow"}
      </div>
      {isFormSubflow &&
        (editable ? (
          // nodrag/nopan: interacting with the select must not move the canvas
          <select
            className="ff-node__type nodrag nopan"
            value={data.form_flow_type ?? formFlowTypeOptions[0]?.value ?? ""}
            onChange={(event) => onNodeDataChange?.(id, { form_flow_type: event.target.value })}
          >
            {formFlowTypeOptions.map((option) => (
              <option key={option.value} value={option.value}>
                {option.label}
              </option>
            ))}
          </select>
        ) : (
          data.form_flow_type && <div className="ff-node__type-label">{typeLabel}</div>
        ))}
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
// FormFlow.Web.Helpers.ReactFlow.to_data/1 — serialized to JSON, and handed in
// as opts.flow. This is only the fallback for mounting with nothing at all, so
// it is deliberately empty rather than a second, competing definition of a flow.
const EMPTY_FLOW = { nodes: [], edges: [] };

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
  flow,
  onChange,
  editable = true,
  flowLabel = "forms",
  formFlowTypeOptions = [],
  formTypeOptions = [],
  onOpenSubflow,
  onOpenForm,
}) {
  // One state object on purpose. With separate node/edge states, a handler
  // reporting to the server reads the *other* collection from a stale render
  // closure — deleting a node (which also auto-removes its edges) once
  // reported "node still present, edges gone", and saving persisted the
  // ghost. Functional updates over the combined state always see the whole
  // current picture.
  const [state, setState] = useState(() => normalize(flow));

  // The node whose name input should grab the keyboard: set when a node is
  // created (so its placeholder name can be typed over immediately), cleared
  // when that input blurs. autoFocus only acts at mount, so a stale id is
  // inert — the clear just keeps re-renders honest.
  const [focusId, setFocusId] = useState(null);
  const clearFocus = useCallback(() => setFocusId(null), []);

  const { screenToFlowPosition } = useReactFlow();

  // Elixir can push new data at any time (see form_flow:set_flow). useState
  // ignores a changed initial value, so the canvas has to be told explicitly.
  useEffect(() => {
    setState(normalize(flow));
  }, [flow]);

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

        setFocusId(id);
        report(next);
        return next;
      });
    },
    [editable, flowLabel, report, screenToFlowPosition],
  );

  // In-node controls (the type dropdowns) editing node.data. Merges the patch
  // and reports immediately — a picked value is worth persisting, like a
  // drag-end.
  const onNodeDataChange = useCallback(
    (id, patch) =>
      setState((current) => {
        const next = {
          ...current,
          nodes: current.nodes.map((node) =>
            node.id === id ? { ...node, data: { ...node.data, ...patch } } : node,
          ),
        };

        report(next);
        return next;
      }),
    [report],
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

        setFocusId(id);
        report(next);
        return next;
      });
    },
    [flowLabel, report],
  );

  return (
    <EditorContext.Provider
      value={{
        onOpenSubflow,
        onOpenForm,
        onNodeDataChange,
        editable,
        formFlowTypeOptions,
        formTypeOptions,
        focusId,
        clearFocus,
      }}
    >
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

function normalize(flow) {
  if (!flow || !Array.isArray(flow.nodes)) return EMPTY_FLOW;

  return { nodes: flow.nodes, edges: Array.isArray(flow.edges) ? flow.edges : [] };
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
 * `formFlowTypeOptions` ([{label, value}]) are the form_flow_type choices a
 * form subflow node offers: a dropdown when editable, the stored value's
 * label when not. The chosen value lives in the node's data and rides the
 * ordinary onChange round-trip. `formTypeOptions` are the same for a form
 * step's form_type.
 *
 * Returns a handle with `setFlow/1` so the server can push a new flow in, and
 * `unmount/0` for teardown.
 */
export function mount(el, opts = {}) {
  const root = createRoot(el);
  const render = (flow) =>
    root.render(
      // useReactFlow (used for screenToFlowPosition) requires this provider
      <ReactFlowProvider>
        <FlowEditor
          flow={flow}
          onChange={opts.onChange}
          editable={opts.editable !== false}
          flowLabel={opts.flowLabel}
          formFlowTypeOptions={opts.formFlowTypeOptions}
          formTypeOptions={opts.formTypeOptions}
          onOpenSubflow={opts.onOpenSubflow}
          onOpenForm={opts.onOpenForm}
        />
      </ReactFlowProvider>,
    );

  roots.set(el, root);
  render(opts.flow);

  return {
    setFlow: (flow) => render(flow),
    unmount: () => unmount(el),
  };
}

export function unmount(el) {
  roots.get(el)?.unmount();
  roots.delete(el);
}
