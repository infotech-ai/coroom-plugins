#!/usr/bin/env node
// Builds plugins/coroom-staging from plugins/coroom, the one plugin edited by hand. The staging twin is the same plugin
// with the staging connector (https://staging.coroom.ai/mcp) and its own name, so both can be installed side by side.
//
//   node scripts/sync.mjs           write plugins/coroom-staging
//   node scripts/sync.mjs --check   exit 1 and list the differences when plugins/coroom-staging is out of date
//
// Zero dependencies. A test in the Coroom repository (packages/cli/test/wake.test.ts) runs --check.
import { chmodSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, relative, sep } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const SOURCE = join(ROOT, "plugins", "coroom");
const TARGET = join(ROOT, "plugins", "coroom-staging");
const PROD_MCP = "https://coroom.ai/mcp";
const STAGING_MCP = "https://staging.coroom.ai/mcp";
const STAGING_NOTE = "Staging build: connects to staging.coroom.ai, for testing Coroom before a release. ";

function walk(dir) {
  const out = [];
  for (const name of readdirSync(dir).sort()) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) out.push(...walk(p));
    else out.push(p);
  }
  return out;
}

const json = (v) => JSON.stringify(v, null, 2) + "\n";

function mcpServers(text) {
  const v = JSON.parse(text);
  const servers = {};
  for (const [name, server] of Object.entries(v.mcpServers ?? {})) {
    if (server.url !== PROD_MCP) throw new Error(`unexpected MCP url in plugins/coroom: ${server.url}`);
    servers[name === "coroom" ? "coroom-staging" : name] = { ...server, url: STAGING_MCP };
  }
  return json({ ...v, mcpServers: servers });
}

function manifest(text) {
  const v = JSON.parse(text);
  const out = { ...v, name: "coroom-staging", description: STAGING_NOTE + v.description };
  if (v.displayName) out.displayName = `${v.displayName} (staging)`;
  if (v.interface) out.interface = { ...v.interface, displayName: `${v.interface.displayName} (staging)` };
  return json(out);
}

/** The staging twin's files: relative path to { content, mode }. */
export function expected() {
  const files = new Map();
  for (const p of walk(SOURCE)) {
    const rel = relative(SOURCE, p).split(sep).join("/");
    let content = readFileSync(p, "utf8");
    if (rel === ".mcp.json" || rel === "mcp.json") content = mcpServers(content);
    else if (rel === ".claude-plugin/plugin.json" || rel === ".codex-plugin/plugin.json") content = manifest(content);
    files.set(rel, { content, mode: statSync(p).mode & 0o777 });
  }
  return files;
}

/** Differences between plugins/coroom-staging on disk and what it should be; empty when in sync. */
export function check() {
  const want = expected();
  const diffs = [];
  let have = [];
  try {
    have = walk(TARGET).map((p) => relative(TARGET, p).split(sep).join("/"));
  } catch {
    return ["plugins/coroom-staging is missing"];
  }
  for (const rel of have) if (!want.has(rel)) diffs.push(`extra: ${rel}`);
  for (const [rel, f] of want) {
    let content;
    try {
      content = readFileSync(join(TARGET, rel), "utf8");
    } catch {
      diffs.push(`missing: ${rel}`);
      continue;
    }
    if (content !== f.content) diffs.push(`differs: ${rel}`);
    else if ((statSync(join(TARGET, rel)).mode & 0o111) !== (f.mode & 0o111)) diffs.push(`mode differs: ${rel}`);
  }
  return diffs;
}

function write() {
  rmSync(TARGET, { recursive: true, force: true });
  for (const [rel, f] of expected()) {
    const p = join(TARGET, rel);
    mkdirSync(dirname(p), { recursive: true });
    writeFileSync(p, f.content);
    chmodSync(p, f.mode);
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  if (process.argv.includes("--check")) {
    const diffs = check();
    if (diffs.length) {
      console.error(`plugins/coroom-staging is out of date; run node scripts/sync.mjs\n${diffs.join("\n")}`);
      process.exit(1);
    }
    console.log("plugins/coroom-staging is in sync with plugins/coroom");
  } else {
    write();
    console.log("wrote plugins/coroom-staging");
  }
}
