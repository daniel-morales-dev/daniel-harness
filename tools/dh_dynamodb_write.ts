import { tool } from "@opencode-ai/plugin"
import { s, e, r, getLauncher, redact } from "./_helpers.js"

export default tool({
  description: "DynamoDB PutItem/UpdateItem with 2-step confirmation via dh-data executor",
  args: {
    profile: s().describe("AWS profile name"),
    operation: e(["PutItem", "UpdateItem"]).describe("DynamoDB write operation"),
    tableName: s().describe("DynamoDB table name"),
    keys: r().describe("Primary key values"),
    fields: r().optional().describe("Attributes to write"),
    condition: s().optional().describe("Optional condition expression"),
    token: s().optional().describe("Confirmation token (confirm phase only)"),
  },
  async execute(args) {
    const isConfirm = !!args.token
    const payload = JSON.stringify({
      tool: "dynamodb-write",
      profile: args.profile,
      operation: isConfirm ? "confirm" : "prepare",
      params: {
        operation: args.operation,
        tableName: args.tableName,
        keys: args.keys,
        fields: args.fields,
        condition: args.condition,
        token: args.token,
      },
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
