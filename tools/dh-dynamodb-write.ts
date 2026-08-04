// dh-dynamodb-write.ts — OpenCode custom tool for DynamoDB writes with 2-step confirmation
import { z } from "zod";

const writeSchema = z.object({
  profile: z.string(),
  operation: z.enum(["PutItem", "UpdateItem"]),
  tableName: z.string(),
  keys: z.record(z.unknown()),
  fields: z.record(z.unknown()),
  condition: z.string().optional(),
});

const confirmSchema = z.object({
  token: z.string(),
  profile: z.string(),
  operation: z.enum(["PutItem", "UpdateItem"]),
  tableName: z.string(),
  keys: z.record(z.unknown()),
  fields: z.record(z.unknown()),
});

const outputData = z.object({
  attributes: z.record(z.unknown()).optional(),
  confirmationRequired: z.boolean().optional(),
  preview: z.record(z.unknown()).optional(),
  token: z.string().optional(),
});

export default {
  name: "dh_dynamodb_write",
  description: "DynamoDB PutItem/UpdateItem with 2-step confirmation via dh-data executor",
  input: z.union([writeSchema, confirmSchema]),
  output: outputData,
  execute: async (args: unknown) => {
    const { execSync } = await import("child_process");
    const isConfirm = typeof args === "object" && args !== null && "token" in args;
    const payload = JSON.stringify({
      tool: "dynamodb-write",
      profile: isConfirm ? (args as any).profile : (args as any).profile,
      operation: isConfirm ? "confirm" : "prepare",
      params: args,
    });
    const result = execSync(`python3 scripts/dh_data/executor.py`, {
      input: payload, encoding: "utf-8", maxBuffer: 10 * 1024 * 1024, timeout: 30_000,
    });
    return JSON.parse(result);
  },
};
