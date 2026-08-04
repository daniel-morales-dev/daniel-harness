import { tool } from "@opencode-ai/plugin"
import { s, getLauncher, redact } from "./_helpers.js"

export default tool({
  description: "Read an object from S3-compatible storage via dh-data executor",
  args: {
    profile: s().describe("Profile ID from connections.yaml"),
    bucket: s().describe("S3 bucket name"),
    key: s().describe("Object key (path within bucket)"),
  },
  async execute(args) {
    const payload = JSON.stringify({
      tool: "object-storage-read",
      profile: args.profile,
      operation: "get-object",
      params: { bucket: args.bucket, key: args.key },
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
