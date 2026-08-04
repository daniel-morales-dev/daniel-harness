import { tool } from "@opencode-ai/plugin"
import { s, r, a, getLauncher, redact } from "./_helpers.js"

export default tool({
  description: "Read-only MongoDB find/aggregate via dh-data executor",
  args: {
    profile: s().describe("Profile ID from connections.yaml"),
    collection: s().describe("Collection name"),
    filter: r().optional().describe("Query filter"),
    projection: r().optional().describe("Field projection"),
    pipeline: a(r()).optional().describe("Aggregation pipeline stages"),
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
