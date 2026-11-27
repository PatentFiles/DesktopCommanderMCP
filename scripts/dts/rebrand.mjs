#!/usr/bin/env node
/**
 * Desktop Terminal Sync: repeatable, non-destructive source branding migration.
 * Run from repository root or pass --root <dir>.
 * Keeps upstream MIT copyright/attribution untouched.
 * Does NOT contact any hosted remote-broker service.
 */
import { readFile, writeFile, readdir, stat } from 'node:fs/promises';
import path from 'node:path';

const rootArg = process.argv.indexOf('--root');
const root = path.resolve(rootArg < 0 ? path.join(import.meta.dirname, '..', '..') : process.argv[rootArg + 1]);
const dry = process.argv.includes('--check');
const clean = process.argv.includes('--clean-legacy-docs');
const skipDirs = new Set(['.git','node_modules','dist','coverage','.next','build','.turbo','vendor']);
const namesToSkip = new Set(['LICENSE','NOTICE','THIRD_PARTY_NOTICES.md']);
const allowed = new Set(['.ts','.tsx','.js','.mjs','.cjs','.json','.md','.txt','.html','.css','.svg','.yml','.yaml','.ps1','.cmd','.sh','.toml']);
const changes = [];

async function update(rel, transform) {
  const full = path.join(root, rel);
  let old;
  try { old = await readFile(full, 'utf8'); } catch (e) { if (e.code === 'ENOENT') return; throw e; }
  const next = transform(old);
  if (next !== old) {
    changes.push(rel);
    if (!dry) await writeFile(full, next, 'utf8');
  }
}

async function walk(folder = '') {
  const entries = await readdir(path.join(root, folder), { withFileTypes: true });
  for (const entry of entries) {
    if (entry.isSymbolicLink()) continue;
    const rel = path.join(folder, entry.name);
    if (entry.isDirectory()) {
      if (!skipDirs.has(entry.name)) await walk(rel);
    } else if (entry.isFile() && allowed.has(path.extname(entry.name).toLowerCase()) &&
               !namesToSkip.has(entry.name) && !rel.includes('scripts/dts/rebrand.mjs') &&
               !rel.includes('scripts\\dts\\rebrand.mjs') &&
               !rel.includes('package-lock.json')) {
      const info = await stat(path.join(root, rel));
      if (info.size > 1024 * 1024) continue;
      await update(rel, (s) => {
        // Only rebrand human-readable names, preserving source URL/package/filename dependencies.
        // An aggressive global rename of technical identifiers breaks the upstream MCP SDK.
        return s.replaceAll('Remote Desktop Commander', 'Desktop Terminal Sync Remote')
                .replaceAll('Desktop Commander MCP', 'Desktop Terminal Sync')
                .replaceAll('Desktop Commander', 'Desktop Terminal Sync')
                .replaceAll('DESKTOP COMMANDER', 'DESKTOP TERMINAL SYNC')
                .replaceAll('DESKTOP_COMMANDER_DISABLE_TELEMETRY', 'DESKTOP_TERMINAL_SYNC_DISABLE_TELEMETRY');
      });
    }
  }
}

const pkg = JSON.parse(await readFile(path.join(root, 'package.json'), 'utf8'));
if (!pkg.scripts?.build || !pkg.dependencies?.['@modelcontextprotocol/sdk']) {
  throw new Error('Not the expected upstream MCP project. Nothing changed.');
}
await walk();

// Replace the actual MCP server identity, but retain internal filenames and code exports.
await update('src/server.ts', (s) => s.replace(/name: ["']desktop-commander["']/, 'name: "desktop-terminal-sync"'));
await update('src/ui/contracts.ts', (s) => s.replaceAll('ui://desktop-commander/', 'ui://desktop-terminal-sync/'));
await update('src/config.ts', (s) => s.replaceAll('.claude-server-commander', '.desktop-terminal-sync')
  .replaceAll('claude_tool_call.log', 'desktop_terminal_sync_tool_calls.log'));

// Prevent accidentally starting the original provider's paid Remote broker.
// The official OpenAI Secure MCP Tunnel launches our local server via stdio instead.
await update('src/index.ts', (s) => {
  s = s.replace(/^import \{ runRemote \} from '\.\/npm-scripts\/remote\.js';\r?\n/m, '');
  return s.replace(/if \(process\.argv\[2\] === 'remote'\) \{\s*await runRemote\(\);\s*return;\s*\}/m,
    `if (process.argv[2] === 'remote') {\n      process.stderr.write('Desktop Terminal Sync: provider Remote is disabled. Use scripts/dts/Connect-ChatGPT.ps1 with OpenAI Secure MCP Tunnel.\\n');\n      process.exitCode = 2;\n      return;\n    }`);
});

// Disable external A/B feature flag checks on startup; no service account needed.
await update('src/index.ts', (s) => s.replace(/^(\s*)await featureFlagManager\.initialize\(\);/m,
  '$1// No upstream feature flag service required for the standalone distribution.'));

// Favor new product identity in metadata and remove the upstream install tracker.
await update('package.json', (s) => {
  const j = JSON.parse(s);
  j.name = 'desktop-terminal-sync';
  j.mcpName = 'io.github.PatentFiles/desktop-terminal-sync';
  j.description = 'Desktop Terminal Sync: private, local MCP terminal and file operations for AI clients';
  j.repository = { type: 'git', url: 'https://github.com/PatentFiles/DesktopCommanderMCP.git' };
  j.homepage = 'https://github.com/PatentFiles/DesktopCommanderMCP';
  j.bugs = 'https://github.com/PatentFiles/DesktopCommanderMCP/issues';
  j.bin = { 'desktop-terminal-sync': 'dist/index.js' };
  j.scripts.postinstall = 'node -e "console.log(\'Desktop Terminal Sync dependencies installed\')"';
  return JSON.stringify(j, null, 2) + '\n';
});
await update('package-lock.json', (s) => {
  const j = JSON.parse(s);
  j.name = 'desktop-terminal-sync';
  if (j.packages?.['']) j.packages[''].name = 'desktop-terminal-sync';
  return JSON.stringify(j, null, 2) + '\n';
});

const unique = [...new Set(changes)].sort();
console.log(`${dry ? 'Would update' : 'Updated'} ${unique.length} tracked text files for Desktop Terminal Sync.`);
if (process.argv.includes('--verbose')) console.log(unique.join('\n'));
if (!dry && !unique.length) console.log('Already rebranded; no changes needed.');
