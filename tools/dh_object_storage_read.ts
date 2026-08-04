import { tool } from "@opencode-ai/plugin"

export default tool({
  description: "Read an object from S3-compatible storage via dh-data executor",
  args: {
    profile: tool.schema.string().describe("Profile ID from connections.yaml"),
    bucket: tool.schema.string().describe("S3 bucket name"),
    key: tool.schema.string().describe("Object key (path within bucket)"),
  },
  async execute(args) {
    const payload = JSON.stringify({
      tool: "object-storage-read",
      profile: args.profile,
      operation: "get-object",
      params: { bucket: args.bucket, key: args.key },
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
