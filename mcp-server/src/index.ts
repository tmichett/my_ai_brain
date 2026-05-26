import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { createClient } from "@supabase/supabase-js";
import { z } from "zod";

const SUPABASE_URL = process.env.SUPABASE_URL || "http://127.0.0.1:54321";
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || "";
const OLLAMA_URL = process.env.OLLAMA_URL || "http://127.0.0.1:11434";
const OLLAMA_EMBED_MODEL = process.env.OLLAMA_EMBED_MODEL || "nomic-embed-text";

if (!SUPABASE_SERVICE_ROLE_KEY) {
  console.error("SUPABASE_SERVICE_ROLE_KEY is required");
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

type ThoughtMatch = {
  id: string;
  content: string;
  metadata: Record<string, unknown>;
  similarity: number;
  created_at: string;
};

type ThoughtRecord = {
  content: string;
  metadata: Record<string, unknown>;
  created_at: string;
};

async function getEmbedding(text: string): Promise<number[]> {
  const response = await fetch(`${OLLAMA_URL}/api/embed`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      model: OLLAMA_EMBED_MODEL,
      input: text,
    }),
  });

  if (!response.ok) {
    const msg = await response.text().catch(() => "");
    throw new Error(
      `Ollama embedding failed (${response.status}): ${msg}. Is Ollama running with model '${OLLAMA_EMBED_MODEL}' pulled?`
    );
  }

  const data = await response.json();
  return data.embeddings[0];
}

const server = new McpServer({
  name: "open-brain",
  version: "1.0.0",
});

// Tool 1: Capture Thought
server.tool(
  "capture_thought",
  "Save a new thought to the Open Brain. Generates a vector embedding and stores it for semantic retrieval. Pass metadata (topics, people, type, action_items) if available - the AI calling this tool should extract metadata from the content naturally.",
  {
    content: z
      .string()
      .describe(
        "The thought to capture - a clear, standalone statement that will make sense when retrieved later"
      ),
    topics: z
      .array(z.string())
      .optional()
      .describe("1-3 short topic tags extracted from the content"),
    type: z
      .enum(["observation", "task", "idea", "reference", "person_note", "decision", "learning"])
      .optional()
      .describe("Classification of the thought"),
    people: z
      .array(z.string())
      .optional()
      .describe("People mentioned in the thought"),
    action_items: z
      .array(z.string())
      .optional()
      .describe("Implied to-dos extracted from the content"),
    source: z
      .string()
      .optional()
      .describe("Where this thought originated (e.g. 'cursor', 'meeting', 'obsidian')"),
  },
  async ({ content, topics, type, people, action_items, source }) => {
    try {
      const embedding = await getEmbedding(content);

      const metadata: Record<string, unknown> = {
        type: type || "observation",
        topics: topics || [],
        people: people || [],
        action_items: action_items || [],
        source: source || "mcp",
      };

      const { data, error } = await supabase
        .from("thoughts")
        .insert({
          content,
          embedding: JSON.stringify(embedding),
          metadata,
        })
        .select("id")
        .single();

      if (error) {
        return {
          content: [{ type: "text" as const, text: `Failed to capture: ${error.message}` }],
          isError: true,
        };
      }

      let confirmation = `Captured thought (id: ${data.id}) as ${metadata.type}`;
      if (Array.isArray(metadata.topics) && (metadata.topics as string[]).length) {
        confirmation += ` | Topics: ${(metadata.topics as string[]).join(", ")}`;
      }
      if (Array.isArray(metadata.people) && (metadata.people as string[]).length) {
        confirmation += ` | People: ${(metadata.people as string[]).join(", ")}`;
      }
      if (Array.isArray(metadata.action_items) && (metadata.action_items as string[]).length) {
        confirmation += ` | Actions: ${(metadata.action_items as string[]).join("; ")}`;
      }

      return { content: [{ type: "text" as const, text: confirmation }] };
    } catch (err: unknown) {
      return {
        content: [{ type: "text" as const, text: `Error: ${(err as Error).message}` }],
        isError: true,
      };
    }
  }
);

// Tool 2: Search Thoughts (semantic)
server.tool(
  "search_thoughts",
  "Search captured thoughts by meaning using vector similarity. Use when looking for thoughts about a topic, person, or idea previously captured.",
  {
    query: z.string().describe("What to search for - natural language query"),
    limit: z.number().optional().default(10).describe("Max results to return"),
    threshold: z
      .number()
      .optional()
      .default(0.5)
      .describe("Minimum similarity score (0-1). Lower = more results, less relevant"),
  },
  async ({ query, limit, threshold }) => {
    try {
      const queryEmbedding = await getEmbedding(query);

      const { data, error } = await supabase.rpc("match_thoughts", {
        query_embedding: JSON.stringify(queryEmbedding),
        match_threshold: threshold,
        match_count: limit,
        filter: {},
      });

      if (error) {
        return {
          content: [{ type: "text" as const, text: `Search error: ${error.message}` }],
          isError: true,
        };
      }

      if (!data || data.length === 0) {
        return {
          content: [
            { type: "text" as const, text: `No thoughts found matching "${query}".` },
          ],
        };
      }

      const results = (data as ThoughtMatch[]).map((t, i) => {
        const m = t.metadata || {};
        const parts = [
          `--- Result ${i + 1} (${(t.similarity * 100).toFixed(1)}% match) ---`,
          `ID: ${t.id}`,
          `Captured: ${new Date(t.created_at).toLocaleDateString()}`,
          `Type: ${(m.type as string) || "unknown"}`,
        ];
        if (Array.isArray(m.topics) && m.topics.length)
          parts.push(`Topics: ${(m.topics as string[]).join(", ")}`);
        if (Array.isArray(m.people) && m.people.length)
          parts.push(`People: ${(m.people as string[]).join(", ")}`);
        if (Array.isArray(m.action_items) && m.action_items.length)
          parts.push(`Actions: ${(m.action_items as string[]).join("; ")}`);
        parts.push(`\n${t.content}`);
        return parts.join("\n");
      });

      return {
        content: [
          {
            type: "text" as const,
            text: `Found ${data.length} thought(s):\n\n${results.join("\n\n")}`,
          },
        ],
      };
    } catch (err: unknown) {
      return {
        content: [{ type: "text" as const, text: `Error: ${(err as Error).message}` }],
        isError: true,
      };
    }
  }
);

// Tool 3: List Recent Thoughts
server.tool(
  "list_thoughts",
  "List recently captured thoughts with optional filters by type, topic, person, or time range.",
  {
    limit: z.number().optional().default(10).describe("Max results"),
    type: z
      .string()
      .optional()
      .describe(
        "Filter by type: observation, task, idea, reference, person_note, decision, learning"
      ),
    topic: z.string().optional().describe("Filter by topic tag"),
    person: z.string().optional().describe("Filter by person mentioned"),
    days: z.number().optional().describe("Only thoughts from the last N days"),
  },
  async ({ limit, type, topic, person, days }) => {
    try {
      let query = supabase
        .from("thoughts")
        .select("content, metadata, created_at")
        .order("created_at", { ascending: false })
        .limit(limit);

      if (type) query = query.contains("metadata", { type });
      if (topic) query = query.contains("metadata", { topics: [topic] });
      if (person) query = query.contains("metadata", { people: [person] });
      if (days) {
        const since = new Date();
        since.setDate(since.getDate() - days);
        query = query.gte("created_at", since.toISOString());
      }

      const { data, error } = await query;

      if (error) {
        return {
          content: [{ type: "text" as const, text: `Error: ${error.message}` }],
          isError: true,
        };
      }

      if (!data || !data.length) {
        return { content: [{ type: "text" as const, text: "No thoughts found." }] };
      }

      const results = (data as ThoughtRecord[]).map((t, i) => {
        const m = t.metadata || {};
        const tags = Array.isArray(m.topics) ? (m.topics as string[]).join(", ") : "";
        return `${i + 1}. [${new Date(t.created_at).toLocaleDateString()}] (${(m.type as string) || "??"}${tags ? " - " + tags : ""})\n   ${t.content}`;
      });

      return {
        content: [
          {
            type: "text" as const,
            text: `${data.length} recent thought(s):\n\n${results.join("\n\n")}`,
          },
        ],
      };
    } catch (err: unknown) {
      return {
        content: [{ type: "text" as const, text: `Error: ${(err as Error).message}` }],
        isError: true,
      };
    }
  }
);

// Tool 4: Thought Stats
server.tool(
  "thought_stats",
  "Get a summary of all captured thoughts: totals, types, top topics, and people mentioned.",
  {},
  async () => {
    try {
      const { count } = await supabase
        .from("thoughts")
        .select("*", { count: "exact", head: true });

      const { data } = await supabase
        .from("thoughts")
        .select("metadata, created_at")
        .order("created_at", { ascending: false });

      const types: Record<string, number> = {};
      const topics: Record<string, number> = {};
      const people: Record<string, number> = {};

      for (const r of data || []) {
        const m = (r.metadata || {}) as Record<string, unknown>;
        if (m.type) types[m.type as string] = (types[m.type as string] || 0) + 1;
        if (Array.isArray(m.topics))
          for (const t of m.topics) topics[t as string] = (topics[t as string] || 0) + 1;
        if (Array.isArray(m.people))
          for (const p of m.people) people[p as string] = (people[p as string] || 0) + 1;
      }

      const sort = (o: Record<string, number>): [string, number][] =>
        Object.entries(o)
          .sort((a, b) => b[1] - a[1])
          .slice(0, 10);

      const lines: string[] = [
        `Total thoughts: ${count}`,
        `Date range: ${
          data?.length
            ? new Date(data[data.length - 1].created_at).toLocaleDateString() +
              " → " +
              new Date(data[0].created_at).toLocaleDateString()
            : "N/A"
        }`,
        "",
        "Types:",
        ...sort(types).map(([k, v]) => `  ${k}: ${v}`),
      ];

      if (Object.keys(topics).length) {
        lines.push("", "Top topics:");
        for (const [k, v] of sort(topics)) lines.push(`  ${k}: ${v}`);
      }

      if (Object.keys(people).length) {
        lines.push("", "People mentioned:");
        for (const [k, v] of sort(people)) lines.push(`  ${k}: ${v}`);
      }

      return { content: [{ type: "text" as const, text: lines.join("\n") }] };
    } catch (err: unknown) {
      return {
        content: [{ type: "text" as const, text: `Error: ${(err as Error).message}` }],
        isError: true,
      };
    }
  }
);

// Start the server
async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((err) => {
  console.error("Fatal:", err);
  process.exit(1);
});
