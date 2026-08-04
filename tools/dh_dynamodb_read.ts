import { tool } from "@opencode-ai/plugin"
import { s, e, r, getLauncher, redact } from "./_helpers.js"

export default tool({
  description: "DynamoDB GetItem/Query/Scan via dh-data executor (read-only)",
  args: {
    profile: s().describe("AWS profile name"),
    operation: e(["GetItem", "Query", "Scan"]).describe("DynamoDB read operation"),
    tableName: s().describe("DynamoDB table name"),
    params: r().describe("Operation parameters (key, filter, limit, etc.)"),
  },
  async execute(args) {
    const payload = JSON.stringify({
      tool: "dynamodb-read",
      profile: args.profile,
      operation: args.operation,
      params: { tableName: args.tableName, ...args.params },
    })
    try {
      const ctrl = new AbortController()
      const timer = setTimeout(() => ctrl.abort(), 30_000)
      const proc = Bun.spawn([getLauncher()], {
        stdin: new Blob([payload]),
        stdout: "pipe",
        stderr: "pipe",
        signal: ctrl.signal,
      })
      const [stdout, stderr] = await Promise.all([
        Bun.readableStreamToText(proc.stdout),
        Bun.readableStreamToText(proc.stderr),
      ])
      clearTimeout(timer)
      const exitCode = await proc.exited
      if (exitCode === 0) return stdout.trim()
      try {
        const parsed = JSON.parse(stdout.trim())
        return JSON.stringify(parsed)
      } catch {
        const sanitised = redact(stderr.trim())
        return JSON.stringify({ error: sanitised || `executor exited (${exitCode})` })
      }
    } catch {
      return JSON.stringify({ error: "executor failed" })
    }
  },
})
