#requires -Version 5.1
<#
Desktop Terminal Sync - user-clickable Windows launcher.
- Reuses an already-running tunnel without starting a duplicate.
- For first launch after initial setup, saves the runtime key encrypted using
  Windows Data Protection API (DPAPI) scoped to the current Windows user.
- Opens the existing stdio MCP tunnel; commands are executed by the separate
  Desktop Terminal Sync MCP server process through ChatGPT.
- No API keys or decrypted secrets are printed, logged, or committed.
#>
[CmdletBinding()]
param(
    [switch]$StatusOnly
)

$ErrorActionPreference = 'Stop'
try { $Host.UI.RawUI.WindowTitle = 'Desktop Terminal Sync' } catch { }

$root = Join-Path $env:LOCALAPPDATA 'DesktopTerminalSync'
$server = Join-Path $root 'dist\index.js'
$profile = 'desktop-terminal-sync'
$profilePath = Join-Path $env:APPDATA 'tunnel-client\desktop-terminal-sync.yaml'
$keyDir = Join-Path $env:APPDATA 'DesktopTerminalSync'
$keyFile = Join-Path $keyDir 'TunnelKey.dpapi'

function Find-DtsTunnel {
    $matches = @(Get-CimInstance Win32_Process -Filter "Name='tunnel-client.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*run*--profile*desktop-terminal-sync*' })
    if ($matches.Count -gt 0) { return $matches[0] }
    return $null
}

function Test-DtsReady {
    try {
        $r = Invoke-WebRequest -Uri 'http://127.0.0.1:8080/readyz' -UseBasicParsing -TimeoutSec 5
        return ($r.StatusCode -eq 200)
    } catch { return $false }
}

Write-Host ''
Write-Host '======================================================' -ForegroundColor Cyan
Write-Host '                  DESKTOP TERMINAL SYNC' -ForegroundColor White
Write-Host '            ChatGPT <--> Windows <--> GitHub' -ForegroundColor Cyan
Write-Host '======================================================' -ForegroundColor Cyan
Write-Host ''

$existing = Find-DtsTunnel
if ($null -ne $existing) {
    if (Test-DtsReady) {
        Write-Host 'CONNECTED: Your desktop tunnel is running and ready.' -ForegroundColor Green
    } else {
        Write-Host 'STARTED: Tunnel exists, but readiness is not yet confirmed.' -ForegroundColor Yellow
    }
    Write-Host ('Existing tunnel PID: ' + $existing.ProcessId)
    Write-Host 'No duplicate session was started.'
    Write-Host 'Keep the original tunnel PowerShell window open.'
    Write-Host 'Dashboard: http://127.0.0.1:8080/ui'
    return
}

if ($StatusOnly) {
    Write-Host 'OFFLINE: Desktop Terminal Sync tunnel is not running.' -ForegroundColor Yellow
    return
}

if (-not (Test-Path -LiteralPath $server)) { throw "MCP executable is missing: $server" }
if (-not (Test-Path -LiteralPath $profilePath)) { throw "Tunnel profile is missing: $profilePath" }

$tunnel = Get-ChildItem -LiteralPath (Join-Path $root 'TunnelClient') -Filter 'tunnel-client.exe' -Recurse -File -ErrorAction SilentlyContinue |
    Select-Object -First 1 -ExpandProperty FullName
if (-not $tunnel) {
    $found = Get-Command 'tunnel-client.exe' -ErrorAction SilentlyContinue
    if ($found) { $tunnel = $found.Source }
}
if (-not $tunnel) { throw 'Tunnel Client was not found. Reinstall the official OpenAI tunnel-client.' }

$secure = $null
try {
    if (Test-Path -LiteralPath $keyFile) {
        # Decryption is available only to the same Windows login on this machine.
        $secure = Get-Content -LiteralPath $keyFile -Raw | ConvertTo-SecureString
        Write-Host 'Secure Windows credential found (DPAPI).' -ForegroundColor Green
    } else {
        Write-Host 'ONE-TIME SETUP: Save your private runtime key for future launches.' -ForegroundColor Yellow
        Write-Host 'Copy your OpenAI tunnel runtime API key in the browser.'
        [void](Read-Host 'Return here and press Enter after copying; do not paste the key into this window')
        $clipboardKey = Get-Clipboard -Raw
        if ($null -eq $clipboardKey) { $clipboardKey = '' }
        $clipboardKey = $clipboardKey.Trim()
        if ($clipboardKey.Length -lt 20 -or -not $clipboardKey.StartsWith('sk-')) {
            throw 'No valid-looking runtime API key was found on the clipboard. Copy the complete key and try again.'
        }
        $secure = ConvertTo-SecureString -String $clipboardKey -AsPlainText -Force
        New-Item -ItemType Directory -Path $keyDir -Force | Out-Null
        $cipher = ConvertFrom-SecureString -SecureString $secure
        Set-Content -LiteralPath $keyFile -Value $cipher -Encoding ASCII -NoNewline
        Remove-Variable cipher -ErrorAction SilentlyContinue
        $clipboardKey = $null
        try { Set-Clipboard -Value ' ' -ErrorAction Stop } catch { }
        Write-Host 'Encrypted credential saved for this Windows account.' -ForegroundColor Green
        Write-Host "To forget it, delete: $keyFile"
    }

    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        $env:CONTROL_PLANE_API_KEY = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }
    $env:DESKTOP_TERMINAL_SYNC_DISABLE_TELEMETRY = '1'
    Write-Host ''
    Write-Host 'Checking OpenAI tunnel settings...' -ForegroundColor Cyan
    & $tunnel doctor --profile $profile --explain
    if ($LASTEXITCODE -ne 0) {
        throw "Tunnel diagnostics failed. If your key was rotated, delete $keyFile and relaunch to save the new key."
    }
    Write-Host ''
    Write-Host 'STARTING: Desktop Terminal Sync is available to regular ChatGPT.' -ForegroundColor Green
    Write-Host 'Leave this window open while you want remote access.' -ForegroundColor Yellow
    Write-Host 'Dashboard: http://127.0.0.1:8080/ui'
    Write-Host '------------------------------------------------------'
    & $tunnel run --profile $profile
    if ($LASTEXITCODE -ne 0) { Write-Warning "Tunnel exited with code $LASTEXITCODE" }
} finally {
    Remove-Item Env:\CONTROL_PLANE_API_KEY -ErrorAction SilentlyContinue
    Remove-Item Env:\DESKTOP_TERMINAL_SYNC_DISABLE_TELEMETRY -ErrorAction SilentlyContinue
    if ($null -ne $secure) { $secure.Dispose() }
}
