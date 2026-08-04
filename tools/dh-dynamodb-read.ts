// dh-dynamodb-read.ts — OpenCode custom tool for DynamoDB read-only operations
import { z } from "zod";

const input = z.object({
  profile: z.string(),
  operation: z.enum(["GetItem", "Query", "Scan"]),
  tableName: z.string(),
  params: z.record(z.unknown()),
});

const output = z.object({
  items: z.array(z.record(z.unknown())),
  count: z.number().optional(),
  truncated: z.boolean().optional(),
});

export default {
  name: "dh_dynamodb_read",
  description: "DynamoDB GetItem/Query/Scan via dh-data executor (read-only)",
  input,
  output,
  execute: async (args: z.infer<typeof input>) => {
    const { execSync } = await import("child_process");
    const payload = JSON.stringify({
      tool: "dynamodb-read",
      profile: args.profile,
      operation: args.operation,
      params: { tableName: args.tableName, ...args.params },
    });
    const result = execSync(`python3 scripts/dh_data/executor.py`, {
      input: payload, encoding: "utf-8", maxBuffer: 10 * 1024 * 1024, timeout: 30_000,
    });
    return JSON.parse(result);
  },
};
