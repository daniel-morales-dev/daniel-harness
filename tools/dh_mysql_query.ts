import { tool } from "@opencode-ai/plugin"
import { s, r, getLauncher, redact } from "./_helpers.js"

export default tool({
  description: "Execute a read-only MySQL/MariaDB query via dh-data executor",
  args: {
    profile: s().describe("Profile ID from connections.yaml"),
    sql: s().describe("SELECT, SHOW, DESCRIBE, EXPLAIN statement"),
    params: r().optional().describe("Query parameters"),
  },
  async execute(args) {
    const payload = JSON.stringify({
      tool: "mysql-query",
      profile: args.profile,
      operation: "query",
      params: { sql: args.sql, ...(args.params || {}) },
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
