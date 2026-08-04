// dh-mongodb-query.ts — OpenCode custom tool for MongoDB read-only queries
import { z } from "zod";

const input = z.object({
  profile: z.string(),
  collection: z.string(),
  filter: z.record(z.unknown()).optional().default({}),
  projection: z.record(z.unknown()).optional(),
  pipeline: z.array(z.record(z.unknown())).optional(),
});

const output = z.object({
  documents: z.array(z.record(z.unknown())),
  truncated: z.boolean().optional(),
});

export default {
  name: "dh_mongodb_query",
  description: "Read-only MongoDB find/aggregate via dh-data executor",
  input,
  output,
  execute: async (args: z.infer<typeof input>) => {
    const { execSync } = await import("child_process");
    const payload = JSON.stringify({
      tool: "mongodb-query",
      profile: args.profile,
      operation: args.pipeline ? "aggregate" : "find",
      params: {
        collection: args.collection,
        filter: args.filter,
        projection: args.projection,
        pipeline: args.pipeline,
      },
    });
    const result = execSync(`python3 scripts/dh_data/executor.py`, {
      input: payload, encoding: "utf-8", maxBuffer: 10 * 1024 * 1024, timeout: 30_000,
    });
    return JSON.parse(result);
  },
};
