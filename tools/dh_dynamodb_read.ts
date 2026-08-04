import { tool } from "@opencode-ai/plugin"

export default tool({
  description: "DynamoDB GetItem/Query/Scan via dh-data executor (read-only)",
  args: {
    profile: tool.schema.string().describe("AWS profile name"),
    operation: tool.schema.enum(["GetItem", "Query", "Scan"]).describe("DynamoDB read operation"),
    tableName: tool.schema.string().describe("DynamoDB table name"),
    params: tool.schema.record(tool.schema.unknown()).describe("Operation parameters (key, filter, limit, etc.)"),
  },
  async execute(args) {
    const payload = JSON.stringify({
      tool: "dynamodb-read",
      profile: args.profile,
      operation: args.operation,
      params: { tableName: args.tableName, ...args.params },
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
