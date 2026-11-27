#!/usr/bin/env node
/** Local MCP client/server smoke test. Does not execute shell or modify files. */
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import path from 'node:path';
import process from 'node:process';
const root = path.resolve(import.meta.dirname, '..', '..');
const client = new Client({ name: 'desktop-terminal-sync-smoke', version: '1.0.0' }, { capabilities: {} });
const transport = new StdioClientTransport({
  command: process.execPath,
  args: [path.join(root, 'dist', 'index.js'), '--no-onboarding'],
  env: { ...process.env, DESKTOP_TERMINAL_SYNC_DISABLE_TELEMETRY: '1' },
});
const timeout = setTimeout(() => { console.error('MCP smoke timeout'); process.exit(1); }, 20_000);
try {
  await client.connect(transport);
  const result = await client.listTools();
  const names = new Set(result.tools.map((x) => x.name));
  for (const required of ['read_file', 'write_file', 'start_process', 'list_directory']) {
    if (!names.has(required)) throw new Error(`MCP missing tool: ${required}`);
  }
  console.log(`MCP handshake successful; ${names.size} tools available.`);
} finally {
  clearTimeout(timeout);
  await client.close().catch(() => {});
}
