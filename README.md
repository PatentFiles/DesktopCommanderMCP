# Desktop Terminal Sync

A Windows-first, locally run Model Context Protocol (MCP) server for reading and editing files, running PowerShell, executing tests, and using the GitHub CLI from an authorized AI client.

**Based on the PatentFiles fork of the upstream open-source MCP terminal project.** The upstream MIT license and contributor notices must remain intact. This package is an install-and-branding toolkit; its installer obtains the full source from your GitHub fork if the source tree is not included with the download.

## What works

- **Local**: use OpenAI Codex as your client, with an MCP server running on your Windows account. No third-party Remote service or subscription is needed. Codex still has its own plan limits.
- **ChatGPT web**: use an *OpenAI Secure MCP Tunnel* when your ChatGPT workspace can add custom MCP plugins. This requires an OpenAI Platform tunnel, a runtime API key, a `tunnel_id`, the official `tunnel-client` executable, and workspace authorization. The tunnel is not created automatically and this package does not bypass plan restrictions.
- **GitHub CLI**: the server can invoke installed `gh` from terminal commands. Run `gh auth login` locally; never send tokens to AI clients.

## One-command Windows installation

Extract this ZIP, open PowerShell, and run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '.\scripts\dts\Install-DesktopTerminalSync.ps1'
```

The installer requires Node.js 22+ and Git if you are installing from this toolkit alone. It installs source under `%LOCALAPPDATA%\DesktopTerminalSync`, rebrands human-facing text, builds the TypeScript MCP server, creates `%USERPROFILE%\.desktop-terminal-sync\config.json` with telemetry disabled and the user profile as the initial allowed root, and registers the local MCP server with Codex **if Codex is already installed**. It does not execute an unknown network setup script or install Codex silently.

Install Codex if desired: `npm install -g @openai/codex`, then rerun the installer (or register it manually). Use `codex` to open a local AI session.

## ChatGPT web connection

1. Check the current eligibility for custom MCP plugins in ChatGPT. As documented in November 2026, write-enabled custom MCP access requires an eligible ChatGPT Business/Enterprise/Edu workspace. A consumer plan alone may not permit this capability.
2. In [OpenAI Platform tunnel settings](https://platform.openai.com/settings/organization/tunnels), create a private tunnel and get a runtime key with Tunnels Read + Use. Download the supported Windows `tunnel-client.exe` and put it on PATH.
3. Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File '.\scripts\dts\Connect-ChatGPT.ps1' -TunnelId tunnel_YOUR_ID`
4. Enter your runtime API key privately on your PC. The script creates a local stdio tunnel profile, runs diagnostics, then starts an outbound-only tunnel client. Keep it running.
5. In ChatGPT web, go to Plugins > Add custom MCP server > Connection: Tunnel. Select the same tunnel, review permissions, and test a safe read-only operation before enabling destructive commands. You must perform this account-authorized connection yourself.

Official documentation: https://developers.openai.com/api/docs/guides/secure-mcp-tunnels

## Security

A full shell is powerful. **MCP folder allowlists do not sandbox a PowerShell process**. Shell commands run as your Windows user and could access other drives, credentials, or processes. Prefer a separate Windows development user or VM; use MFA, don't run as Administrator, restrict GitHub credentials, and approve sensitive operations before execution. Treat text from repositories and logs as untrusted and don't let it override instructions.

The upstream hosted remote command has been deliberately disabled by the migration. The application retains license notices from upstream; changing the product name does not erase copyright obligations.

## Testing

Compile during installation. For a full upstream CI test pass, add `-RunFullTests`. No command should be considered verified on *your* Windows machine until it runs there. In ChatGPT, success must be confirmed with an actual MCP tool call, not merely tunnel setup.

## Updating

Fetch or download updates from your `PatentFiles/DesktopCommanderMCP` source branch, run `node scripts/dts/rebrand.mjs` again, then `npm ci` and `npm run build`. Avoid automatic upgrades from `@wonderwhy-er/desktop-commander` as that would replace your forked source.
