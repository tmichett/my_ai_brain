import {
  Stack,
  Row,
  Grid,
  Card,
  CardBody,
  CardHeader,
  H1,
  Text,
  Pill,
  Stat,
  Table,
  Callout,
  CollapsibleSection,
  computeDAGLayout,
  useHostTheme,
} from "cursor/canvas";

type FlowNode = {
  id: string;
  label: string;
  detail: string;
  lane: "dev" | "repo" | "doit" | "aap" | "lab";
  phase: number;
};

const FLOW_NODES: FlowNode[] = [
  { id: "start", label: "New course repo", detail: "RedHatTraining/{SKU} on GitHub", lane: "repo", phase: 1 },
  { id: "create-inv", label: "create_inventory", detail: "Profile: rhel-basic · aap-snap · aap-mesh · ocp · full", lane: "doit", phase: 1 },
  { id: "scaffold", label: "Inventory scaffold", detail: "inventory · group_vars · host_vars · site.yml · course.yml", lane: "repo", phase: 1 },
  { id: "configure", label: "Configure course", detail: "course.yml · host groups · SSL_VMs · changeme images", lane: "dev", phase: 2 },
  { id: "validate", label: "validate_inventory", detail: "Schema check against profiles.yml", lane: "doit", phase: 2 },
  { id: "ssl", label: "get_ssl_certs", detail: "DLE-Web SSL Lab API → files/ssl/*.pem", lane: "doit", phase: 2 },
  { id: "heat", label: "dle-doit pipeline", detail: "Parse inventory → Heat templates (builder/dev/prod)", lane: "doit", phase: 3 },
  { id: "commit", label: "git commit & push", detail: "PEMs · playbooks · collections/requirements.yml", lane: "repo", phase: 3 },
  { id: "project-sync", label: "AAP Project sync", detail: "GitHub SCM → /runner/project/ + galaxy collections", lane: "aap", phase: 4 },
  { id: "ee", label: "Execution Environment", detail: "Job template · credentials · inventory · EE container", lane: "aap", phase: 4 },
  { id: "site", label: "site.yml", detail: "classroom/ansible-playbooks-novello/site.yml", lane: "aap", phase: 5 },
  { id: "components", label: "dle.components", detail: "wait · timezone · features · IdM SSL playbooks", lane: "lab", phase: 5 },
  { id: "course-plays", label: "Course playbooks", detail: "100_upgrade · VS Code · network_profiles · clean", lane: "lab", phase: 5 },
  { id: "aap-install", label: "AAP install (optional)", detail: "download_aap_bundle · install_aap2.6 · custom_ca_cert", lane: "lab", phase: 6 },
  { id: "done", label: "Classroom ready", detail: "Lab VMs with TLS · features · course content", lane: "lab", phase: 6 },
];

const FLOW_EDGES = [
  { from: "start", to: "create-inv" },
  { from: "create-inv", to: "scaffold" },
  { from: "scaffold", to: "configure" },
  { from: "configure", to: "validate" },
  { from: "configure", to: "ssl" },
  { from: "validate", to: "heat" },
  { from: "ssl", to: "commit" },
  { from: "heat", to: "commit" },
  { from: "commit", to: "project-sync" },
  { from: "project-sync", to: "ee" },
  { from: "ee", to: "site" },
  { from: "site", to: "components" },
  { from: "components", to: "course-plays" },
  { from: "course-plays", to: "aap-install" },
  { from: "aap-install", to: "done" },
];

const PHASES = [
  { n: 1, title: "Scaffold", subtitle: "dle-doit create_inventory" },
  { n: 2, title: "Configure", subtitle: "Inventory + IdM SSL PEMs" },
  { n: 3, title: "Artifacts", subtitle: "Heat + git push" },
  { n: 4, title: "Controller", subtitle: "GitHub project + EE" },
  { n: 5, title: "Provision", subtitle: "site.yml playbooks" },
  { n: 6, title: "Complete", subtitle: "Lab classroom live" },
];

function laneLabel(lane: FlowNode["lane"]): string {
  switch (lane) {
    case "dev": return "Developer";
    case "repo": return "Course repo";
    case "doit": return "dle-doit";
    case "aap": return "Automation Controller";
    case "lab": return "Lab targets";
  }
}

function WorkflowDiagram() {
  const theme = useHostTheme();
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

  const laneFill: Record<FlowNode["lane"], string> = {
    dev: theme.fill.secondary,
    repo: theme.fill.tertiary,
    doit: theme.fill.quaternary,
    aap: theme.accent.control,
    lab: theme.fill.secondary,
  };

  return (
    <div style={{ overflowX: "auto", paddingBottom: 8 }}>
      <div style={{ position: "relative", width: layout.width, height: layout.height + 36, minWidth: layout.width }}>
        <svg width={layout.width} height={layout.height} style={{ position: "absolute", top: 36, left: 0 }}>
          <defs>
            <marker id="flow-arrow" markerWidth="8" markerHeight="6" refX="8" refY="3" orient="auto">
              <polygon points="0 0, 8 3, 0 6" fill={theme.stroke.secondary} />
            </marker>
          </defs>
          {layout.edges.map((e, i) => (
            <path
              key={i}
              d={`M ${e.sourceX} ${e.sourceY} C ${(e.sourceX + e.targetX) / 2} ${e.sourceY}, ${(e.sourceX + e.targetX) / 2} ${e.targetY}, ${e.targetX} ${e.targetY}`}
              fill="none"
              stroke={theme.stroke.secondary}
              strokeWidth={1.5}
              markerEnd="url(#flow-arrow)"
            />
          ))}
        </svg>
        {layout.ranks.map((rank) => {
          const phase = PHASES.find((p) => p.n === rank.rank + 1);
          if (!phase) return null;
          return (
            <div key={rank.rank} style={{ position: "absolute", left: rank.x - 8, top: 0, width: rank.width + 16, textAlign: "center" }}>
              <Text size="small" weight="medium" tone="secondary">{phase.title}</Text>
              <Text size="small" tone="tertiary">{phase.subtitle}</Text>
            </div>
          );
        })}
        {layout.nodes.map((n) => {
          const data = nodeMap.get(n.id)!;
          const isTerminal = n.id === "done";
          return (
            <div
              key={n.id}
              title={data.detail}
              style={{
                position: "absolute", left: n.x, top: n.y + 36, width: 168, height: 72,
                display: "flex", flexDirection: "column", justifyContent: "center", gap: 4,
                padding: "8px 10px", borderRadius: 6,
                background: isTerminal ? theme.accent.primary : laneFill[data.lane],
                color: isTerminal ? theme.text.onAccent : theme.text.primary,
                border: `1px solid ${isTerminal ? theme.accent.primary : theme.stroke.tertiary}`,
                boxSizing: "border-box",
              }}
            >
              <Text size="small" weight="medium" style={{ lineHeight: 1.25, color: "inherit" }}>{data.label}</Text>
              <Text size="small" style={{ lineHeight: 1.2, color: isTerminal ? theme.text.onAccent : theme.text.secondary, opacity: 0.9 }}>{data.detail}</Text>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function InventoryTree() {
  const theme = useHostTheme();
  const lines = [
    { indent: 0, text: "classroom/ansible-playbooks-novello/", tone: "primary" as const },
    { indent: 1, text: "inventory.yml · inventory.laptop", tone: "secondary" as const },
    { indent: 1, text: "[SSL_VMs] [lab_VMs] [workstation] …", tone: "secondary" as const },
    { indent: 1, text: "group_vars/all/", tone: "secondary" as const },
    { indent: 2, text: "course.yml — SKU, rhelver, profiles", tone: "tertiary" as const },
    { indent: 2, text: "certificates.yml — ca_cert_file", tone: "tertiary" as const },
    { indent: 1, text: "host_vars/{host}/ — image, flavor, networks", tone: "secondary" as const },
    { indent: 1, text: "files/ssl/ — lab-ipa-ca.pem, {fqdn}.crt/.key", tone: "secondary" as const },
    { indent: 1, text: "site.yml — imports dle.components + course plays", tone: "secondary" as const },
    { indent: 0, text: "collections/requirements.yml (repo root)", tone: "primary" as const },
    { indent: 1, text: "dle.components (+ git branch if pre-Hub)", tone: "tertiary" as const },
  ];
  return (
    <Stack gap={4}>
      {lines.map((line, i) => (
        <div key={i}>
          <Text size="small" style={{
            paddingLeft: line.indent * 16,
            fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace",
            color: line.tone === "primary" ? theme.text.primary : line.tone === "secondary" ? theme.text.secondary : theme.text.tertiary,
          }}>
            {line.indent > 0 ? "└ " : ""}{line.text}
          </Text>
        </div>
      ))}
    </Stack>
  );
}

export default function CourseBuildWorkflow() {
  const theme = useHostTheme();
  return (
    <Stack gap={24} style={{ maxWidth: 1200, margin: "0 auto", padding: "8px 4px 32px" }}>
      <Stack gap={8}>
        <H1>Course build workflow</H1>
        <Text style={{ color: theme.text.secondary, maxWidth: 720 }}>
          End-to-end path from a new Red Hat Training course through dle-doit inventory scaffolding,
          GitHub commit, and Ansible Automation Controller provisioning inside an Execution Environment.
        </Text>
        <Row gap={8} wrap>
          <Pill tone="neutral">Developer workstation</Pill>
          <Pill tone="info">Course GitHub repo</Pill>
          <Pill tone="warning">dle-doit CLI</Pill>
          <Pill tone="success">Automation Controller + EE</Pill>
          <Pill tone="info">Lab VMs</Pill>
        </Row>
      </Stack>
      <Card>
        <CardHeader trailing={<Text size="small" tone="tertiary">6 phases</Text>}>Start → finish flow</CardHeader>
        <CardBody>
          <WorkflowDiagram />
          <div style={{ height: 16 }} />
          <Row gap={16} wrap>
            {(["dev", "repo", "doit", "aap", "lab"] as const).map((lane) => (
              <div key={lane} style={{ display: "flex", alignItems: "center", gap: 6 }}>
                <div style={{ width: 10, height: 10, borderRadius: 2, background: lane === "aap" ? theme.accent.control : lane === "doit" ? theme.fill.quaternary : theme.fill.secondary, border: `1px solid ${theme.stroke.tertiary}` }} />
                <Text size="small">{laneLabel(lane)}</Text>
              </div>
            ))}
          </Row>
        </CardBody>
      </Card>
      <Grid columns={2} gap={16}>
        <Card>
          <CardHeader>Ansible inventory layout</CardHeader>
          <CardBody><InventoryTree /></CardBody>
        </Card>
        <Card>
          <CardHeader>dle-doit commands</CardHeader>
          <CardBody>
            <Table headers={["Command", "When", "Output"]} rows={[
              [<Text weight="medium">create_inventory --profile</Text>, <Text>Start of new course</Text>, <Text>inventory · group_vars · site.yml</Text>],
              [<Text weight="medium">get_ssl_certs</Text>, <Text>Before AWX build</Text>, <Text>files/ssl/*.pem</Text>],
              [<Text weight="medium">dle-doit</Text>, <Text>Heat generation</Text>, <Text>rh{"{SKU}"}-{"{ver}"}-{"{type}"}.yaml</Text>],
            ]} />
          </CardBody>
        </Card>
      </Grid>
      <Callout tone="info" title="IdM SSL on AWX">
        Collection imports use inventory_dir for PEM paths — not playbook_dir. Commit files/ssl/ to git for project sync.
      </Callout>
      <Grid columns={3} gap={16}>
        <Stat label="rhel-basic · aap-snap · aap-mesh · ocp · full" value="5 profiles" />
        <Stat label="Every job runs in an Execution Environment container" value="EE" tone="success" />
        <Stat label="collections/requirements.yml at repo root" value="Galaxy sync" />
      </Grid>
      <CollapsibleSection title="Automation Controller details" defaultOpen={false}>
        <Text size="small">
          Production builds always run on AAP — not local ansible-playbook. GitHub project sync → /runner/project/.
          Collections install to /runner/requirements_collections/ inside the EE.
        </Text>
      </CollapsibleSection>
    </Stack>
  );
}
