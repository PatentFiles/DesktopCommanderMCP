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
    [string]$ServerDirectory = (Join-Path $env:LOCALAPPDATA 'DesktopTerminalSync'),
    [switch]$UseClipboardKey
)
$ErrorActionPreference='Stop'
$server = Join-Path $ServerDirectory 'dist\index.js'
if (-not (Test-Path -LiteralPath $server)) { throw 'Install and build Desktop Terminal Sync first.' }
# Prefer PATH; also support the bundled Windows ZIP installation without a permanent PATH edit.
$tunnel = Get-Command tunnel-client -ErrorAction SilentlyContinue
$tunnelExe = if ($tunnel) { $tunnel.Source } else { $null }
if (-not $tunnelExe) {
    $binDir = Join-Path $ServerDirectory 'TunnelClient'
    if (Test-Path -LiteralPath $binDir) {
        $found = Get-ChildItem -LiteralPath $binDir -Filter 'tunnel-client.exe' -Recurse -File |
            Select-Object -First 1
        if ($found) { $tunnelExe = $found.FullName }
    }
}
if (-not $tunnelExe) {
    throw "tunnel-client.exe was not found in PATH or $ServerDirectory\TunnelClient. Install the Windows release first."
}
Write-Host 'Using private OpenAI Secure MCP Tunnel. No public inbound port is opened.' -ForegroundColor Cyan
Write-Host 'Your API key will not be written to disk by this script.'
# Windows PowerShell 5.1's secure console paste may insert incomplete text.
# -UseClipboardKey reads a freshly copied key without putting it in command history.
# Never print the key; clear the clipboard after transferring it to this process.
if ($UseClipboardKey) {
    Write-Host 'Copy the complete runtime API key in your browser, then come back and press Enter here. Do not paste it into PowerShell.' -ForegroundColor Cyan
    [void](Read-Host 'Press Enter after copying your key')
    $key = (Get-Clipboard -Raw)
    if ($null -eq $key) { $key = '' }
    $key = $key.Trim()
    $hasPrefix = $key.StartsWith('sk-', [StringComparison]::Ordinal)
    if (-not $hasPrefix -or $key.Length -lt 20 -or $key.Contains([char]10) -or $key.Contains([char]13)) {
        Remove-Variable key -ErrorAction SilentlyContinue
        throw 'Clipboard does not contain a complete OpenAI runtime API key (expected sk-...); copy the runtime key again from OpenAI Platform > Organization > API Keys.'
    }
    $env:CONTROL_PLANE_API_KEY = $key
    Remove-Variable key -ErrorAction SilentlyContinue
    Set-Clipboard -Value '' # Avoid leaving the key exposed in clipboard history.
} else {
    $sec = Read-Host 'OpenAI tunnel runtime API key' -AsSecureString
    if ($sec.Length -lt 20) { throw 'Pasted key appears incomplete. Re-run with -UseClipboardKey after copying the complete runtime key.' }
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    try {
        $env:CONTROL_PLANE_API_KEY = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        $sec.Dispose()
    }
}
$env:DESKTOP_TERMINAL_SYNC_DISABLE_TELEMETRY='1'
$profile = 'desktop-terminal-sync'
$serverForMcp = ([System.IO.Path]::GetFullPath($server)).Replace([char]92, [char]47)
$cmd = "node `"$serverForMcp`" --no-onboarding"
try {
    & $tunnelExe init --sample sample_mcp_stdio_local --profile $profile --tunnel-id $TunnelId --mcp-command $cmd
    if ($LASTEXITCODE -ne 0) { throw 'Tunnel profile creation failed. Check CLI help and permissions.' }
    & $tunnelExe doctor --profile $profile --explain
    if ($LASTEXITCODE -ne 0) { throw 'Tunnel diagnostics failed.' }
    Write-Host 'Tunnel health checked. Leave this terminal running and add a custom MCP plugin in ChatGPT (Connection: Tunnel).' -ForegroundColor Green
    & $tunnelExe run --profile $profile
} finally {
    Remove-Item Env:\CONTROL_PLANE_API_KEY -ErrorAction SilentlyContinue
    Remove-Item Env:\DESKTOP_TERMINAL_SYNC_DISABLE_TELEMETRY -ErrorAction SilentlyContinue
}
