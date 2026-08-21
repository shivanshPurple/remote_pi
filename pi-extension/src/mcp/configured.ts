import { homedir } from "node:os";
import { join } from "node:path";
import { readFileSync } from "node:fs";

/**
 * Names of MCP servers configured for a Pi session.
 *
 * Pi loads (in order, later files overlay) the global agent config and any
 * project-local file. We only need the *names* for Home chips — never the
 * command/args/env, which must stay on the host.
 *
 * Sources, matching Pi's own lookup:
 *   ~/.pi/agent/mcp.json          (global)
 *   <cwd>/.pi/mcp.json            (project)
 *   <cwd>/.mcp.json               (Claude-style project file)
 */
export function listConfiguredMcp(cwd: string): string[] {
  const names = new Set<string>();
  const files = [
    join(homedir(), ".pi", "agent", "mcp.json"),
    join(cwd, ".pi", "mcp.json"),
    join(cwd, ".mcp.json"),
  ];
  for (const file of files) {
    for (const k of _serverNamesFromFile(file)) names.add(k);
  }
  return [...names].sort();
}

function _serverNamesFromFile(file: string): string[] {
  let raw: unknown;
  try {
    raw = JSON.parse(readFileSync(file, "utf8")) as unknown;
  } catch {
    return [];
  }
  if (!raw || typeof raw !== "object") return [];
  const obj = raw as Record<string, unknown>;
  const servers = obj.mcpServers ?? obj.servers;
  if (!servers || typeof servers !== "object" || Array.isArray(servers)) {
    return [];
  }
  return Object.keys(servers as Record<string, unknown>).filter(Boolean);
}
