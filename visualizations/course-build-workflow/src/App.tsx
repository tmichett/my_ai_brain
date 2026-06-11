import { useState } from "react";
import {
  FLOW_NODES,
  FLOW_EDGES,
  PHASES,
  LANE_LABELS,
  type Lane,
} from "./workflow-data";
import { computeDAGLayout } from "./dag-layout";
import "./styles.css";

function WorkflowDiagram() {
  const nodeMap = new Map(FLOW_NODES.map((n) => [n.id, n]));
  const layout = computeDAGLayout({
    nodes: FLOW_NODES.map(({ id }) => ({ id })),
    edges: FLOW_EDGES,
    direction: "horizontal",
    nodeWidth: 168,
    nodeHeight: 72,
    rankGap: 56,
    nodeGap: 20,
    padding: 28,
  });

  return (
    <div className="diagram-scroll">
      <div className="diagram-canvas" style={{ width: layout.width, height: layout.height + 36 }}>
        <svg width={layout.width} height={layout.height} className="diagram-edges" style={{ top: 36 }}>
          <defs>
            <marker id="arrow" markerWidth="8" markerHeight="6" refX="8" refY="3" orient="auto">
              <polygon points="0 0, 8 3, 0 6" className="arrow-head" />
            </marker>
          </defs>
          {layout.edges.map((e, i) => (
            <path
              key={i}
              d={`M ${e.sourceX} ${e.sourceY} C ${(e.sourceX + e.targetX) / 2} ${e.sourceY}, ${(e.sourceX + e.targetX) / 2} ${e.targetY}, ${e.targetX} ${e.targetY}`}
              className="edge"
              markerEnd="url(#arrow)"
            />
          ))}
        </svg>
        {layout.ranks.map((rank) => {
          const phase = PHASES.find((p) => p.n === rank.rank + 1);
          if (!phase) return null;
          return (
            <div key={rank.rank} className="phase-label" style={{ left: rank.x - 8, width: rank.width + 16 }}>
              <div className="phase-title">{phase.title}</div>
              <div className="phase-sub">{phase.subtitle}</div>
            </div>
          );
        })}
        {layout.nodes.map((n) => {
          const data = nodeMap.get(n.id)!;
          return (
            <div
              key={n.id}
              className={`node lane-${data.lane}${n.id === "done" ? " node-terminal" : ""}`}
              style={{ left: n.x, top: n.y + 36, width: 168, height: 72 }}
              title={data.detail}
            >
              <div className="node-label">{data.label}</div>
              <div className="node-detail">{data.detail}</div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function InventoryTree() {
  const lines = [
    [0, "classroom/ansible-playbooks-novello/"],
    [1, "inventory.yml · inventory.laptop"],
    [1, "[SSL_VMs] [lab_VMs] [workstation] …"],
    [1, "group_vars/all/course.yml · certificates.yml"],
    [1, "host_vars/{host}/ · files/ssl/ · site.yml"],
    [0, "collections/requirements.yml (repo root)"],
  ];
  return (
    <pre className="mono-tree">
      {lines.map(([indent, text], i) => (
        <div key={i} style={{ paddingLeft: Number(indent) * 16 }}>
          {Number(indent) > 0 ? "└ " : ""}
          {text}
        </div>
      ))}
    </pre>
  );
}

export default function App() {
  const [detailsOpen, setDetailsOpen] = useState(false);

  return (
    <div className="page">
      <header>
        <h1>Course build workflow</h1>
        <p>
          End-to-end path from a new Red Hat Training course through dle-doit inventory scaffolding,
          GitHub commit, and Ansible Automation Controller provisioning inside an Execution Environment.
        </p>
        <div className="pills">
          {(Object.keys(LANE_LABELS) as Lane[]).map((lane) => (
            <span key={lane} className={`pill lane-${lane}`}>{LANE_LABELS[lane]}</span>
          ))}
        </div>
      </header>

      <section className="card">
        <h2>Start → finish flow</h2>
        <WorkflowDiagram />
        <div className="legend">
          {(Object.keys(LANE_LABELS) as Lane[]).map((lane) => (
            <span key={lane} className="legend-item">
              <span className={`swatch lane-${lane}`} />
              {LANE_LABELS[lane]}
            </span>
          ))}
        </div>
      </section>

      <div className="grid-2">
        <section className="card">
          <h2>Ansible inventory layout</h2>
          <InventoryTree />
        </section>
        <section className="card">
          <h2>dle-doit commands</h2>
          <table>
            <thead>
              <tr><th>Command</th><th>When</th></tr>
            </thead>
            <tbody>
              <tr><td>create_inventory --profile</td><td>New course scaffold</td></tr>
              <tr><td>validate_inventory</td><td>Before build</td></tr>
              <tr><td>get_ssl_certs</td><td>Before AWX (IdM SSL)</td></tr>
              <tr><td>dle-doit</td><td>Heat template generation</td></tr>
            </tbody>
          </table>
        </section>
      </div>

      <section className="card callout">
        <strong>IdM SSL on AWX:</strong> use <code>inventory_dir</code> for PEM paths — not <code>playbook_dir</code>.
        Commit <code>files/ssl/</code> to git for project sync.
      </section>

      <button type="button" className="toggle" onClick={() => setDetailsOpen(!detailsOpen)}>
        {detailsOpen ? "Hide" : "Show"} Automation Controller details
      </button>
      {detailsOpen && (
        <section className="card">
          <p>
            Production builds always run on AAP — not local ansible-playbook. GitHub project sync lands files
            at /runner/project/. Collections install to /runner/requirements_collections/ inside the EE.
          </p>
        </section>
      )}
    </div>
  );
}
