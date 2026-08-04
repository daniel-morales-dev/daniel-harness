import { tool } from "@opencode-ai/plugin"

export default tool({
  description: "Read-only MongoDB find/aggregate via dh-data executor",
  args: {
    profile: tool.schema.string().describe("Profile ID from connections.yaml"),
    collection: tool.schema.string().describe("Collection name"),
    filter: tool.schema.record(tool.schema.unknown()).optional().describe("Query filter"),
    projection: tool.schema.record(tool.schema.unknown()).optional().describe("Field projection"),
    pipeline: tool.schema.array(tool.schema.record(tool.schema.unknown())).optional().describe("Aggregation pipeline stages"),
  },
  async execute(args) {
    const payload = JSON.stringify({
      tool: "mongodb-query",
      profile: args.profile,
      operation: args.pipeline ? "aggregate" : "find",
      params: {
        collection: args.collection,
        filter: args.filter ?? {},
        projection: args.projection,
        pipeline: args.pipeline,
      },
    })
    const launcher = process.env.HOME + "/.local/bin/dh-data-executor"
    try {
      const proc = Bun.spawn([launcher], { input: payload, stdout: "pipe", stderr: "pipe" })
      const [stdout, stderr] = await Promise.all([
        Bun.readableStreamToText(proc.stdout),
        Bun.readableStreamToText(proc.stderr),
      ])
      const exitCode = await proc.exited
      if (exitCode !== 0) {
        try { return JSON.stringify(JSON.parse(stdout)) } catch { return JSON.stringify({ error: stderr || "executor exited " + exitCode }) }
      }
      return stdout.trim()
    } catch (e) {
      return JSON.stringify({ error: "executor failed: " + (e instanceof Error ? e.message : String(e)) })
    }
  },
})
