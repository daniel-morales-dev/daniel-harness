import { describe, test, expect } from "bun:test"
import { mkdtempSync, mkdirSync, chmodSync } from "fs"
import { join } from "path"
import { tmpdir } from "os"

const TOOLS = ["dh_mysql_query", "dh_mongodb_query", "dh_dynamodb_read", "dh_dynamodb_write", "dh_object_storage_read"] as const

const dummyCtx = {} as any

function writeLauncher(dir: string, content: string): string {
  const binDir = join(dir, ".local", "bin")
  mkdirSync(binDir, { recursive: true })
  const p = join(binDir, "dh-data-executor")
  Bun.write(p, content)
  chmodSync(p, 0o755)
  return dir
}

async function withHome(dir: string, fn: () => Promise<void>): Promise<void> {
  const orig = process.env.HOME
  process.env.HOME = dir
  try {
    await fn()
  } finally {
    process.env.HOME = orig
  }
}

for (const name of TOOLS) {
  test(`${name}: importable and has tool() contract`, async () => {
    const mod = await import(`../../tools/${name}.ts`)
    expect(mod.default).toBeDefined()
    expect(typeof mod.default.execute).toBe("function")
    expect(typeof mod.default.description).toBe("string")
    expect(mod.default.args).toBeDefined()
  })
}

test("tool sends JSON to launcher via stdin", async () => {
  const dir = writeLauncher(mkdtempSync(join(tmpdir(), "dh-stdin-")),
    '#!/usr/bin/env bash\nread -r L\necho \'{"received":true}\'\nexit 0\n')
  await withHome(dir, async () => {
    const mod = await import("../../tools/dh_mysql_query.ts")
    const result = await mod.default.execute({ profile: "test", sql: "SELECT 1", params: {} }, dummyCtx)
    const parsed = JSON.parse(result as string)
    expect(parsed.received).toBe(true)
  })
})

for (const code of [2, 3, 4]) {
  test(`exit code ${code}: preserves executor JSON`, async () => {
    const json = `{"status":"code-${code}","detail":"ok"}`
    const dir = writeLauncher(mkdtempSync(join(tmpdir(), "dh-code-")),
      `#!/usr/bin/env bash\necho '${json}'\nexit ${code}\n`)
    await withHome(dir, async () => {
      const mod = await import("../../tools/dh_mysql_query.ts")
      const result = await mod.default.execute({ profile: "x", sql: "SELECT 1", params: {} }, dummyCtx)
      const parsed = JSON.parse(result as string)
      expect(parsed.status).toBe(`code-${code}`)
      expect(parsed.detail).toBe("ok")
    })
  })
}

test("invalid JSON stdout returns controlled error", async () => {
  const dir = writeLauncher(mkdtempSync(join(tmpdir(), "dh-inv-")),
    "#!/usr/bin/env bash\necho 'not-json'\nexit 1\n")
  await withHome(dir, async () => {
    const mod = await import("../../tools/dh_mysql_query.ts")
    const result = await mod.default.execute({ profile: "x", sql: "SELECT 1", params: {} }, dummyCtx)
    const parsed = JSON.parse(result as string)
    expect(parsed.error).toBeDefined()
  })
})

test("timeout kills long-running process", async () => {
  const dir = writeLauncher(mkdtempSync(join(tmpdir(), "dh-timeout-")),
    "#!/usr/bin/env bash\nsleep 35\necho 'slow'\n")
  const start = Date.now()
  await withHome(dir, async () => {
    const mod = await import("../../tools/dh_mysql_query.ts")
    const result = await mod.default.execute({ profile: "x", sql: "SELECT 1", params: {} }, dummyCtx)
    const elapsed = Date.now() - start
    const parsed = JSON.parse(result as string)
    expect(parsed.error).toBeDefined()
    expect(elapsed).toBeGreaterThan(28_000)
    expect(elapsed).toBeLessThan(40_000)
  })
}, 45_000)
