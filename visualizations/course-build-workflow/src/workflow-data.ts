export type Lane = "dev" | "repo" | "doit" | "aap" | "lab";

export type FlowNode = {
  id: string;
  label: string;
  detail: string;
  lane: Lane;
};

export const FLOW_NODES: FlowNode[] = [
  { id: "start", label: "New course repo", detail: "RedHatTraining/{SKU} on GitHub", lane: "repo" },
  { id: "create-inv", label: "create_inventory", detail: "Profile: rhel-basic · aap-snap · aap-mesh · ocp · full", lane: "doit" },
  { id: "scaffold", label: "Inventory scaffold", detail: "inventory · group_vars · host_vars · site.yml · course.yml", lane: "repo" },
  { id: "configure", label: "Configure course", detail: "course.yml · host groups · SSL_VMs · changeme images", lane: "dev" },
  { id: "validate", label: "validate_inventory", detail: "Schema check against profiles.yml", lane: "doit" },
  { id: "ssl", label: "get_ssl_certs", detail: "DLE-Web SSL Lab API → files/ssl/*.pem", lane: "doit" },
  { id: "heat", label: "dle-doit pipeline", detail: "Parse inventory → Heat templates (builder/dev/prod)", lane: "doit" },
  { id: "commit", label: "git commit & push", detail: "PEMs · playbooks · collections/requirements.yml", lane: "repo" },
  { id: "project-sync", label: "AAP Project sync", detail: "GitHub SCM → /runner/project/ + galaxy collections", lane: "aap" },
  { id: "ee", label: "Execution Environment", detail: "Job template · credentials · inventory · EE container", lane: "aap" },
  { id: "site", label: "site.yml", detail: "classroom/ansible-playbooks-novello/site.yml", lane: "aap" },
  { id: "components", label: "dle.components", detail: "wait · timezone · features · IdM SSL playbooks", lane: "lab" },
  { id: "course-plays", label: "Course playbooks", detail: "100_upgrade · VS Code · network_profiles · clean", lane: "lab" },
  { id: "aap-install", label: "AAP install (optional)", detail: "download_aap_bundle · install_aap2.6 · custom_ca_cert", lane: "lab" },
  { id: "done", label: "Classroom ready", detail: "Lab VMs with TLS · features · course content", lane: "lab" },
];

export const FLOW_EDGES = [
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

export const PHASES = [
  { n: 1, title: "Scaffold", subtitle: "dle-doit create_inventory" },
  { n: 2, title: "Configure", subtitle: "Inventory + IdM SSL PEMs" },
  { n: 3, title: "Artifacts", subtitle: "Heat + git push" },
  { n: 4, title: "Controller", subtitle: "GitHub project + EE" },
  { n: 5, title: "Provision", subtitle: "site.yml playbooks" },
  { n: 6, title: "Complete", subtitle: "Lab classroom live" },
];

export const LANE_LABELS: Record<Lane, string> = {
  dev: "Developer",
  repo: "Course repo",
  doit: "dle-doit",
  aap: "Automation Controller",
  lab: "Lab targets",
};
