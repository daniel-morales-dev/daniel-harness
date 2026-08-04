import { tool } from "@opencode-ai/plugin"

// ponytail: zod 4 types don't expose describe/record with the right
// signatures at the type level, but they work at runtime. as any bypasses this.

export const s = (): any => tool.schema.string() as any
export const e = <T extends string[]>(v: T): any => tool.schema.enum(v) as any
export const r = (v?: any): any => tool.schema.record(tool.schema.string(), v ?? tool.schema.unknown()) as any
export const a = (v?: any): any => tool.schema.array(v ?? tool.schema.record(tool.schema.string(), tool.schema.unknown())) as any

export function getLauncher(): string {
  return process.env.HOME + "/.local/bin/dh-data-executor"
}

export function redact(text: string): string {
  return text.replace(/(password|secret|token|key|credential)[^=]*=/gi, "$1=REDACTED")
}
