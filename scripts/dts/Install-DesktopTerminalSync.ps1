#requires -Version 5.1
<#
.SYNOPSIS
    Install Desktop Terminal Sync, built from the PatentFiles GitHub fork.
.DESCRIPTION
    Installs in %LOCALAPPDATA%, builds source with Node 22+, disables upstream
    hosted Remote command and telemetry, initializes a scoped configuration,
    and registers the local MCP server with OpenAI Codex if available.
    Does NOT register a remote ChatGPT plugin or create cloud API credentials.
#>
[CmdletBinding()]
param(
    [string]$InstallDirectory = (Join-Path $env:LOCALAPPDATA 'DesktopTerminalSync'),
    [string[]]$AllowedDirectories = @($env:USERPROFILE),
    [switch]$SkipCodex,
    [switch]$RunFullTests
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
function Assert-Success([string]$Step) { if ($LASTEXITCODE -ne 0) { throw "$Step failed (exit code $LASTEXITCODE)" } }
function Require-Exe([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) { throw "Missing $Name. Install it, reopen PowerShell, and rerun this installer." }
}

Write-Host '=== DESKTOP TERMINAL SYNC ===' -ForegroundColor Cyan
Require-Exe 'node'
Require-Exe 'npm.cmd'
$nodeMajor = [int](([string](& node -p 'process.versions.node')).Split('.')[0])
if ($nodeMajor -lt 22) { throw "Node.js 22 or newer required. Found $(& node -v)" }

# Prefer the complete extracted source tree; a small installer-only bundle
# instead checks out the selected GitHub branch.
$sourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
if (Test-Path (Join-Path $sourceRoot 'src\server.ts')) {
    Write-Host "Using extracted source: $sourceRoot"
    if (-not [string]::Equals($sourceRoot.TrimEnd('\'), $InstallDirectory.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) {
        New-Item -ItemType Directory -Force -Path $InstallDirectory | Out-Null
        & robocopy.exe $sourceRoot $InstallDirectory /E /NFL /NDL /NJH /NJS /NP /XD '.git' 'node_modules' 'dist' '.next' 'coverage' | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "Source copy failed (robocopy exit code $LASTEXITCODE)" }
    }
} else {
    Require-Exe 'git'
    $gitDir = Join-Path $InstallDirectory '.git'
    if (Test-Path $gitDir) {
        Write-Host 'Existing checkout detected; retaining it (no automatic destructive update).'
    } elseif (Test-Path $InstallDirectory) {
        if (@(Get-ChildItem -LiteralPath $InstallDirectory -Force).Count -gt 0) {
            throw "Destination is not empty and is not a Git checkout: $InstallDirectory"
        }
    }
    if (-not (Test-Path $gitDir)) {
        & git clone --branch desktop-terminal-sync --single-branch 'https://github.com/PatentFiles/DesktopCommanderMCP.git' $InstallDirectory
        Assert-Success 'Git clone'
    }
}
if (-not (Test-Path (Join-Path $InstallDirectory 'package.json'))) { throw 'Missing source package.json' }
Set-Location $InstallDirectory

# Idempotent source migration; the source checkout remains independent of npm registry publication.
$rebrand = Join-Path $InstallDirectory 'scripts\dts\rebrand.mjs'
if (-not (Test-Path $rebrand)) { throw "Missing rebrand script: $rebrand" }
& node $rebrand
Assert-Success 'Source rebrand'

# Never run the inherited upstream install analytics hook. npm package scripts
# were already replaced by the migration. Runtime telemetry is disabled below.
Write-Host 'Installing Node packages and compiling MCP server...'
& npm.cmd ci --no-audit --no-fund
Assert-Success 'npm ci'
& npm.cmd run build
Assert-Success 'npm run build'
if ($RunFullTests) {
    & npm.cmd run test:ci
    Assert-Success 'npm run test:ci'
}
if (-not (Test-Path (Join-Path $InstallDirectory 'dist\index.js'))) { throw 'No compiled MCP entry point found' }
& node --check (Join-Path $InstallDirectory 'dist\index.js')
Assert-Success 'Compiled entry point syntax check'

# Save settings in a separate product folder; no copied authentication keys.
$configDir = Join-Path $env:USERPROFILE '.desktop-terminal-sync'
New-Item -ItemType Directory -Path $configDir -Force | Out-Null
$configPath = Join-Path $configDir 'config.json'
$roots = @($AllowedDirectories | ForEach-Object {
    $p = [Environment]::ExpandEnvironmentVariables($_)
    if (Test-Path -LiteralPath $p -PathType Container) { [IO.Path]::GetFullPath($p) }
} | Select-Object -Unique)
if ($roots.Count -eq 0) { throw 'No allowed directories exist on this PC.' }
if (-not (Test-Path -LiteralPath $configPath)) {
    $config = [ordered]@{
        allowedDirectories = $roots
        defaultShell = 'powershell.exe'
        telemetryEnabled = $false
        welcomeOnboardingEligible = $false
        pendingWelcomeOnboarding = $false
    }
    [IO.File]::WriteAllText($configPath, ($config | ConvertTo-Json -Depth 5), [System.Text.UTF8Encoding]::new($false))
    Write-Host "Created scoped configuration: $configPath"
} else {
    # Protect user preferences; only enforce disabled telemetry on reinstallation.
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    $config | Add-Member -NotePropertyName 'telemetryEnabled' -NotePropertyValue $false -Force
    [IO.File]::WriteAllText($configPath, ($config | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
    Write-Host 'Preserved existing configuration; telemetry remains disabled.'
}

# MCP connects over STDIO; it is launched by the client, not by double-clicking a console.
if (-not $SkipCodex) {
    $codexCmd = Get-Command codex -ErrorAction SilentlyContinue
    if ($codexCmd) {
        Write-Host 'Registering local MCP server with OpenAI Codex...'
        & codex mcp remove desktop-terminal-sync 2>$null | Out-Null
        & codex mcp add desktop-terminal-sync -- node (Join-Path $InstallDirectory 'dist\index.js') --no-onboarding
        Assert-Success 'Codex MCP registration'
    } else {
        Write-Host 'Codex not installed. Optional: npm install -g @openai/codex'
    }
}
Write-Host ''
Write-Host 'INSTALLATION COMPLETE' -ForegroundColor Green
Write-Host "Source: $InstallDirectory"
Write-Host "MCP entry: $InstallDirectory\dist\index.js"
Write-Host "Allowed folders: $($roots -join ', ')"
Write-Host 'Local chat: run codex after installation and use the desktop-terminal-sync MCP.'
Write-Host 'ChatGPT web: follow scripts\dts\Connect-ChatGPT.ps1 (requires eligible ChatGPT access + OpenAI tunnel credentials).'
Write-Host 'Terminal commands have your Windows user privileges. Use least-privilege accounts and review sensitive commands.' -ForegroundColor Yellow
