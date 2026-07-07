<#
.SYNOPSIS
    Downloads the latest Vencord installer from GitHub, patches Discord, and launches Discord.
    Solves the problem of Vencord breaking every time Discord updates.

.DESCRIPTION
    This script:
    1. Downloads the newest VencordInstallerCli.exe straight from the official GitHub release
    2. Runs it to patch your local Discord installation
    3. Cleans up the downloaded installer (no leftovers)
    4. Launches Discord

    Set it to run at Windows startup via Task Scheduler or Startup folder.
    Use setup.bat for automatic one-click setup.

    Logs are written to %TEMP%\VencordAutoPatcher.log

.PARAMETER Branch
    Vencord branch to install. Default: 'stable'. Other options: 'canary', 'ptb'.

.PARAMETER NoLaunch
    Skip launching Discord after patching.

.PARAMETER Help
    Show this help text.

.EXAMPLE
    .\Vencord-AutoPatcher.ps1
    Downloads latest Vencord, patches Discord (stable branch), launches Discord.

.EXAMPLE
    .\Vencord-AutoPatcher.ps1 -Branch canary -NoLaunch
    Patches Discord Canary and does not launch.

.LINK
    https://github.com/Vencord/Installer
#>

param(
    [ValidateSet("stable", "canary", "ptb")]
    [string]$Branch = "stable",
    [switch]$NoLaunch,
    [switch]$Help
)

if ($Help) {
    Get-Help -Detailed $PSCommandPath
    exit 0
}

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$logFile = Join-Path $env:TEMP "VencordAutoPatcher.log"
$installerDir = "$env:LOCALAPPDATA\VencordAutoPatcher"
$installerPath = "$installerDir\VencordInstallerCli.exe"
$installerUrl = "https://github.com/Vencord/Installer/releases/latest/download/VencordInstallerCli.exe"

# branch -> install folder under %LOCALAPPDATA%
$branchDirMap = @{
    "stable" = "Discord"
    "ptb"    = "DiscordPTB"
    "canary" = "DiscordCanary"
}

function Write-Log {
    param([string]$Message)
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$stamp  $Message" | Out-File -Append -Encoding utf8 $logFile
}

function Write-Step {
    param([string]$Num, [string]$Label)
    $msg = "[$Num] $Label"
    Write-Host $msg
    Write-Log $msg
}

Write-Log "=== Vencord Auto-Patcher started ==="
Write-Log "Branch: $Branch, NoLaunch: $NoLaunch"

try {
    New-Item -ItemType Directory -Force -Path $installerDir | Out-Null

    Write-Step "1/4" "Downloading latest Vencord installer..."
    Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath

    Write-Step "2/4" "Patching Discord ($Branch branch)..."
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & $installerPath -install -branch $Branch 2>&1 | ForEach-Object {
        $line = "$_"
        Write-Host $line
        Write-Log $line
    }
    $patchExit = $LASTEXITCODE
    $ErrorActionPreference = $prev
    if ($patchExit -ne 0) { throw "Installer exited with code $patchExit" }

    Write-Step "3/4" "Cleaning up..."
    Remove-Item -Force $installerPath -ErrorAction SilentlyContinue

    if ($NoLaunch) {
        Write-Step "4/4" "Skipping Discord launch (-NoLaunch set)"
    }
    else {
        Write-Step "4/4" "Launching Discord ($Branch)..."
        $dirName = $branchDirMap[$Branch]
        $updater = "$env:LOCALAPPDATA\$dirName\Update.exe"
        if (Test-Path $updater) {
            Start-Process -FilePath $updater -ArgumentList "--processStart", "$dirName.exe"
        }
        else {
            Write-Warning "$dirName Update.exe not found. Is that Discord branch installed?"
            Write-Log "WARN: $updater not found"
        }
    }

    Write-Log "=== Done ==="
}
catch {
    Write-Log "ERROR: $_"
    Remove-Item -Force $installerPath -ErrorAction SilentlyContinue
    throw
}
