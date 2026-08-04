import { tool } from "@opencode-ai/plugin"

export default tool({
  description: "DynamoDB PutItem/UpdateItem with 2-step confirmation via dh-data executor",
  args: {
    profile: tool.schema.string().describe("AWS profile name"),
    operation: tool.schema.enum(["PutItem", "UpdateItem"]).describe("DynamoDB write operation"),
    tableName: tool.schema.string().describe("DynamoDB table name"),
    keys: tool.schema.record(tool.schema.unknown()).describe("Primary key values"),
    fields: tool.schema.record(tool.schema.unknown()).optional().describe("Attributes to write"),
    condition: tool.schema.string().optional().describe("Optional condition expression"),
    token: tool.schema.string().optional().describe("Confirmation token (confirm phase only)"),
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
