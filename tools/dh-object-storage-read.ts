// dh-object-storage-read.ts — OpenCode custom tool for S3-compatible object storage reads
import { z } from "zod";

const input = z.object({
  profile: z.string(),
  bucket: z.string(),
  key: z.string(),
});

const output = z.union([
  z.object({
    content: z.string(),
    truncated: z.boolean().optional(),
  }),
  z.object({
    metadata: z.object({
      size: z.number(),
      contentType: z.string(),
      etag: z.string().optional(),
    }),
    binary: z.literal(true),
  }),
]);

export default {
  name: "dh_object_storage_read",
  description: "Read an object from S3-compatible storage via dh-data executor",
  input,
  output,
  execute: async (args: z.infer<typeof input>) => {
    const { execSync } = await import("child_process");
    const payload = JSON.stringify({
      tool: "object-storage-read",
      profile: args.profile,
      operation: "get-object",
      params: { bucket: args.bucket, key: args.key },
    });
    const result = execSync(`python3 scripts/dh_data/executor.py`, {
      input: payload, encoding: "utf-8", maxBuffer: 10 * 1024 * 1024, timeout: 30_000,
    });
    return JSON.parse(result);
  },
};
