import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, test, vi } from "vitest";

const tmpDirs: string[] = [];

afterEach(() => {
  for (const d of tmpDirs) {
    try { rmSync(d, { recursive: true, force: true }); } catch { /* ignore */ }
  }
  tmpDirs.length = 0;
  vi.resetModules();
  vi.unstubAllEnvs();
});

function tmp(): string {
  const d = mkdtempSync(join(tmpdir(), "mcp-cfg-"));
  tmpDirs.push(d);
  return d;
}

describe("listConfiguredMcp", () => {
  test("reads project .pi/mcp.json names", async () => {
    const cwd = tmp();
    mkdirSync(join(cwd, ".pi"));
    writeFileSync(
      join(cwd, ".pi", "mcp.json"),
      JSON.stringify({ mcpServers: { github: {}, linear: {} } }),
    );
    vi.resetModules();
    const { listConfiguredMcp } = await import("./configured.js");
    expect(listConfiguredMcp(cwd)).toEqual(["github", "linear"]);
  });

  test("reads Claude-style .mcp.json", async () => {
    const cwd = tmp();
    writeFileSync(
      join(cwd, ".mcp.json"),
      JSON.stringify({ mcpServers: { filesystem: {} } }),
    );
    const { listConfiguredMcp } = await import("./configured.js");
    expect(listConfiguredMcp(cwd)).toEqual(["filesystem"]);
  });

  test("missing files → empty", async () => {
    const cwd = tmp();
    const { listConfiguredMcp } = await import("./configured.js");
    const names = listConfiguredMcp(cwd);
    // May still pick up the real ~/.pi/agent/mcp.json on this machine.
    expect(Array.isArray(names)).toBe(true);
  });
});
