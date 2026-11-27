#requires -Version 5.1
<#
.SYNOPSIS
    Connect the local Desktop Terminal Sync stdio MCP server to an OpenAI Secure MCP Tunnel.
.NOTES
    ChatGPT custom MCP availability depends on workspace authorization.
    Requires tunnel-client.exe from the official OpenAI Platform tunnel page,
    a tunnel_id, and a runtime API key with Tunnels Read + Use.
    API keys are prompted at runtime, never saved in the repository or config.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidatePattern('^tunnel_[A-Za-z0-9_-]+$')][string]$TunnelId,
    [string]$ServerDirectory = (Join-Path $env:LOCALAPPDATA 'DesktopTerminalSync')
)
$ErrorActionPreference='Stop'
$server = Join-Path $ServerDirectory 'dist\index.js'
if (-not (Test-Path -LiteralPath $server)) { throw 'Install and build Desktop Terminal Sync first.' }
$tunnel = Get-Command tunnel-client -ErrorAction SilentlyContinue
if (-not $tunnel) {
    Write-Host 'Download tunnel-client for Windows from your OpenAI Platform organization Tunnels page:' -ForegroundColor Yellow
    Write-Host 'https://platform.openai.com/settings/organization/tunnels'
    Write-Host 'Put tunnel-client.exe on your PATH, reopen PowerShell, then rerun.'
    throw 'tunnel-client not found'
}
Write-Host 'Using private OpenAI Secure MCP Tunnel. No public inbound port is opened.' -ForegroundColor Cyan
Write-Host 'Your API key will not be written to disk by this script.'
$sec = Read-Host 'OpenAI tunnel runtime API key' -AsSecureString
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
try {
    $env:CONTROL_PLANE_API_KEY = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    $sec.Dispose()
}
$env:DESKTOP_TERMINAL_SYNC_DISABLE_TELEMETRY='1'
$profile = 'desktop-terminal-sync'
$cmd = "node `"$server`" --no-onboarding"
try {
    & tunnel-client help quickstart
    & tunnel-client init --sample sample_mcp_stdio_local --profile $profile --tunnel-id $TunnelId --mcp-command $cmd
    if ($LASTEXITCODE -ne 0) { throw 'Tunnel profile creation failed. Check CLI help and permissions.' }
    & tunnel-client doctor --profile $profile --explain
    if ($LASTEXITCODE -ne 0) { throw 'Tunnel diagnostics failed.' }
    Write-Host 'Tunnel health checked. Leave this terminal running and add a custom MCP plugin in ChatGPT (Connection: Tunnel).' -ForegroundColor Green
    & tunnel-client run --profile $profile
} finally {
    Remove-Item Env:\CONTROL_PLANE_API_KEY -ErrorAction SilentlyContinue
    Remove-Item Env:\DESKTOP_TERMINAL_SYNC_DISABLE_TELEMETRY -ErrorAction SilentlyContinue
}
