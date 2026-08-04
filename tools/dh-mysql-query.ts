// dh-mysql-query.ts — OpenCode custom tool for MySQL/MariaDB read-only queries
import { z } from "zod";

const input = z.object({
  profile: z.string().describe("Profile ID from connections.yaml"),
  sql: z.string().describe("SELECT, SHOW, DESCRIBE, EXPLAIN statement"),
  params: z.record(z.unknown()).optional().describe("Query parameters"),
});

const output = z.object({
  rows: z.array(z.record(z.unknown())).describe("Result rows"),
  truncated: z.boolean().optional().describe("True if result exceeds 1000 rows"),
});

export default {
  name: "dh_mysql_query",
  description: "Execute a read-only MySQL/MariaDB query via dh-data executor",
  input,
  output,
  execute: async ({ profile, sql, params }: z.infer<typeof input>) => {
    const { execSync } = await import("child_process");
    const input = JSON.stringify({
      tool: "mysql-query",
      profile,
      operation: "query",
      params: { sql, ...(params || {}) },
    });
    const result = execSync(`python3 scripts/dh_data/executor.py`, {
      input,
      encoding: "utf-8",
      maxBuffer: 10 * 1024 * 1024,
      timeout: 30_000,
      env: { ...process.env },
    });
    return JSON.parse(result);
  },
};
