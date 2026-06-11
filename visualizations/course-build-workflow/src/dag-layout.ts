export type DAGLayoutOptions = {
  nodes: Array<{ id: string }>;
  edges: Array<{ from: string; to: string }>;
  direction?: "vertical" | "horizontal";
  nodeWidth?: number;
  nodeHeight?: number;
  rankGap?: number;
  nodeGap?: number;
  padding?: number;
};

export type DAGLayoutNode = { id: string; x: number; y: number; rank: number; order: number };
export type DAGLayoutEdge = {
  from: string;
  to: string;
  sourceX: number;
  sourceY: number;
  targetX: number;
  targetY: number;
  isBackEdge: boolean;
};
export type DAGLayoutRank = { rank: number; x: number; y: number; width: number; height: number; nodeIds: string[] };
export type DAGLayoutResult = {
  nodes: DAGLayoutNode[];
  edges: DAGLayoutEdge[];
  ranks: DAGLayoutRank[];
  direction: "vertical" | "horizontal";
  width: number;
  height: number;
};

export function computeDAGLayout(options: DAGLayoutOptions): DAGLayoutResult {
  const {
    nodes,
    edges,
    direction = "vertical",
    nodeWidth = 160,
    nodeHeight = 40,
    rankGap = 64,
    nodeGap = 48,
    padding = 24,
  } = options;

  const ids = nodes.map((n) => n.id);
  const rank: Record<string, number> = Object.fromEntries(ids.map((id) => [id, 0]));
  let changed = true;
  while (changed) {
    changed = false;
    for (const { from, to } of edges) {
      if (rank[to] < rank[from] + 1) {
        rank[to] = rank[from] + 1;
        changed = true;
      }
    }
  }

  const byRank = new Map<number, string[]>();
  for (const id of ids) {
    const r = rank[id];
    if (!byRank.has(r)) byRank.set(r, []);
    byRank.get(r)!.push(id);
  }

  const layoutNodes: DAGLayoutNode[] = [];
  const ranks: DAGLayoutRank[] = [];
  const horizontal = direction === "horizontal";

  for (const r of [...byRank.keys()].sort((a, b) => a - b)) {
    const col = byRank.get(r)!;
    const span = col.length * (horizontal ? nodeHeight : nodeWidth) + (col.length - 1) * nodeGap;
    col.forEach((id, order) => {
      if (horizontal) {
        const x = padding + r * (nodeWidth + rankGap);
        const y = padding + order * (nodeHeight + nodeGap);
        layoutNodes.push({ id, x, y, rank: r, order });
      } else {
        const x = padding + order * (nodeWidth + nodeGap);
        const y = padding + r * (nodeHeight + rankGap);
        layoutNodes.push({ id, x, y, rank: r, order });
      }
    });
    if (horizontal) {
      const x = padding + r * (nodeWidth + rankGap);
      ranks.push({ rank: r, x, y: padding, width: nodeWidth, height: span, nodeIds: col });
    } else {
      const y = padding + r * (nodeHeight + rankGap);
      ranks.push({ rank: r, x: padding, y, width: span, height: nodeHeight, nodeIds: col });
    }
  }

  const pos = Object.fromEntries(layoutNodes.map((n) => [n.id, n]));
  const layoutEdges: DAGLayoutEdge[] = edges.map(({ from, to }) => {
    const a = pos[from];
    const b = pos[to];
    if (horizontal) {
      return {
        from,
        to,
        sourceX: a.x + nodeWidth,
        sourceY: a.y + nodeHeight / 2,
        targetX: b.x,
        targetY: b.y + nodeHeight / 2,
        isBackEdge: false,
      };
    }
    return {
      from,
      to,
      sourceX: a.x + nodeWidth / 2,
      sourceY: a.y + nodeHeight,
      targetX: b.x + nodeWidth / 2,
      targetY: b.y,
      isBackEdge: false,
    };
  });

  const maxX = Math.max(...layoutNodes.map((n) => n.x)) + nodeWidth + padding;
  const maxY = Math.max(...layoutNodes.map((n) => n.y)) + nodeHeight + padding;

  return {
    nodes: layoutNodes,
    edges: layoutEdges,
    ranks,
    direction,
    width: maxX,
    height: maxY,
  };
}
