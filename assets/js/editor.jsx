// The flow editor: ordinary React + JSX, written the way the ReactFlow docs are
// written. This source never ships to an app installing form_flow — build.sh
// compiles it into priv/static/form_flow_editor.mjs, which is committed.
//
// The public surface is mount/unmount/injectStyles, called by the colocated
// hook in FormFlow.Web.Templates.Forms.Index.
import React, {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
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
  BaseEdge,
  addEdge,
  applyNodeChanges,
  applyEdgeChanges,
  useReactFlow,
  useNodesInitialized,
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
  flowTypeOptions: [],
  formTypeOptions: [],
  perspectiveOptions: [],
  focusId: null,
  clearFocus: null,
});

// Who a form subflow is for, named under its type. Read-only here: the
// perspectives are set on the subflow's own page, and the ids ride in
// node.data as a display projection the server drops at save.
function NodePerspectives({ ids }) {
  const { perspectiveOptions } = useContext(EditorContext);

  if (!ids?.length) return null;

  const names = ids.map(
    (id) => perspectiveOptions.find((option) => option.value === id)?.label ?? id,
  );

  return (
    <div className="ff-node__perspectives" title="Perspectives">
      <svg aria-hidden="true" viewBox="0 0 16 16" fill="currentColor">
        <path d="M8 8a3 3 0 1 0 0-6 3 3 0 0 0 0 6ZM12.735 14c.618 0 1.093-.561.872-1.139a6.002 6.002 0 0 0-11.215 0c-.22.578.254 1.139.872 1.139h9.47Z" />
      </svg>
      <span className="ff-node__perspectives-title">Perspectives</span>
      <span>{names.join(", ")}</span>
    </div>
  );
}

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
// menu can't fire anything destructive; one with `disabled` stays listed
// with its `title` saying why. Renders nothing with no items, e.g. a Start
// node on a read-only canvas.
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
              disabled={item.disabled}
              title={item.title}
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
// own after these. Copy puts a snapshot of the step on the clipboard (see
// "clipboard" below) — offered on form and subflow steps, on the read-only
// canvas too since copying writes nothing, and disabled until the step has
// been saved, since the save copies from the source by its real id. Delete
// goes through ReactFlow's deleteElements — the same path as the
// Backspace key — so connected edges cascade, deletable: false is respected,
// and the removal reaches the server through the ordinary
// onNodesChange/onEdgesChange reports.
function useNodeMenuItems(id, deletable) {
  const { editable } = useContext(EditorContext);
  const { deleteElements, getNode } = useReactFlow();

  const items = [];
  const node = getNode(id);

  if (node && copyableKind(node)) {
    const saved = isSaved(node);

    items.push({
      label: "Copy",
      disabled: !saved,
      title: saved ? "Copy this step, to paste onto this or another canvas" : "Save before copying",
      onSelect: () => {
        const current = getNode(id);
        if (current) writeClipboard(current);
      },
    });
  }

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

// A pasted step wears this until it is saved: the save copies the step it
// came from for it and drops the mark, so the fresh data the server pushes
// back draws the node without it
function CopyMark() {
  return (
    <span className="ff-node__copy" title="A pasted step. Saving makes it a copy of its own.">
      Copy
    </span>
  );
}

// isConnectable must be passed through to every Handle: it is how ReactFlow
// delivers nodesConnectable to custom nodes, and Handle defaults to true
// when it is omitted — which would leave handles live on read-only canvases.
function StepNode({ id, data, selected, isConnectable, deletable }) {
  const { onOpenForm, onNodeDataChange, editable, formTypeOptions } = useContext(EditorContext);
  const menuItems = useNodeMenuItems(id, deletable);

  // The form_type dropdown, on form steps: how the collected form behaves
  // for the user filling it out. Stored in node.data like a subflow's
  // flow_type, and written through to the form at save the same way.
  // The options are exactly the configured types; an unset type shows the
  // first, which is what the server resolves it to. A type's properties are
  // set on the form's own page, not here.
  const typeLabel =
    formTypeOptions.find((option) => option.value === data.form_type)?.label ?? data.form_type;

  // Edges leave a step's right side and enter its left - unless the
  // overview's layout has turned the step's handles to the vertical
  // (data.handles "vertical"): a Start stood above its level's row of steps
  // and an End below it on the balanced layout, or every node of a level
  // stacked top to bottom on the vertical one. Then edges leave the bottom
  // and arrive at the top.
  const vertical = data.handles === "vertical";

  return (
    <div className={`ff-node ff-node--${data.kind} ${selected ? "is-selected" : ""}`}>
      <NodeMenu items={menuItems} />
      {data.kind !== "start" && (
        <Handle
          type="target"
          position={vertical ? Position.Top : Position.Left}
          isConnectable={isConnectable}
        />
      )}
      <div className="ff-node__title">
        {editable ? <NodeTitleInput id={id} label={data.label} /> : data.label}
      </div>
      <div className="ff-node__meta">
        {(data.labels ?? []).join(", ")}
        {data.copy_of_node_id && <CopyMark />}
      </div>
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
        <Handle
          type="source"
          position={vertical ? Position.Bottom : Position.Right}
          isConnectable={isConnectable}
        />
      )}
    </div>
  );
}

// The type options for one kind of flow - what a node embedding such a flow
// offers. An option without a kind is offered to every node.
function optionsForKind(options, kind) {
  return options.filter((option) => !option.kind || option.kind === kind);
}

function SubflowNode({ id, data, selected, isConnectable, deletable }) {
  const { onOpenSubflow, onNodeDataChange, editable, flowTypeOptions } =
    useContext(EditorContext);
  const menuItems = useNodeMenuItems(id, deletable);

  // The flow_type dropdown: how the embedded flow is worked - a form subflow's
  // wizard, a complex subflow's order. Stored in node.data, so it rides the
  // ordinary properties round-trip to the server. The options are the
  // configured types of the kind the node embeds; an unset type shows the
  // first, which is what the server resolves it to.
  const isFormSubflow = data.subflow_label !== "subflows";
  const typeOptions = optionsForKind(flowTypeOptions, isFormSubflow ? "forms" : "subflows");
  const typeLabel =
    typeOptions.find((option) => option.value === data.flow_type)?.label ?? data.flow_type;

  return (
    <div className={`ff-node ff-node--subflow ${selected ? "is-selected" : ""}`}>
      <NodeMenu items={menuItems} />
      <Handle type="target" position={Position.Left} isConnectable={isConnectable} />
      <div className="ff-node__title">
        <span aria-hidden="true">⧉</span>
        {editable ? <NodeTitleInput id={id} label={data.label} /> : data.label}
      </div>
      <div className="ff-node__meta">
        {data.subflow_label === "subflows" ? "Complex subflow" : "Form subflow"}
        {data.copy_of_node_id && <CopyMark />}
      </div>
      {typeOptions.length > 0 &&
        (editable ? (
          // nodrag/nopan: interacting with the select must not move the canvas
          <select
            className="ff-node__type nodrag nopan"
            value={data.flow_type ?? typeOptions[0]?.value ?? ""}
            onChange={(event) => onNodeDataChange?.(id, { flow_type: event.target.value })}
          >
            {typeOptions.map((option) => (
              <option key={option.value} value={option.value}>
                {option.label}
              </option>
            ))}
          </select>
        ) : (
          data.flow_type && <div className="ff-node__type-label">{typeLabel}</div>
        ))}
      {isFormSubflow && <NodePerspectives ids={data.perspectives} />}
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
      <Handle type="source" position={Position.Right} isConnectable={isConnectable} />
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

// Nodes are positioned by their left centre, so a node dropped at the cursor
// lands beside it rather than below it — flows build left to right
const NODE_ORIGIN = [0, 0.5];

// Ids stay in the same simple numeric style the server sends, without colliding
// with the ids already in play
function nextId(nodes) {
  const used = new Set(nodes.map((node) => node.id));
  let candidate = nodes.length + 1;

  while (used.has(String(candidate))) candidate += 1;

  return String(candidate);
}

// Where an added or pasted node lands: to the right of the last one
function nextPosition(nodes) {
  const last = nodes[nodes.length - 1];

  return {
    x: (last?.position.x ?? 240) + 220,
    y: last?.position.y ?? 120,
  };
}

/* -------------------------------------------------------------- clipboard -- */

// Copy and paste of one step at a time, across canvases and across tabs. The
// clipboard is the browser's localStorage, not anything on the server: the
// editor is a LiveComponent inside the host's LiveView, whose state does not
// survive navigating to another flow's canvas — which is exactly the paste
// we want — and nothing is written until Save. What is stored is a snapshot
// of the ReactFlow node as it was when copied, and when. Paste adds the
// snapshot as a new node whose data.copy_of_node_id names the source; the
// save copies the entity behind the source for it and never stores the
// marker (FormFlow.Data.Templates.Flows, "Pasting a step"), so the mark
// goes away with the fresh data the server pushes back. The snapshot's
// stale form_id/subflow_id copies ride along like any node's and are
// dropped by the save. A snapshot older than a day is ignored and removed:
// the step it names has likely moved on, and a save whose source is gone is
// refused.
const CLIPBOARD_KEY = "form_flow:clipboard";
const CLIPBOARD_MAX_AGE_MS = 24 * 60 * 60 * 1000;
const CLIPBOARD_EVENT = "form_flow:clipboard";

function readClipboard() {
  try {
    const raw = window.localStorage.getItem(CLIPBOARD_KEY);
    if (!raw) return null;

    const entry = JSON.parse(raw);
    if (!entry?.node?.id || typeof entry.copied_at !== "number") return null;

    if (Date.now() - entry.copied_at > CLIPBOARD_MAX_AGE_MS) {
      window.localStorage.removeItem(CLIPBOARD_KEY);
      return null;
    }

    return entry;
  } catch {
    // Storage unavailable (private mode, disabled) or unreadable: no clipboard
    return null;
  }
}

function writeClipboard(node) {
  try {
    window.localStorage.setItem(CLIPBOARD_KEY, JSON.stringify({ node, copied_at: Date.now() }));
    // storage events reach *other* documents only; tell this one as well
    window.dispatchEvent(new Event(CLIPBOARD_EVENT));
  } catch {
    // The copy did not take; nothing to undo
  }
}

// The clipboard entry as it stands, following copies made here, in another
// tab (storage), or while this tab was in the background (focus)
function useClipboard() {
  const [entry, setEntry] = useState(readClipboard);

  useEffect(() => {
    const refresh = () => setEntry(readClipboard());

    window.addEventListener("storage", refresh);
    window.addEventListener(CLIPBOARD_EVENT, refresh);
    window.addEventListener("focus", refresh);

    return () => {
      window.removeEventListener("storage", refresh);
      window.removeEventListener(CLIPBOARD_EVENT, refresh);
      window.removeEventListener("focus", refresh);
    };
  }, []);

  return entry;
}

// Stored nodes carry the server's UUIDs; a node added since the last save
// has a temporary id (nextId) and nothing behind it yet to copy
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function isSaved(node) {
  return UUID.test(node.id);
}

// Form steps and subflow steps have an entity behind them to copy; Start and
// End do not
function copyableKind(node) {
  return node.type === "subflow" || node.data?.kind === "form";
}

// Whether the clipboard's step fits this canvas: a subflow step on a
// "subflows" canvas, a form step on a "forms" one. The server's flavor rule
// refuses the rest at save; this keeps the button from offering it.
function fitsCanvas(entry, flowLabel) {
  if (!entry) return false;

  return flowLabel === "subflows"
    ? entry.node.type === "subflow"
    : entry.node.type === "step" && entry.node.data?.kind === "form";
}

// The pasted node: the snapshot's data marked as a copy of its source, under
// a fresh id at the given position. The snapshot's placement, selection, and
// measurements stay behind.
function pastedNode(entry, id, position) {
  const { position: _position, selected: _selected, dragging: _dragging, measured: _measured, ...node } =
    entry.node;

  return {
    ...node,
    id,
    position,
    origin: NODE_ORIGIN,
    data: { ...node.data, copy_of_node_id: entry.node.id },
  };
}

function copiedAgo(entry) {
  const minutes = Math.round((Date.now() - entry.copied_at) / 60000);

  if (minutes < 1) return "just now";
  if (minutes < 60) return `${minutes} min ago`;

  const hours = Math.round(minutes / 60);
  return `${hours} ${hours === 1 ? "hour" : "hours"} ago`;
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
  flowTypeOptions = [],
  formTypeOptions = [],
  perspectiveOptions = [],
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

        const next = {
          ...current,
          nodes: current.nodes.concat(
            newNode(flowLabel, subflowLabel, id, nextPosition(current.nodes)),
          ),
        };

        setFocusId(id);
        report(next);
        return next;
      });
    },
    [flowLabel, report],
  );

  // The clipboard as the Paste button shows it; the paste itself reads again,
  // since the entry may have expired while the button was on screen
  const clipboard = useClipboard();

  const pasteNode = useCallback(() => {
    const entry = readClipboard();
    if (!fitsCanvas(entry, flowLabel)) return;

    setState((current) => {
      const id = nextId(current.nodes);
      const next = {
        ...current,
        nodes: current.nodes.concat(pastedNode(entry, id, nextPosition(current.nodes))),
      };

      report(next);
      return next;
    });
  }, [flowLabel, report]);

  return (
    <EditorContext.Provider
      value={{
        onOpenSubflow,
        onOpenForm,
        onNodeDataChange,
        editable,
        flowTypeOptions,
        formTypeOptions,
        perspectiveOptions,
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
          {fitsCanvas(clipboard, flowLabel) && (
            <button
              type="button"
              className="ff-panel__paste"
              title={`Paste a copy of “${clipboard.node.data?.label ?? "this step"}”, copied ${copiedAgo(clipboard)}`}
              onClick={pasteNode}
            >
              Paste “{clipboard.node.data?.label ?? "step"}”
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

/* --------------------------------------------------------------- overview -- */

// The overview: one read-only canvas of the whole flow, every level at once.
// The server hands in a *tree* — FormFlow.Web.Helpers.ReactFlow.to_tree_data/1:
// this level's nodes and edges, plus `subflows`, the same shape again for the
// flow each subflow node embeds, keyed by that node's id — already narrowed
// to the nodes connected to Start (FormFlow.Data.Templates.Flows.connected_tree/1).
// Every subflow node becomes a group node with its inner flow drawn inside
// it, using ReactFlow's parentId nesting; Start, End, and form nodes are the
// canvas's own StepNode, read-only.
//
// ReactFlow has no layout engine, so positions are computed here (layoutLevel)
// from the sizes ReactFlow measured on a first, invisible render — never
// guessed from CSS. See archive/plans/flow-overview.md for the decisions.
//
// Three layouts, chosen by the page (`layout`):
//
//   * "horizontal" - every level runs left to right, Start to End, each
//     subflow a box in that line holding its own left-to-right line
//   * "balanced" (the page's default) - the steps of a level still run left
//     to right, but its Start stands above them at the top-left and its End
//     below at the bottom-right, so a subflow is a box entered at its top
//     and left at its bottom, and nesting grows the drawing downwards
//     instead of ever further to the right
//   * "vertical" - a level of subflows runs top to bottom, Start to End,
//     every subflow's box entered at its top and left at its bottom; a level
//     of forms runs left to right as on the horizontal layout. The whole is
//     a stack of wide boxes.
//   * "flows" - the balanced layout with every form subflow drawn closed: a
//     box naming what it holds ("4 forms") instead of its steps, which are
//     what take the room. Complex subflows stay open, so what is left is
//     the flow of flows. The tree is pruned first (closeFormSubflows), so
//     the layout itself knows nothing of this.

// Space between layers (x) and between nodes in a layer (y), and the padding
// a group keeps around the inner flow it contains
const LAYER_GAP = 72;
const NODE_GAP = 28;
const GROUP_PADDING = 20;

// The room one lane takes, beside a level's line of nodes (see ElbowEdge),
// and the room the balanced layout keeps between a Start or End and its
// row of steps
const LANE_GAP = 24;
const END_GAP = 40;

// How far an elbow edge runs straight out of a side handle before it turns
const EDGE_TURN = 24;

// A subflow expanded in place. ReactFlow draws the inner flow's nodes inside
// this one (they carry parentId), so this renders only the header; the body
// is the space the layout reserves for them. Before layout, the node's
// measured height is therefore exactly the header's — which is the offset
// the inner flow needs — and its measured width is the header's natural
// width, which the layout widens to fit the inner flow.
function SubflowGroupNode({ id, data, isConnectable }) {
  const { onOpenSubflow, flowTypeOptions } = useContext(EditorContext);

  const isFormSubflow = data.flow_label !== "subflows";
  const typeOptions = optionsForKind(flowTypeOptions, isFormSubflow ? "forms" : "subflows");
  const typeLabel =
    typeOptions.find((option) => option.value === data.flow_type)?.label ?? data.flow_type;

  // Entered at the left and left at the right, or, in a level the vertical
  // layout stacks top to bottom, entered at the top and left at the bottom
  const vertical = data.handles === "vertical";

  // A closed group (data.collapsed, on the flows layout) holds nothing and
  // says instead what it would hold
  const holds = data.collapsed ? describeContents(data.contents) : null;

  return (
    <div className={`ff-group ${data.collapsed ? "ff-group--collapsed" : ""}`}>
      <Handle
        type="target"
        position={vertical ? Position.Top : Position.Left}
        isConnectable={isConnectable}
      />
      <div className="ff-group__header">
        <div className="ff-group__title">
          <span aria-hidden="true">⧉</span>
          <span>{data.label}</span>
        </div>
        <div className="ff-group__meta">
          {isFormSubflow ? "Form subflow" : "Complex subflow"}
          {typeLabel ? ` · ${typeLabel}` : ""}
        </div>
        {isFormSubflow && <NodePerspectives ids={data.perspectives} />}
        {holds && <div className="ff-group__meta">{holds}</div>}
        {data.empty && <div className="ff-group__empty">No connected steps</div>}
        <button
          type="button"
          className="ff-node__open ff-group__open"
          onClick={(event) => {
            event.stopPropagation();
            onOpenSubflow?.(id);
          }}
        >
          Open →
        </button>
      </div>
      <Handle
        type="source"
        position={vertical ? Position.Bottom : Position.Right}
        isConnectable={isConnectable}
      />
    </div>
  );
}

// What a closed subflow holds, in words: "4 forms", "2 subflows · 8 forms",
// or "No connected steps" - counted through every level under it
function describeContents({ subflows, forms }) {
  const parts = [];

  if (subflows) parts.push(`${subflows} ${subflows === 1 ? "subflow" : "subflows"}`);
  if (forms) parts.push(`${forms} ${forms === 1 ? "form" : "forms"}`);

  return parts.length ? parts.join(" · ") : "No connected steps";
}

// "subflow", not "group", even though ReactFlow's word for a node holding
// others is a group: ReactFlow ships four node types of its own — input,
// default, output, and group — and its stylesheet reaches them by the
// `react-flow__node-<type>` class the wrapper puts on *every* node, custom
// ones included. A type named `group` therefore inherits that stylesheet's
// dark border, white background, 10px padding, and centred text, drawing a
// second box around the dashed one and (nodes being border-box) eating 22px
// out of the size the layout assigned. Only the CSS collides — nesting is
// driven by parentId, and the built-in `group` component renders nothing —
// so the fix is the name. It is also the better name: this is a subflow.
const overviewNodeTypes = { step: StepNode, subflow: SubflowGroupNode };

// An edge drawn as straight runs and right-angle turns, never a curve
// across whatever sits between its ends. ReactFlow paints edges *under*
// nodes, so a curve behind an expanded subflow would simply vanish.
//
// Which sides it leaves and enters come from the handles: a step's right
// and left, or a node's bottom and top where a layout has turned them. The
// layout says whether it takes a lane - `data.lane`: `{y}`, how far below
// the source's handle a lane across runs, negative for above; `{x}`, how
// far right of it a lane down runs, negative for left; null for none - and
// reserves the room for it (layoutLevel); the edge itself knows nothing of
// the nodes it passes. An edge that skips a layer - Application → Payment,
// past Review - is the case a lane exists for: out of the source, over to
// the lane, along, and back in to the target.
function ElbowEdge({
  id,
  sourceX,
  sourceY,
  targetX,
  targetY,
  sourcePosition,
  targetPosition,
  data,
  markerEnd,
  style,
}) {
  const lane = data?.lane ?? null;
  const fromBottom = sourcePosition === Position.Bottom;
  const intoTop = targetPosition === Position.Top;

  // The line each end's run turns on before a lane across: a side handle's
  // is one turn out, a top or bottom handle's its own
  const out = fromBottom ? sourceX : sourceX + EDGE_TURN;
  const into = intoTop ? targetX : targetX - EDGE_TURN;

  let points;

  if (lane?.x !== undefined) {
    // A lane down: out of the handle one turn, over to the lane, along it,
    // back over, and in
    const laneX = sourceX + lane.x;
    const outY = fromBottom ? sourceY + EDGE_TURN : sourceY;
    const intoY = intoTop ? targetY - EDGE_TURN : targetY;

    points = [
      [sourceX, sourceY],
      ...(fromBottom ? [[sourceX, outY]] : []),
      [laneX, outY],
      [laneX, intoY],
      ...(intoTop ? [[targetX, intoY]] : []),
      [targetX, targetY],
    ];
  } else if (lane === null) {
    if (fromBottom && intoTop) {
      const midY = (sourceY + targetY) / 2;
      points = [[sourceX, sourceY], [sourceX, midY], [targetX, midY], [targetX, targetY]];
    } else if (fromBottom) {
      points = [[sourceX, sourceY], [sourceX, targetY], [targetX, targetY]];
    } else if (intoTop) {
      points = [[sourceX, sourceY], [targetX, sourceY], [targetX, targetY]];
    } else {
      points = [[sourceX, sourceY], [out, sourceY], [out, targetY], [targetX, targetY]];
    }
  } else {
    const laneY = sourceY + lane.y;

    points = [
      [sourceX, sourceY],
      ...(fromBottom ? [] : [[out, sourceY]]),
      [out, laneY],
      [into, laneY],
      ...(intoTop ? [] : [[into, targetY]]),
      [targetX, targetY],
    ];
  }

  return <BaseEdge id={id} path={roundedPath(points, 10)} markerEnd={markerEnd} style={style} />;
}

// The SVG path through `points`, each corner rounded by `radius` - less
// where a run is too short for it. Repeated points are dropped, so a route
// whose runs collapse (a lane directly under its source, say) still draws.
function roundedPath(points, radius) {
  const route = points.filter(
    ([x, y], index) =>
      index === 0 || Math.abs(x - points[index - 1][0]) > 0.5 || Math.abs(y - points[index - 1][1]) > 0.5,
  );

  let path = `M ${route[0][0]} ${route[0][1]}`;

  for (let index = 1; index < route.length - 1; index++) {
    const [px, py] = route[index - 1];
    const [cx, cy] = route[index];
    const [nx, ny] = route[index + 1];
    const inLength = Math.hypot(cx - px, cy - py);
    const outLength = Math.hypot(nx - cx, ny - cy);
    const r = Math.min(radius, inLength / 2, outLength / 2);

    const inX = cx - ((cx - px) / inLength) * r;
    const inY = cy - ((cy - py) / inLength) * r;
    const outX = cx + ((nx - cx) / outLength) * r;
    const outY = cy + ((ny - cy) / outLength) * r;

    path += ` L ${inX} ${inY} Q ${cx} ${cy} ${outX} ${outY}`;
  }

  const [lastX, lastY] = route[route.length - 1];

  return `${path} L ${lastX} ${lastY}`;
}

const overviewEdgeTypes = { elbow: ElbowEdge };

// Nothing on the overview moves, connects, or selects
const READ_ONLY_NODE = { draggable: false, selectable: false, connectable: false, deletable: false };
const READ_ONLY_EDGE = { selectable: false, focusable: false, deletable: false };

// A stored node carries the *editing* canvas's layout state in its
// properties, and both halves of it are wrong here:
//
//   * `origin` is [0, 0.5] on every node the editor's add buttons made
//     (NODE_ORIGIN), which places a node by its left centre. This canvas
//     lays out top-left corners, so a node keeping that origin is drawn
//     half its height too high.
//   * `measured` is the size ReactFlow measured *there*. A subflow node is
//     a group header here, a different size entirely. Worse, ReactFlow
//     reads its "have all nodes been measured?" flag straight off the nodes
//     handed in (adoptUserNodes), so a stored `measured` makes
//     useNodesInitialized true before this canvas has measured anything and
//     the layout runs on the editor's numbers.
//
// Both are dropped, so the layout starts from what it can see (D6).
const WITHOUT_EDITOR_LAYOUT = { origin: [0, 0], measured: undefined };

// The tree with every form subflow closed: its inner flow cut out, and the
// node marked collapsed, with a count of what was cut. Complex subflows are
// kept open, their own trees closed the same way. Used by the flows layout,
// which lays out the pruned tree as the balanced layout would.
function closeFormSubflows(tree) {
  if (!tree) return tree;

  const subflows = {};
  const nodes = (tree.nodes ?? []).map((node) => {
    const subtree = tree.subflows?.[node.id];
    if (!subtree && node.type !== "subflow") return node;

    if (isSubflowsLevel(subtree ?? { nodes: [] })) {
      subflows[node.id] = closeFormSubflows(subtree);
      return node;
    }

    return { ...node, data: { ...node.data, collapsed: true, contents: countContents(subtree) } };
  });

  return { ...tree, nodes, subflows };
}

// How many subflows and forms a tree holds, every level down
function countContents(tree, counts = { subflows: 0, forms: 0 }) {
  for (const node of tree?.nodes ?? []) {
    if (node.type === "subflow" || node.id in (tree.subflows ?? {})) {
      counts.subflows += 1;
      countContents(tree.subflows?.[node.id], counts);
    } else if (node.data?.kind === "form") {
      counts.forms += 1;
    }
  }

  return counts;
}

// The tree as ReactFlow's flat lists, every node at the origin until the
// layout has sizes to work with. Parents precede their children, as
// ReactFlow requires of parentId nesting. Handles are turned to the
// vertical (StepNode, SubflowGroupNode) where the layout runs edges up and
// down: a Start's and an End's on the balanced layout, every node's in a
// level the vertical layout stacks.
function flattenTree(tree, layout, parentId = null, nodes = [], edges = []) {
  if (!tree) return { nodes, edges };

  const stacked = layout === "vertical" && isSubflowsLevel(tree);

  for (const node of tree.nodes ?? []) {
    const subflow = node.type === "subflow" || node.id in (tree.subflows ?? {});
    const subtree = tree.subflows?.[node.id];
    const end = node.data?.kind === "start" || node.data?.kind === "end";
    const vertical = stacked || (layout === "balanced" && end);

    const flat = {
      ...node,
      ...READ_ONLY_NODE,
      ...WITHOUT_EDITOR_LAYOUT,
      position: { x: 0, y: 0 },
      ...(parentId ? { parentId } : {}),
    };

    if (subflow) {
      flat.type = "subflow";
      flat.data = {
        ...node.data,
        flow_label: subtree?.flow?.label ?? node.data?.subflow_label ?? "forms",
        empty: !node.data?.collapsed && !subtree?.nodes?.length,
      };
    }

    if (vertical) flat.data = { ...flat.data, handles: "vertical" };

    nodes.push(flat);

    if (subflow && subtree) flattenTree(subtree, layout, node.id, nodes, edges);
  }

  for (const edge of tree.edges ?? []) {
    edges.push({ ...edge, ...READ_ONLY_EDGE });
  }

  return { nodes, edges };
}

// Lays out one level of the tree, bottom-up: a subflow node's size is the
// size of its inner flow laid out first, plus its header and padding.
// Positions are relative to the level's own top-left corner — for a child
// level that is what ReactFlow expects of a node with parentId. Writes
// every node's position into `positions`, every group's size into `sizes`,
// and, for every edge drawn as an elbow, its lane (or null for none) into
// `lanes` (see ElbowEdge); returns the level's own size.
function layoutLevel(tree, measured, positions, sizes, lanes, layout) {
  const nodes = tree.nodes ?? [];
  if (nodes.length === 0) return { width: 0, height: 0 };

  const size = new Map();

  for (const node of nodes) {
    const header = measured.get(node.id) ?? { width: 180, height: 40 };
    const subtree = tree.subflows?.[node.id];
    const subflow = node.type === "subflow" || node.id in (tree.subflows ?? {});

    if (!subflow) {
      size.set(node.id, header);
      continue;
    }

    const inner = layoutLevel(subtree ?? { nodes: [] }, measured, positions, sizes, lanes, layout);
    const body = inner.width > 0 ? inner.height + GROUP_PADDING : 0;
    const group = {
      width: Math.max(header.width, inner.width + 2 * GROUP_PADDING),
      height: header.height + body,
    };

    // The inner flow sits under the header, inset by the padding
    for (const child of subtree?.nodes ?? []) {
      const at = positions.get(child.id);
      positions.set(child.id, { x: at.x + GROUP_PADDING, y: at.y + header.height });
    }

    size.set(node.id, group);
    sizes.set(node.id, group);
  }

  if (layout === "balanced") return placeBalanced(tree, size, positions, lanes);
  if (layout === "vertical" && isSubflowsLevel(tree)) return placeVertical(tree, size, positions, lanes);

  return placeHorizontal(tree, size, positions, lanes);
}

// Whether a level holds subflows rather than forms - by the flow's label,
// or, without one, by what its nodes are
function isSubflowsLevel(tree) {
  if (tree.flow?.label) return tree.flow.label === "subflows";

  return (tree.nodes ?? []).some(
    (node) => node.type === "subflow" || node.id in (tree.subflows ?? {}),
  );
}

// The horizontal layout of one level: every node in a layer, layers left to
// right from Start to End.
function placeHorizontal(tree, size, positions, lanes) {
  const layers = layerNodes(tree);
  const { layerHeights, height } = measureLayers(layers, size);

  // Edges that do not step to the very next layer — a skip forwards, a loop
  // back, a same-layer link — detour through lanes above the level. The
  // shortest span takes the lane nearest the nodes, so lanes nest rather
  // than cross. The band of lanes pushes the level's nodes down.
  const layerOf = new Map();
  layers.forEach((ids, index) => ids.forEach((id) => layerOf.set(id, index)));

  const detours = laneEdges(tree.edges, layerOf);
  const band = detours.length * LANE_GAP;

  const row = placeRow(layers, size, positions, 0, band, layerHeights, height);

  detours.forEach((edge, lane) => {
    const laneY = band - (lane + 0.5) * LANE_GAP;
    lanes.set(edge.id, { y: laneY - sideHandleY(edge.source, size, positions) });
  });

  return { width: row.right, height: height + band };
}

// The vertical layout of a level of subflows: every node in a layer, layers
// top to bottom from Start to End, each centred on the widest. Edges that
// skip a layer take lanes to the left of the stack, as the horizontal
// layout's take lanes above its row.
function placeVertical(tree, size, positions, lanes) {
  const layers = layerNodes(tree);
  const layerWidths = layers.map(
    (layer) => layer.reduce((sum, id) => sum + size.get(id).width, 0) + (layer.length - 1) * NODE_GAP,
  );
  const width = Math.max(...layerWidths);

  const layerOf = new Map();
  layers.forEach((ids, index) => ids.forEach((id) => layerOf.set(id, index)));

  const detours = laneEdges(tree.edges, layerOf);
  const band = detours.length * LANE_GAP;

  let y = 0;
  layers.forEach((layer, index) => {
    let x = band + (width - layerWidths[index]) / 2;

    for (const id of layer) {
      positions.set(id, { x, y });
      x += size.get(id).width + NODE_GAP;
    }

    y += Math.max(...layer.map((id) => size.get(id).height)) + LAYER_GAP;
  });

  detours.forEach((edge, lane) => {
    const laneX = band - (lane + 0.5) * LANE_GAP;
    const source = positions.get(edge.source);
    lanes.set(edge.id, { x: laneX - (source.x + size.get(edge.source).width / 2) });
  });

  return { width: width + band, height: y - LAYER_GAP };
}

// The balanced layout of one level: its steps in a row as the horizontal
// layout would place them, but its Start above that row at the top-left
// and its End below it at the bottom-right. A Start's edge drops straight
// down and turns into the row's first layer; the last layer's edges run
// right and turn down into End. Edges to a later layer, or into End from an
// earlier one, take lanes - above the row for the former, below for the
// latter - as the horizontal layout's detours do.
function placeBalanced(tree, size, positions, lanes) {
  const nodes = tree.nodes ?? [];
  const edges = tree.edges ?? [];
  const kindOf = new Map(nodes.map((node) => [node.id, node.data?.kind]));
  const starts = nodes.filter((node) => kindOf.get(node.id) === "start").map((node) => node.id);
  const ends = nodes.filter((node) => kindOf.get(node.id) === "end").map((node) => node.id);
  const steps = nodes.filter((node) => !starts.includes(node.id) && !ends.includes(node.id));

  const isStart = (id) => kindOf.get(id) === "start";
  const isEnd = (id) => kindOf.get(id) === "end";

  // A Start's handle is its bottom centre, a step's its right centre
  const handleY = (id) =>
    isStart(id)
      ? positions.get(id).y + size.get(id).height
      : sideHandleY(id, size, positions);

  // Start, top-left. Several Starts (not something the editor makes) sit
  // side by side.
  const startRow = placeSideBySide(starts, size, positions, 0, 0);

  // The row begins one turn to the right of the first Start's centre line,
  // so its edge drops straight down and turns into the first layer
  const rowX = starts.length
    ? positions.get(starts[0]).x + size.get(starts[0]).width / 2 + EDGE_TURN
    : 0;
  const rowTop = starts.length ? startRow.height + END_GAP : 0;

  // Nothing between Start and End: End straight under Start
  if (steps.length === 0) {
    const endRow = placeSideBySide(ends, size, positions, 0, rowTop);

    edges
      .filter((edge) => isStart(edge.source) && isEnd(edge.target))
      .forEach((edge) => lanes.set(edge.id, null));

    return {
      width: Math.max(startRow.width, endRow.width),
      height: rowTop + endRow.height,
    };
  }

  // The steps are layered from the ones Start leads to; Start itself
  // stands before every layer and End after, for the span an edge covers
  const roots = edges
    .filter((edge) => isStart(edge.source) && kindOf.has(edge.target) && !isEnd(edge.target))
    .map((edge) => edge.target)
    .filter((id, index, all) => all.indexOf(id) === index);

  const layers = layerNodes({ nodes: steps, edges }, roots);
  const { layerHeights, height } = measureLayers(layers, size);

  const layerOf = new Map();
  starts.forEach((id) => layerOf.set(id, -1));
  ends.forEach((id) => layerOf.set(id, layers.length));
  layers.forEach((ids, index) => ids.forEach((id) => layerOf.set(id, index)));

  const above = laneEdges(edges, layerOf, (edge) => !isEnd(edge.target));
  const below = laneEdges(edges, layerOf, (edge) => isEnd(edge.target));

  const top = rowTop + above.length * LANE_GAP;
  const row = placeRow(layers, size, positions, rowX, top, layerHeights, height);
  const bottom = top + height;

  // End, bottom-right: its centre line one turn past the row's right edge,
  // so the last layer's edges run right and turn down into it
  const endTop = bottom + below.length * LANE_GAP + (ends.length ? END_GAP : 0);
  const endX = ends.length ? row.right + EDGE_TURN - size.get(ends[0]).width / 2 : 0;
  const endRow = placeSideBySide(ends, size, positions, endX, endTop);

  above.forEach((edge, lane) => {
    const laneY = top - (lane + 0.5) * LANE_GAP;
    lanes.set(edge.id, { y: laneY - handleY(edge.source) });
  });

  below.forEach((edge, lane) => {
    const laneY = bottom + (lane + 0.5) * LANE_GAP;
    lanes.set(edge.id, { y: laneY - handleY(edge.source) });
  });

  // Every other edge out of a Start or into an End is an elbow too, with no
  // lane: down and into the first layer, or right and down into End
  edges
    .filter((edge) => layerOf.has(edge.source) && layerOf.has(edge.target))
    .filter((edge) => isStart(edge.source) || isEnd(edge.target))
    .forEach((edge) => lanes.has(edge.id) || lanes.set(edge.id, null));

  return {
    width: Math.max(startRow.width, row.right, endX + endRow.width),
    height: endTop + endRow.height,
  };
}

// The edges of a level that need a lane: those between layered nodes that do
// not step to the very next layer, among the ones `keep` admits. Ordered
// shortest span first, so the lane nearest the nodes goes to the edge that
// covers the least and lanes nest rather than cross.
function laneEdges(edges, layerOf, keep = () => true) {
  const span = (edge) => layerOf.get(edge.target) - layerOf.get(edge.source);

  return (edges ?? [])
    .filter((edge) => layerOf.has(edge.source) && layerOf.has(edge.target))
    .filter((edge) => span(edge) !== 1)
    .filter(keep)
    .sort((a, b) => Math.abs(span(a)) - Math.abs(span(b)));
}

// Each layer's height with its nodes stacked, and the tallest of them
function measureLayers(layers, size) {
  const layerHeights = layers.map(
    (layer) => layer.reduce((sum, id) => sum + size.get(id).height, 0) + (layer.length - 1) * NODE_GAP,
  );

  return { layerHeights, height: Math.max(...layerHeights) };
}

// Places the layers left to right from (x, top), each centred on the
// tallest so a straight Start → End line stays straight; returns the row's
// right edge.
function placeRow(layers, size, positions, x, top, layerHeights, height) {
  layers.forEach((layer, index) => {
    let y = top + (height - layerHeights[index]) / 2;

    for (const id of layer) {
      positions.set(id, { x, y });
      y += size.get(id).height + NODE_GAP;
    }

    x += Math.max(...layer.map((id) => size.get(id).width)) + LAYER_GAP;
  });

  return { right: x - LAYER_GAP };
}

// Places `ids` in one line from (x, y), a node gap apart; returns the
// line's size
function placeSideBySide(ids, size, positions, x, y) {
  let right = x;
  let height = 0;

  for (const id of ids) {
    positions.set(id, { x: right, y });
    right += size.get(id).width + NODE_GAP;
    height = Math.max(height, size.get(id).height);
  }

  return { width: ids.length ? right - NODE_GAP - x : 0, height };
}

// A node's right-hand handle, vertically: its centre
function sideHandleY(id, size, positions) {
  return positions.get(id).y + size.get(id).height / 2;
}

// Longest-path layering from the level's Start nodes, left to right. A DFS
// first marks back edges (an edge to a node still on the DFS stack), so a
// loop in a flow is drawn but does not push its target rightwards forever.
// Within a layer, nodes are ordered by the mean position of their
// predecessors in the layer before — one barycenter pass, which keeps most
// edges from crossing. Ties keep the stored order.
//
// The first layer is the Start nodes, or `roots` when the caller has taken
// them out of the level (the balanced layout, which lays out the steps alone
// and passes the ones Start leads to).
function layerNodes(tree, roots = []) {
  const nodes = tree.nodes ?? [];
  const order = new Map(nodes.map((node, index) => [node.id, index]));
  const outgoing = new Map(nodes.map((node) => [node.id, []]));

  for (const edge of tree.edges ?? []) {
    if (outgoing.has(edge.source) && order.has(edge.target)) {
      outgoing.get(edge.source).push(edge.target);
    }
  }

  const starts = nodes.filter((node) => node.data?.kind === "start").map((node) => node.id);
  // Should not happen — the server sends connected nodes, which means a
  // Start exists — but a level without one still needs a first layer
  const first = roots.length ? roots : starts.length ? starts : nodes.slice(0, 1).map((node) => node.id);

  // Back edges, by DFS
  const back = new Set();
  const state = new Map(); // "open" while on the stack, "done" after

  const visit = (id) => {
    state.set(id, "open");

    for (const target of outgoing.get(id)) {
      const seen = state.get(target);

      if (seen === "open") back.add(`${id}→${target}`);
      else if (!seen) visit(target);
    }

    state.set(id, "done");
  };

  first.forEach((id) => state.get(id) || visit(id));
  // Nodes the roots never reached (only possible without a Start): treat
  // each as another root so every node gets a layer
  nodes.forEach((node) => state.get(node.id) || visit(node.id));

  // Longest path over the forward edges, in topological order
  const forward = new Map(
    nodes.map((node) => [
      node.id,
      outgoing.get(node.id).filter((target) => !back.has(`${node.id}→${target}`)),
    ]),
  );
  const incoming = new Map(nodes.map((node) => [node.id, 0]));
  forward.forEach((targets) => targets.forEach((target) => incoming.set(target, incoming.get(target) + 1)));

  const layer = new Map(nodes.map((node) => [node.id, 0]));
  const queue = nodes.filter((node) => incoming.get(node.id) === 0).map((node) => node.id);

  while (queue.length) {
    const id = queue.shift();

    for (const target of forward.get(id)) {
      layer.set(target, Math.max(layer.get(target), layer.get(id) + 1));
      incoming.set(target, incoming.get(target) - 1);

      if (incoming.get(target) === 0) queue.push(target);
    }
  }

  const depth = Math.max(...layer.values()) + 1;
  const layers = Array.from({ length: depth }, () => []);
  nodes.forEach((node) => layers[layer.get(node.id)].push(node.id));

  // Barycenter ordering, left to right
  const predecessors = new Map(nodes.map((node) => [node.id, []]));
  forward.forEach((targets, source) => targets.forEach((target) => predecessors.get(target).push(source)));

  const rank = new Map();
  layers.forEach((ids) => {
    const key = (id) => {
      const above = predecessors.get(id).filter((source) => rank.has(source));
      if (!above.length) return order.get(id);
      return above.reduce((sum, source) => sum + rank.get(source), 0) / above.length;
    };

    ids.sort((a, b) => key(a) - key(b) || order.get(a) - order.get(b));
    ids.forEach((id, index) => rank.set(id, index));
  });

  return layers;
}

function FlowOverview({
  tree,
  layout = "balanced",
  flowTypeOptions = [],
  formTypeOptions = [],
  perspectiveOptions = [],
  onOpenSubflow,
  onOpenForm,
}) {
  // The flows layout is the balanced one over a pruned tree: every form
  // subflow closed
  const placement = layout === "flows" ? "balanced" : layout;
  const shown = useMemo(() => (layout === "flows" ? closeFormSubflows(tree) : tree), [tree, layout]);

  // Same combined state as the editor, for the same reason: dimension
  // changes arrive per node through onNodesChange, and the layout needs
  // them all at once
  const [state, setState] = useState(() => flattenTree(shown, placement));

  // "measured": every node has a size from ReactFlow; "placed": positions
  // and group sizes are set; "fitted": the viewport shows all of it. Nothing
  // is visible until then, so no frame shows the nodes piled at the origin.
  const [phase, setPhase] = useState("measuring");
  const measured = useNodesInitialized();
  const { fitView } = useReactFlow();

  // useNodesInitialized answers for ReactFlow's store, which can still hold
  // the sizes of the *last* tree when a new one with the same ids has just
  // been handed in. The layout reads sizes off the nodes here, so it waits
  // until every one of them has been measured since flattenTree dropped them.
  const sized = state.nodes.every((node) => node.measured?.width && node.measured?.height);

  useEffect(() => {
    setState(flattenTree(shown, placement));
    setPhase("measuring");
  }, [shown, placement]);

  const onNodesChange = useCallback(
    (changes) =>
      setState((current) => ({ ...current, nodes: applyNodeChanges(changes, current.nodes) })),
    [],
  );

  useEffect(() => {
    if (phase !== "measuring") return;

    // useNodesInitialized is false for an empty canvas; there is nothing to
    // place, so go straight to showing it
    if (state.nodes.length === 0) {
      setPhase("fitted");
      return;
    }

    if (!measured || !sized) return;

    setState((current) => {
      const sizesByNode = new Map(current.nodes.map((node) => [node.id, node.measured]));
      const positions = new Map();
      const groupSizes = new Map();
      const lanes = new Map();

      layoutLevel(shown, sizesByNode, positions, groupSizes, lanes, placement);

      return {
        nodes: current.nodes.map((node) => ({
          ...node,
          position: positions.get(node.id) ?? node.position,
          ...(groupSizes.has(node.id) ? { style: groupSizes.get(node.id) } : {}),
        })),
        edges: current.edges.map((edge) =>
          lanes.has(edge.id)
            ? { ...edge, type: "elbow", data: { ...edge.data, lane: lanes.get(edge.id) } }
            : edge,
        ),
      };
    });

    setPhase("placed");
  }, [phase, measured, sized, state.nodes.length, shown, placement]);

  // Fit once the groups have been re-measured at the sizes the layout gave
  // them — fitting earlier would frame the header-sized groups
  useEffect(() => {
    if (phase !== "placed") return;

    const resized = state.nodes.every(
      (node) => !node.style?.width || Math.abs((node.measured?.width ?? 0) - node.style.width) < 1,
    );

    if (!resized) return;

    fitView({ padding: 0.1 });
    setPhase("fitted");
  }, [phase, state.nodes, fitView]);

  return (
    <EditorContext.Provider
      value={{
        onOpenSubflow,
        onOpenForm,
        onNodeDataChange: null,
        editable: false,
        flowTypeOptions,
        formTypeOptions,
        perspectiveOptions,
        focusId: null,
        clearFocus: null,
      }}
    >
      <div
        className="ff-overview"
        style={{ width: "100%", height: "100%", visibility: phase === "fitted" ? "visible" : "hidden" }}
      >
        <ReactFlow
          nodes={state.nodes}
          edges={state.edges}
          nodeTypes={overviewNodeTypes}
          edgeTypes={overviewEdgeTypes}
          onNodesChange={onNodesChange}
          nodesDraggable={false}
          nodesConnectable={false}
          elementsSelectable={false}
          edgesReconnectable={false}
          deleteKeyCode={null}
          minZoom={0.1}
          proOptions={{ hideAttribution: false }}
        >
          <Background variant="dots" gap={16} size={1} />
          <Controls showInteractive={false} />
          <MiniMap pannable zoomable />
          {state.nodes.length === 0 && (
            <Panel position="top-center" className="ff-panel">
              <span className="ff-panel__note">Nothing is connected to Start yet.</span>
            </Panel>
          )}
        </ReactFlow>
      </div>
    </EditorContext.Provider>
  );
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
 * `flowTypeOptions` ([{label, value, kind}]) are the flow_type choices a
 * subflow node offers - those whose kind ("forms" or "subflows") is the
 * kind of flow the node embeds: a dropdown when editable, the stored value's
 * label when not. The chosen value lives in the node's data and rides the
 * ordinary onChange round-trip. `formTypeOptions` are the same for a form
 * step's form_type. `perspectiveOptions` ([{label, value}]) name the
 * perspectives a form subflow node's data.perspectives ids refer to — shown
 * read-only under the type, since they are set on the subflow's own page.
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
          flowTypeOptions={opts.flowTypeOptions}
          formTypeOptions={opts.formTypeOptions}
          perspectiveOptions={opts.perspectiveOptions}
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

/**
 * Renders the overview into `el`: the whole flow, every level at once,
 * read-only. `opts.tree` is FormFlow.Web.Helpers.ReactFlow.to_tree_data/1's
 * shape. `opts.layout` is "horizontal", "balanced" (the default),
 * "vertical", or "flows" - see the overview section above for what each
 * draws. The option lists and the two open callbacks mean what they mean for
 * mount/2; there is no onChange, since nothing here can change. Nor is
 * there a setter for the tree: the page never edits, so the only tree it
 * ever draws is the one it mounted with, and a fresh one arrives as a fresh
 * page.
 *
 * Returns a handle with `unmount/0`.
 */
export function mountOverview(el, opts = {}) {
  const root = createRoot(el);

  root.render(
    <ReactFlowProvider>
      <FlowOverview
        tree={opts.tree}
        layout={opts.layout}
        flowTypeOptions={opts.flowTypeOptions}
        formTypeOptions={opts.formTypeOptions}
        perspectiveOptions={opts.perspectiveOptions}
        onOpenSubflow={opts.onOpenSubflow}
        onOpenForm={opts.onOpenForm}
      />
    </ReactFlowProvider>,
  );

  roots.set(el, root);

  return { unmount: () => unmount(el) };
}

export function unmount(el) {
  roots.get(el)?.unmount();
  roots.delete(el);
}
