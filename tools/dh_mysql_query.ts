import { tool } from "@opencode-ai/plugin"

export default tool({
  description: "Execute a read-only MySQL/MariaDB query via dh-data executor",
  args: {
    profile: tool.schema.string().describe("Profile ID from connections.yaml"),
    sql: tool.schema.string().describe("SELECT, SHOW, DESCRIBE, EXPLAIN statement"),
    params: tool.schema.record(tool.schema.unknown()).optional().describe("Query parameters"),
  },
  async execute(args) {
    const payload = JSON.stringify({
      tool: "mysql-query",
      profile: args.profile,
      operation: "query",
      params: { sql: args.sql, ...(args.params || {}) },
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
